# Plano — Coleta de posição em background (iOS)

**Fork:** `northonBarbosa/flutter-geolocator-azs` (base: `baseflow/flutter-geolocator`)
**Escopo desta fase:** iOS apenas. Android é a próxima fase (ver §7). O fork não suporta mais web/windows/linux — esses pacotes foram removidos do repositório.
**Data:** 2026-07-31

## Decisões de arquitetura (fechadas)

| Decisão | Escolha |
|---|---|
| Nível de background | **Nível 2** — sobrevive a suspensão *e* a terminação pelo sistema |
| Destino dos dados | **Buffer nativo persistente** (SQLite), drenado pelo Dart |
| iOS mínimo | **iOS 14+**, com caminho otimizado quando iOS 17+ |

---

## 1. Diagnóstico — o que existe hoje e por que não atende

O plugin hoje tem exatamente **um** modo de operação em background, e ele é frágil.

### 1.1 O que já funciona

Em [GeolocationHandler.m:130-134](../geolocator_apple/darwin/geolocator_apple/Sources/geolocator_apple/Handlers/GeolocationHandler.m#L130-L134):

```objc
locationManager.allowsBackgroundLocationUpdates = allowBackgroundLocationUpdates
  && [GeolocationHandler shouldEnableBackgroundLocationUpdates];
locationManager.showsBackgroundLocationIndicator = showBackgroundLocationIndicator;
```

Isso, combinado com `AppleSettings(allowBackgroundLocationUpdates: true)` ([apple_settings.dart:46](../geolocator_apple/lib/src/types/apple_settings.dart#L46)) e `UIBackgroundModes: [location]` no `Info.plist`, mantém o `CLLocationManager` entregando `didUpdateLocations` enquanto o app está em background.

### 1.2 Por que isso não é suficiente

**a) O ponto morre junto com a engine Flutter.**
Todo fix é entregue via `FlutterEventSink` em [PositionStreamHandler.m:79-83](../geolocator_apple/darwin/geolocator_apple/Sources/geolocator_apple/Handlers/PositionStreamHandler.m#L79-L83). Se o iOS mata o app (jetsam por pressão de memória, o que é rotina após alguns minutos em background), `_eventSink` deixa de existir e **todas as posições subsequentes são perdidas silenciosamente**. Não há persistência em lugar nenhum do pacote nativo.

**b) O plugin não sabe que foi relançado.**
[GeolocatorPlugin.m:29-48](../geolocator_apple/darwin/geolocator_apple/Sources/geolocator_apple/GeolocatorPlugin.m#L29-L48) nunca chama `[registrar addApplicationDelegate:instance]`. Sem isso o plugin não recebe `application:didFinishLaunchingWithOptions:` e portanto **não consegue detectar `UIApplicationLaunchOptionsLocationKey`** — a chave que o iOS usa para avisar "relancei você por causa de um evento de localização". Sem essa detecção, relaunch em background é inútil: o app acorda e não faz nada.

**c) Não existe nenhum gatilho que sobreviva à terminação.**
Não há `startMonitoringSignificantLocationChanges`, nem region monitoring, nem `startMonitoringVisits`. `startUpdatingLocation` sozinho **não relança** um app terminado. Esses três são as únicas APIs do CoreLocation que relançam o processo.

**d) Não há como pedir permissão `Always`.**
[PermissionHandler.m:72-79](../geolocator_apple/darwin/geolocator_apple/Sources/geolocator_apple/Handlers/PermissionHandler.m#L72-L79) só chama `requestAlwaysAuthorization` se `NSLocationWhenInUseUsageDescription` **não** existir no plist — ou seja, na prática nunca, porque todo app de localização declara essa chave. E `cleanUp` ([PermissionHandler.m:119-123](../geolocator_apple/darwin/geolocator_apple/Sources/geolocator_apple/Handlers/PermissionHandler.m#L119-L123)) destrói o `CLLocationManager` após o primeiro callback, o que impossibilita o fluxo de dois passos (`WhenInUse` → `Always`) que o iOS exige.

**e) Não há estado persistido do tracking.**
Depois de um relaunch, o plugin não tem como saber que o tracking estava ligado, nem com quais parâmetros. Nada é gravado.

**f) O `pausesLocationUpdatesAutomatically` é uma armadilha.**
Se `true`, o iOS pausa os updates quando julga que o device parou — e a retomada depende de `locationManagerDidPauseLocationUpdates:`, que o plugin não implementa. Resultado: tracking morre e não volta.

### 1.3 Conclusão

Não é ajuste — é **funcionalidade nova**. O modo atual (`getPositionStream`) continua existindo e intocado; vamos adicionar um subsistema paralelo de *tracking em background*.

---

## 2. Arquitetura alvo

```
                    ┌──────────────────────────────────────────┐
   App em foreground│  Dart / UI isolate                       │
                    │  Geolocator.startBackgroundTracking()    │
                    │  Geolocator.drainBufferedPositions()     │
                    └───────────────┬──────────────────────────┘
                                    │ MethodChannel + EventChannel
                    ┌───────────────▼──────────────────────────┐
                    │  GeolocatorPlugin (ObjC)                 │
                    │  + FlutterApplicationLifeCycleDelegate   │
                    └───────────────┬──────────────────────────┘
                                    │
              ┌─────────────────────▼─────────────────────┐
              │  BackgroundTrackingHandler                │
              │  (dono do CLLocationManager de background) │
              │                                            │
              │  modo continuous  → startUpdatingLocation  │
              │  modo significant → SLC + region "âncora"  │
              │  modo hybrid      → alterna entre os dois  │
              │  iOS 17+          → CLBackgroundActivity   │
              └────────┬─────────────────────┬─────────────┘
                       │                     │
          ┌────────────▼──────────┐  ┌───────▼────────────────┐
          │  PositionStore        │  │  TrackingStateStore    │
          │  SQLite (WAL)         │  │  NSUserDefaults        │
          │  fila persistente     │  │  ligado? settings?     │
          │  sobrevive a tudo     │  │  usado no auto-restart │
          └───────────────────────┘  └────────────────────────┘
```

**Princípio central:** o caminho crítico (CoreLocation → SQLite) **nunca depende da engine Flutter estar viva**. O Dart é um consumidor opcional que lê a fila quando puder.

### 2.1 Os três modos e por quê

| Modo | API iOS | Precisão | Bateria | Sobrevive à terminação |
|---|---|---|---|---|
| `continuous` | `startUpdatingLocation` | metros | alta | ❌ não relança |
| `significant` | `startMonitoringSignificantLocationChanges` | ~500m / ~5min | baixíssima | ✅ relança |
| `hybrid` (**default**) | ambos | adaptativa | média | ✅ relança |

O `hybrid` é o que resolve o problema real: mantém `continuous` ligado para ter precisão enquanto o app vive, e mantém SLC ligado **em paralelo, o tempo todo**, como rede de segurança. Se o iOS matar o app, o SLC continua armado no nível do sistema; no próximo deslocamento significativo o iOS relança o processo em background, o `BackgroundTrackingHandler` lê o `TrackingStateStore`, vê que o tracking estava ligado, e **religa o `continuous`**. O gap é de no máximo um evento de SLC.

Como reforço, no modo `hybrid` registramos também uma **região circular "âncora"** de raio configurável (ex. 100m) centrada na última posição conhecida, reposicionada a cada N metros. Region monitoring relança o app com granularidade melhor que o SLC e é a única forma de detectar movimento a partir de um ponto parado com o app morto.

---

## 3. Mudanças por pacote

### 3.1 `geolocator_platform_interface`

Nada aqui é iOS-específico: definimos o contrato para que Android possa implementar depois sem breaking change.

#### Arquivos novos

**`lib/src/models/background_tracking_settings.dart`**
Classe base com o que é comum a qualquer plataforma:
- `BackgroundTrackingMode mode` (`continuous` | `significant` | `hybrid`)
- `LocationAccuracy accuracy`
- `int distanceFilter` — filtro do CoreLocation (nível do SO, economiza bateria)
- `int minimumDistanceMeters` — filtro *nosso*, aplicado antes de gravar no SQLite. Necessário porque o `distanceFilter` do CL não se aplica ao SLC nem sobrevive a trocas de modo.
- `Duration minimumInterval` — mesmo raciocínio, no eixo tempo. Evita encher a fila parado no semáforo.
- `int maxBufferedPositions` (default 50 000) — teto da fila; ao estourar, descarta os mais antigos.
- `Duration maxPositionAge` — TTL das linhas.

*Por quê os filtros duplicados (`distanceFilter` vs `minimumDistanceMeters`)?* O `distanceFilter` do `CLLocationManager` é aplicado pelo SO e **economiza bateria** porque suprime o wake-up. Mas ele é ignorado no SLC e é resetado a cada troca de modo no `hybrid`. O `minimumDistanceMeters` é a garantia de que a fila não infla, independente de qual gatilho produziu o ponto.

**`lib/src/models/buffered_position.dart`**
`Position` + metadados de fila: `int id` (rowid do SQLite), `DateTime recordedAt` (quando o *device* gravou, distinto do `timestamp` do fix), `PositionSource source` (`continuous` | `significantChange` | `region` | `visit`), `String sessionId`.

*Por quê `id`?* Para o protocolo drain→ack (§3.2). Sem ele não dá para deletar com segurança.

**`lib/src/enums/background_tracking_mode.dart`**, **`lib/src/enums/position_source.dart`**

**`lib/src/errors/background_permission_denied_exception.dart`** — lançada quando o tracking é iniciado sem `LocationPermission.always`.
**`lib/src/errors/background_modes_not_configured_exception.dart`** — lançada quando falta `UIBackgroundModes: location` no `Info.plist`. Hoje esse erro é *silencioso*: [GeolocationHandler.m:206-208](../geolocator_apple/darwin/geolocator_apple/Sources/geolocator_apple/Handlers/GeolocationHandler.m#L206-L208) simplesmente desliga `allowsBackgroundLocationUpdates` sem avisar ninguém. É a causa nº1 de "não funciona e não sei porquê".

#### Arquivo alterado

**`lib/src/geolocator_platform_interface.dart`** — novos métodos, todos com `throw UnimplementedError` por default (portanto **não quebram** android):

```dart
Future<void> startBackgroundTracking({required BackgroundTrackingSettings settings});
Future<void> stopBackgroundTracking();
Future<bool> isBackgroundTrackingActive();
Future<int> getBufferedPositionCount();
Future<List<BufferedPosition>> drainBufferedPositions({int limit = 500});
Future<void> acknowledgePositions(List<int> ids);
Future<void> clearBufferedPositions();
Stream<int> getBufferUpdateStream();          // emite a contagem quando chegam pontos novos
Future<LocationPermission> requestAlwaysPermission();
```

**`lib/src/implementations/method_channel_geolocator.dart`** — implementação default via method channel, espelhando o que já existe para os outros métodos.

---

### 3.2 O protocolo drain → ack (e por que não é só `drain`)

`drainBufferedPositions()` **lê sem deletar**. O app envia ao backend, e só depois chama `acknowledgePositions(ids)` para apagar.

*Por quê?* Se o `drain` deletasse na leitura, qualquer falha entre ler e enviar (app morto pelo iOS no meio do upload, rede caindo, crash) perderia o lote inteiro — exatamente o cenário que este projeto existe para evitar. Com ack explícito o pior caso é reenviar um lote duplicado, que o backend deduplica por `(sessionId, id)`. Perder dado é irreversível; duplicar não é.

O `limit = 500` evita estourar a memória do canal de plataforma quando a fila acumulou dias de tracking offline.

---

### 3.3 `geolocator_apple` — camada nativa

Todos os caminhos abaixo são relativos a `geolocator_apple/darwin/geolocator_apple/Sources/geolocator_apple/`.

#### Arquivos novos

**`Storage/PositionStore.m` + `include/geolocator_apple/Storage/PositionStore.h`**

Fila persistente em SQLite via `libsqlite3` (já embarcada no iOS, zero dependência externa).

```sql
CREATE TABLE IF NOT EXISTS positions (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  latitude           REAL    NOT NULL,
  longitude          REAL    NOT NULL,
  accuracy           REAL,
  altitude           REAL,
  altitude_accuracy  REAL,
  speed              REAL,
  speed_accuracy     REAL,
  heading            REAL,
  heading_accuracy   REAL,
  floor              INTEGER,
  is_mocked          INTEGER NOT NULL DEFAULT 0,
  timestamp_ms       INTEGER NOT NULL,   -- CLLocation.timestamp
  recorded_at_ms     INTEGER NOT NULL,   -- quando gravamos
  source             TEXT    NOT NULL,
  session_id         TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_positions_recorded ON positions(recorded_at_ms);
```

Requisitos não-óbvios de implementação:

1. **`PRAGMA journal_mode=WAL`** — permite escrita durante leitura e reduz a chance de corrupção se o processo for morto no meio de uma transação. Sendo morto pelo iOS a qualquer instante, isso não é opcional.
2. **`SQLITE_OPEN_FULLMUTEX`** — o `didUpdateLocations` roda na thread do run loop principal, mas o drain e a poda virão de uma fila serial própria. Serializar no nível do sqlite é mais barato que auditar todos os caminhos.
3. **`NSFileProtectionCompleteUntilFirstUserAuthentication` explícito no arquivo do banco.** Esta é a armadilha mais cara do projeto: se o arquivo herdar `NSFileProtectionComplete`, **toda escrita falha enquanto o device está com a tela bloqueada** — que é justamente 90% do tempo de uso real de tracking. Deve ser setado no momento da criação e reafirmado na abertura.
4. **Poda (`prune`)** por `maxBufferedPositions` e `maxPositionAge`, executada a cada N inserções (não a cada uma — `DELETE` é caro e roda em contexto de background com orçamento de CPU apertado).
5. **Escrita em lote quando possível**: o `didUpdateLocations` entrega um `NSArray` de localizações; inserir todas em uma transação.

**`Storage/TrackingStateStore.m` + `.h`**

`NSUserDefaults` (com suporte opcional a App Group, caso um dia entre uma extensão). Guarda:
- `isTrackingEnabled` (BOOL)
- `serializedSettings` (NSDictionary → plist)
- `sessionId` (NSString, UUID gerado no start)
- `lastAnchorLatitude` / `lastAnchorLongitude` (para reposicionar a região âncora)
- `lastEmittedTimestampMs` / `lastEmittedLat/Lon` (para aplicar `minimumInterval` / `minimumDistanceMeters` **através de relaunches** — sem persistir isso, todo relaunch reseta os filtros e a fila enche)

*Por quê NSUserDefaults e não o SQLite?* Precisa ser lido no `didFinishLaunchingWithOptions`, o mais cedo possível e sem risco de I/O bloqueante. `NSUserDefaults` é carregado pelo sistema antes disso.

**`Handlers/BackgroundTrackingHandler.m` + `.h`** — o núcleo.

Responsabilidades:
- Possui um `CLLocationManager` **dedicado**, separado dos dois de [GeolocationHandler.m:16-20](../geolocator_apple/darwin/geolocator_apple/Sources/geolocator_apple/Handlers/GeolocationHandler.m#L16-L20). *Por quê separado?* Porque o ciclo de vida é completamente diferente: o do `GeolocationHandler` é criado/destruído conforme o stream Dart; o de background precisa existir desde `didFinishLaunchingWithOptions` até `stopBackgroundTracking`, sem relação nenhuma com Dart. Compartilhar levaria a um `stopUpdatingLocation` do stream de foreground derrubando o tracking de background.
- `startWithSettings:` — valida (permissão `authorizedAlways`, `UIBackgroundModes`), grava o estado, arma os gatilhos do modo escolhido.
- `resumeFromPersistedStateIfNeeded` — chamado no launch; lê o `TrackingStateStore` e re-arma tudo se `isTrackingEnabled`.
- `stop` — desarma tudo e limpa o estado.
- Delegate `CLLocationManagerDelegate`: `didUpdateLocations`, `didFailWithError`, `didDetermineState:forRegion:`, `didVisit:`, `locationManagerDidPauseLocationUpdates:` / `didResumeLocationUpdates:` (implementar o par que hoje falta — ver §1.2f), `didChangeAuthorization` (se o usuário rebaixar de `Always` para `WhenInUse` durante o tracking, precisamos parar e registrar o motivo, senão o app fica queimando bateria sem produzir nada).
- Aplica `minimumDistanceMeters` / `minimumInterval` antes de chamar o `PositionStore`.
- Descarta fixes com `horizontalAccuracy < 0` (inválido) ou acima de um teto configurável, e fixes com idade > 60s (cache do CoreLocation logo após relaunch).
- Reposiciona a região âncora quando o device se afasta > raio/2 do centro atual.
- `beginBackgroundTaskWithExpirationHandler:` ao entrar em background para garantir tempo de flush do WAL.

**`Handlers/BackgroundActivitySessionHandler.m` + `.h`** *(iOS 17+, sob `@available(iOS 17.0, *)`)*

Usa `CLBackgroundActivitySession`. Nas versões modernas do iOS essa é a forma suportada de manter atualizações em background de forma confiável; sem ela, o iOS é progressivamente mais agressivo em suspender o app. Substituição condicional, com fallback automático para o caminho clássico em iOS 14–16. Também avaliar `CLMonitor` (iOS 17+) no lugar do `startMonitoringForRegion:`, que está deprecado — mantendo o caminho antigo como fallback.

*Por quê os dois caminhos e não só o clássico?* Porque o caminho clássico funciona mas com taxa de sobrevivência pior no iOS 17/18. E não dá para exigir iOS 17 mínimo hoje. O custo é ~2 dias de trabalho para uma diferença grande de confiabilidade na base instalada moderna.

**`Handlers/BufferStreamHandler.m` + `.h`**
`FlutterStreamHandler` de um novo EventChannel `flutter.baseflow.com/geolocator_buffer_apple`, que emite a contagem da fila sempre que ela cresce **e há engine viva**. É puramente uma otimização de UX (o app sabe na hora que tem dado novo); a corretude não depende dele.

**`Utils/PositionRecordMapper.m` + `.h`**
`CLLocation` ↔ linha do SQLite ↔ `NSDictionary` do canal. Reaproveita as regras de validação já existentes em [LocationMapper.m](../geolocator_apple/darwin/geolocator_apple/Sources/geolocator_apple/Utils/LocationMapper.m) (velocidade negativa = inválida, `verticalAccuracy <= 0` = altitude inválida, etc.) — essas regras estão corretas e não devem ser reescritas.

**`Utils/BackgroundSettingsMapper.m` + `.h`**
Dicionário do Dart → objeto de config, e serialização de volta para o `TrackingStateStore`. Precisa de round-trip fiel: o que for para o disco tem que reconstituir a configuração idêntica após um relaunch.

#### Arquivos alterados

**`GeolocatorPlugin.m`**

1. `registerWithRegistrar:` passa a chamar **`[registrar addApplicationDelegate:instance]`** e a declarar conformidade com `FlutterApplicationLifeCycleDelegate`. Sem isso nada de relaunch funciona (§1.2b).
2. Implementar `application:didFinishLaunchingWithOptions:`:
   ```objc
   BOOL launchedByLocation = launchOptions[UIApplicationLaunchOptionsLocationKey] != nil;
   [[self createBackgroundTrackingHandler] resumeFromPersistedStateIfNeeded:launchedByLocation];
   ```
   *Por quê chamar mesmo quando não foi relançado por localização?* Porque o app pode ter sido aberto normalmente pelo usuário depois de ter sido morto — e o tracking também precisa voltar nesse caso. A flag serve só para telemetria e para decidir se vale a pena subir a UI.
3. Registrar o novo EventChannel e os novos métodos em `handleMethodCall:`: `startBackgroundTracking`, `stopBackgroundTracking`, `isBackgroundTrackingActive`, `getBufferedPositionCount`, `drainBufferedPositions`, `acknowledgePositions`, `clearBufferedPositions`, `requestAlwaysPermission`.
4. Factory `createBackgroundTrackingHandler` + setter de override, seguindo o padrão já usado para os outros handlers ([GeolocatorPlugin.m:50-81](../geolocator_apple/darwin/geolocator_apple/Sources/geolocator_apple/GeolocatorPlugin.m#L50-L81)) — necessário para os XCTests.

**`Handlers/PermissionHandler.m`**

1. Novo método `requestAlwaysPermission:errorHandler:` implementando o fluxo obrigatório em **dois passos** do iOS:
   - se `notDetermined` → `requestWhenInUseAuthorization`, aguarda callback;
   - se `authorizedWhenInUse` → `requestAlwaysAuthorization`, aguarda o segundo callback.

   O iOS **não exibe** o prompt de `Always` se o app nunca teve `WhenInUse`. Um `requestAlwaysAuthorization` direto em estado `notDetermined` mostra o prompt de "When In Use" com opção "Allow Once" e nunca chega em `Always`.
2. **Não destruir** o `CLLocationManager` entre os dois passos. O `cleanUp` atual ([PermissionHandler.m:119-123](../geolocator_apple/darwin/geolocator_apple/Sources/geolocator_apple/Handlers/PermissionHandler.m#L119-L123)) seta `self.locationManager = nil`, e um manager desalocado não entrega o segundo `didChangeAuthorization`. Refatorar para só limpar os handlers ao final do fluxo completo.
3. Tratar o **"provisional always"**: quando o usuário escolhe "Allow While Using App" mas o app tem background modes, o iOS pode conceder `authorizedAlways` provisório e depois exibir, dias depois, o prompt "continuar permitindo?". O `didChangeAuthorization` precisa propagar essa mudança para o `BackgroundTrackingHandler`.
4. Validar as chaves de plist certas e produzir mensagem de erro específica dizendo **qual** chave falta (hoje a mensagem é genérica).

**`Handlers/GeolocationHandler.m`**
Alteração mínima: expor `shouldEnableBackgroundLocationUpdates` como utilitário compartilhado (mover para `Utils/PermissionUtils.h`) e fazer com que a ausência de `UIBackgroundModes` propague um erro em vez de degradar em silêncio (§1.2 / `BackgroundModesNotConfiguredException`).

**`PrivacyInfo.xcprivacy`**
Adicionar `NSPrivacyAccessedAPICategoryUserDefaults` com reason code **`CA92.1`** (acesso restrito ao próprio app). Sem isso a App Store rejeita o binário na submissão — a partir do momento em que o `TrackingStateStore` usa `NSUserDefaults`, a declaração passa a ser obrigatória. Verificar também se o uso de `NSFileManager` para o caminho do banco exige declaração de `FileTimestamp`.

**`darwin/geolocator_apple.podspec`**
```ruby
s.ios.deployment_target = '14.0'   # era 11.0
s.library = 'sqlite3'
```
*Por quê subir para 14.0?* `CLLocationManager.authorizationStatus` de instância, `courseAccuracy` e o comportamento de precisão reduzida já assumem iOS 14 no código. Manter 11.0 é ficção — e complica os `@available` do novo código sem nenhum device real por trás.

**`darwin/geolocator_apple/Package.swift`**
```swift
platforms: [.iOS("14.0"), .macOS("10.15")]
linkerSettings: [.linkedLibrary("sqlite3")]
```

**macOS:** todo o novo código nativo entra sob `#if TARGET_OS_IOS`. `CLBackgroundActivitySession`, `allowsBackgroundLocationUpdates` e relaunch por localização não existem no macOS; o pacote é compartilhado (`sharedDarwinSource: true`), então a compilação para macOS tem que continuar limpa. O Dart lança `UnsupportedError` em macOS.

---

### 3.4 `geolocator_apple` — camada Dart

**`lib/src/types/apple_background_settings.dart`** *(novo)* — estende `BackgroundTrackingSettings` com o que só existe no iOS:
- `bool showBackgroundLocationIndicator` (barra azul)
- `bool pauseLocationUpdatesAutomatically` (**default `false`** — ver §1.2f)
- `ActivityType activityType` (reusa o enum existente)
- `double anchorRegionRadius` (default 100m)
- `bool useBackgroundActivitySession` (default `true`, ignorado em < iOS 17)
- `bool monitorVisits`

**`lib/src/geolocator_apple.dart`** *(alterado)* — implementar os novos métodos do platform interface sobre o `_methodChannel` existente, mais o novo `EventChannel('flutter.baseflow.com/geolocator_buffer_apple')`. Mapear os novos códigos de erro em `_handlePlatformException` ([geolocator_apple.dart:229-248](../geolocator_apple/lib/src/geolocator_apple.dart#L229-L248)): `BACKGROUND_PERMISSION_DENIED`, `BACKGROUND_MODES_NOT_CONFIGURED`, `BACKGROUND_TRACKING_ALREADY_ACTIVE`.

**`lib/geolocator_apple.dart`** *(alterado)* — exportar os tipos novos.

---

### 3.5 `geolocator` (pacote app-facing)

**`lib/geolocator.dart`** — métodos estáticos delegando para `GeolocatorPlatform.instance`, seguindo o padrão do arquivo:

```dart
static Future<void> startBackgroundTracking({required BackgroundTrackingSettings settings});
static Future<void> stopBackgroundTracking();
static Future<bool> isBackgroundTrackingActive();
static Future<int> getBufferedPositionCount();
static Future<List<BufferedPosition>> drainBufferedPositions({int limit = 500});
static Future<void> acknowledgePositions(List<int> ids);
static Future<void> clearBufferedPositions();
static Stream<int> getBufferUpdateStream();
static Future<LocationPermission> requestAlwaysPermission();
```

E adicionar `AppleBackgroundSettings` ao bloco de `export ... show` do `geolocator_apple`.

---

### 3.6 Configuração obrigatória no app hospedeiro

Isso vale tanto para os dois exemplos do repo (`geolocator/example/ios` e `geolocator_apple/example/ios`) quanto para o app de produção da AZ Ship. Sem isso **nada funciona** — e a falha é silenciosa hoje.

**`Info.plist`:**
```xml
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>processing</string>  <!-- opcional: BGTaskScheduler para upload oportunista -->
</array>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Usamos sua localização para acompanhar a rota em andamento.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Precisamos da localização mesmo com o app fechado para registrar o trajeto completo da viagem.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>Precisamos da localização mesmo com o app fechado para registrar o trajeto completo da viagem.</string>
```

O `Info.plist` atual de [geolocator/example/ios/Runner/Info.plist](../geolocator/example/ios/Runner/Info.plist) tem **apenas** `NSLocationWhenInUseUsageDescription` e nenhum `UIBackgroundModes`. As três chaves são necessárias: `AlwaysAndWhenInUse` para iOS 11+, `Always` para o validador da App Store, `WhenInUse` para o primeiro passo do fluxo de permissão.

**Xcode:** habilitar *Signing & Capabilities → Background Modes → Location updates*. (Editar só o plist não é suficiente para o build de release em alguns setups de assinatura.)

**Texto do prompt:** o iOS mostra a string do plist literalmente. Ela é o principal fator de aceitação do `Always` pelo usuário e o principal alvo do revisor da App Store. Não deixar como texto genérico.

---

## 4. Armadilhas conhecidas do iOS (e mitigação)

| Armadilha | Impacto | Mitigação no plano |
|---|---|---|
| **Force-quit pelo usuário** (swipe up) | Standard updates param e não relançam | SLC e region monitoring relançam mesmo após force-quit na maioria das versões, mas o comportamento variou entre iOS 13/15/17. **Precisa validação empírica em device por versão** — item explícito da matriz de testes (§5.3) |
| **Background App Refresh desligado** | O relaunch por SLC pode não ocorrer | Detectar `UIApplication.backgroundRefreshStatus` e expor via API, para o app avisar o usuário |
| **Precisão reduzida** (iOS 14+) | Fixes com ~1-5km, inúteis para rota | Checar `accuracyAuthorization`; expor no status; usar o `requestTemporaryFullAccuracy` que já existe |
| **Device bloqueado + File Protection** | Escritas no SQLite falham | `NSFileProtectionCompleteUntilFirstUserAuthentication` explícito (§3.3) |
| **`pausesLocationUpdatesAutomatically`** | Tracking pausa e não volta | Default `false` + implementar `didPause`/`didResume` |
| **Jetsam por memória** | App morto em minutos | Fila em disco + auto-restart via SLC/region |
| **Bateria** | Reclamação de usuário / rejeição na review | `hybrid` + `distanceFilter` + `minimumInterval`; medir consumo no teste de campo (§5.3) |
| **Review da App Store** | Rejeição por uso de `Always` | Preparar justificativa + vídeo demonstrando o caso de uso de logística. **Reservar tempo de resubmissão no cronograma do app, não deste plugin** |
| **Cache do CoreLocation no relaunch** | Primeiro fix pós-relaunch é velho | Descartar fixes com idade > 60s (a lógica de 5s já existente em [GeolocationHandler.m:161-166](../geolocator_apple/darwin/geolocator_apple/Sources/geolocator_apple/Handlers/GeolocationHandler.m#L161-L166) é boa referência, mas 5s é curto demais para o contexto de background) |

---

## 5. Plano de testes

### 5.1 Testes unitários Dart

Estender [geolocator_apple/test/geolocator_apple_test.dart](../geolocator_apple/test/geolocator_apple_test.dart) usando os mocks já existentes (`method_channel_mock.dart`, `event_channel_mock.dart`):
- serialização/desserialização de `AppleBackgroundSettings` (round-trip)
- `drainBufferedPositions` mapeando corretamente `BufferedPosition`
- cada código de erro novo → exceção Dart correta
- `acknowledgePositions` com lista vazia / ids inexistentes
- stream de buffer: broadcast, cancelamento, re-listen

Idem no `geolocator_platform_interface` (contrato + defaults `UnimplementedError`).

### 5.2 Testes nativos (XCTest)

O alvo **já existe** em [geolocator_apple/example/ios/RunnerTests/](../geolocator_apple/example/ios/RunnerTests/) mas o CI **não o executa** — o workflow [.github/workflows/geolocator_apple.yaml](../.github/workflows/geolocator_apple.yaml) só faz `flutter analyze` e `flutter build ios`. Item do plano: adicionar step de `xcodebuild test`.

Novos testes:
- `PositionStoreTests` — insert/query/ack/prune, cap de linhas, TTL, comportamento com banco corrompido, concorrência
- `TrackingStateStoreTests` — round-trip de settings
- `BackgroundTrackingHandlerTests` — com `CLLocationManager` mockado (o padrão de override já existe em [GeolocationHandler_Test.h](../geolocator_apple/darwin/geolocator_apple/Sources/geolocator_apple/include/geolocator_apple/Handlers/GeolocationHandler_Test.h)): filtros de distância/tempo, descarte de fix inválido/velho, transição entre modos, `resumeFromPersistedState`
- `PermissionHandlerTests` — fluxo de dois passos `notDetermined → whenInUse → always`

### 5.3 Testes de campo (device real — **não simulável**)

Esta é a parte que não pode ser comprimida. Simulador não reproduz jetsam, relaunch por localização, nem consumo de bateria.

| Cenário | Como | Critério de aceite |
|---|---|---|
| App em background, tela ligada | 30 min caminhando | 0 pontos perdidos |
| App em background, device bloqueado | 30 min | 0 pontos perdidos (valida File Protection) |
| App morto pelo iOS (jetsam) | Abrir vários apps pesados até o app sair; depois deslocar > 500m | App relança, tracking retoma, fila íntegra |
| Force-quit pelo usuário | Swipe up; deslocar > 1km | Documentar o comportamento **por versão de iOS** (14/15/16/17/18) |
| Reboot do device | Reiniciar; deslocar | Documentar (esperado: sem relaunch até o app ser aberto) |
| Modo avião / sem rede por 24h | Tracking ligado, sem rede | Fila acumula sem estourar o cap; drena ao voltar |
| Bateria | 8h de tracking `hybrid` | Consumo alvo < 10%/h; medir também `continuous` puro para comparação |
| Downgrade de permissão | `Always` → `WhenInUse` em Ajustes durante o tracking | Tracking para de forma limpa, estado reflete, sem loop de bateria |
| Precisão reduzida | Ativar em Ajustes | Erro/status claro, sem gravar lixo |
| Volume | Rota de 8h, ~1 ponto/10s | Fila com ~2 900 linhas drena sem travar a UI |

**Requer:** ao menos 2 iPhones físicos com versões de iOS diferentes (idealmente um iOS 15/16 e um iOS 18), e deslocamento real (carro).

---

## 6. Cronograma

Estimativa para **1 desenvolvedor** com experiência em Flutter + iOS nativo (ObjC). Dias úteis.

| # | Fase | Dias |
|---|---|---:|
| 0 | Spike técnico: validar relaunch por SLC em device real antes de escrever o resto | 2 |
| 1 | `geolocator_platform_interface`: modelos, enums, erros, contrato | 2 |
| 2 | Permissão `Always` (nativo + Dart + testes) | 2 |
| 3 | `PositionStore` (SQLite, WAL, file protection, poda) + `TrackingStateStore` | 3 |
| 4 | `BackgroundTrackingHandler`: modos `continuous` / `significant` / `hybrid`, filtros, região âncora | 4 |
| 5 | Ciclo de vida: `addApplicationDelegate`, `didFinishLaunchingWithOptions`, auto-restart, pause/resume | 3 |
| 6 | Caminho iOS 17+: `CLBackgroundActivitySession` + `CLMonitor`, com fallback | 2 |
| 7 | Ponte Dart: method/event channels, drain→ack, mapeamento de erros | 2 |
| 8 | Example app: Info.plist, capabilities, tela de tracking/buffer | 2 |
| 9 | Testes unitários Dart + XCTest + step de `xcodebuild test` no CI | 3 |
| 10 | **Testes de campo em device real** (§5.3) | 5 |
| 11 | Correções decorrentes do campo | 3 |
| 12 | Docs (README, CHANGELOG, guia de migração), versionamento dos 3 pacotes | 2 |
| | **Total** | **35** |

**≈ 35 dias úteis ≈ 7 semanas corridas** para 1 dev.

**Com 2 devs** (1 focado no nativo ObjC, 1 no Dart/exemplo/testes), as fases 1/7/8/9 paralelizam com 3/4/5/6:
**≈ 22 dias úteis ≈ 4,5 semanas.**

### Marcos

| Marco | Dia (1 dev) | Entrega |
|---|---:|---|
| **M1 — Viabilidade** | 2 | Relaunch por SLC provado em device. Se falhar, o desenho muda antes de qualquer código de produção |
| **M2 — Fila persistente** | 9 | Posições sobrevivem à morte do app (verificável por dump do SQLite) |
| **M3 — Alpha funcional** | 18 | Tracking end-to-end no example app, iOS 14–18 |
| **M4 — Feature complete** | 23 | Testado, com CI verde |
| **M5 — Validado em campo** | 33 | Matriz da §5.3 preenchida |
| **M6 — Release** | 35 | Pacotes versionados, documentados |

### Riscos de prazo

- **Alto:** o comportamento de relaunch pós-force-quit variar entre versões de iOS e obrigar a mudar o desenho. Mitigado por antecipar o spike (fase 0).
- **Médio:** consumo de bateria acima do aceitável, exigindo rodadas extras de tuning do `hybrid`. Reservados 3 dias na fase 11.
- **Médio:** os testes de campo são serializados por natureza (cada cenário leva horas de deslocamento real). Difícil comprimir mesmo com mais gente.
- **Fora deste escopo:** aprovação da App Store para uso de `Always`. É risco do app, não do plugin, mas pode adicionar semanas ao lançamento.

---

## 7. Fora de escopo (fases futuras)

- Android (foreground service + `WorkManager`); o contrato do platform interface já foi desenhado para acomodar
- Upload HTTP nativo direto (hoje o app drena e envia)
- Geofencing como feature de produto (usamos região apenas como âncora interna)
- Callback Dart headless em tempo real (a fila cobre o requisito)
