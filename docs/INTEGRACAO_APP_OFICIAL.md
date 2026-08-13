# Roteiro — Integrar background tracking no app oficial (AZ Ship)

**Para:** a IA/dev que vai integrar isso no app oficial.
**Fonte:** fork `northonBarbosa/flutter-geolocator-azs`, branch `main`, commit `1d81d54c4adbab3a468fa42609d7ecffadf96446`.
**Escopo implementado:** iOS apenas. Ver §5 (limitações) antes de prometer qualquer coisa em Android.
**Contexto completo do desenho:** [`docs/PLANO_BACKGROUND_IOS.md`](./PLANO_BACKGROUND_IOS.md) neste mesmo repo — leia se precisar entender o *porquê* de alguma decisão. Este documento aqui é só o *como integrar*.

---

## 1. O que isto é

Um subsistema de tracking de localização em background que **sobrevive a suspensão e a terminação do processo pelo iOS** — diferente do `getPositionStream()` normal do geolocator, que morre quando o app é suspenso por tempo suficiente ou o iOS mata o processo.

Arquitetura, resumida: CoreLocation grava direto num SQLite local (WAL) no processo nativo, sem depender da engine Flutter estar viva. O Dart drena esse buffer quando quiser (app em foreground, por exemplo) e confirma (`acknowledge`) o que já foi processado. Três modos de captura (`continuous`, `significant`, `hybrid`) — `hybrid` é o default recomendado e o que resolve o problema de sobrevivência real.

---

## 2. Setup do pubspec — **o passo que mais quebra se for feito errado**

Este é um monorepo com 3 pacotes interdependentes (`geolocator`, `geolocator_apple`, `geolocator_platform_interface`), **nenhum publicado no pub.dev** com essas mudanças. O `geolocator/pubspec.yaml` deste fork ainda declara `geolocator_apple: ^2.3.14` e `geolocator_platform_interface: ^4.2.3` (versões publicadas, sem o contrato novo) — os `pubspec_overrides.yaml` que existem *dentro* deste repo **não se propagam** para quem consome o pacote de fora. Se o app oficial só adicionar `geolocator` como dependência, ele vai resolver as versões antigas e nada do que está documentado aqui vai existir.

**A forma correta**, no `pubspec.yaml` do app oficial:

```yaml
dependencies:
  geolocator:
    git:
      url: https://github.com/northonBarbosa/flutter-geolocator-azs.git
      ref: 1d81d54c4adbab3a468fa42609d7ecffadf96446  # ou uma tag/commit mais novo, ver §7
      path: geolocator

dependency_overrides:
  geolocator_apple:
    git:
      url: https://github.com/northonBarbosa/flutter-geolocator-azs.git
      ref: 1d81d54c4adbab3a468fa42609d7ecffadf96446
      path: geolocator_apple
  geolocator_platform_interface:
    git:
      url: https://github.com/northonBarbosa/flutter-geolocator-azs.git
      ref: 1d81d54c4adbab3a468fa42609d7ecffadf96446
      path: geolocator_platform_interface
```

Os três `git:` devem apontar pro **mesmo `ref`** sempre que atualizar. Rodar `flutter pub get` depois e confirmar que resolveu do git, não do pub.dev (`flutter pub deps` ou olhar o `pubspec.lock` — deve ter `source: git` nas três entradas).

Se o app oficial já tem uma dependência direta em `geolocator_platform_interface` ou `geolocator_apple` (bem provável, para usar tipos específicos), ela pode continuar declarada normalmente em `dependencies:` — o `dependency_overrides:` acima tem prioridade e resolve pro fork de qualquer forma.

---

## 3. Configuração obrigatória no iOS do app oficial

Sem isso a permissão nunca funciona e o erro é silencioso.

**`ios/Runner/Info.plist`** — adicionar as três chaves (texto real, visível ao usuário no prompt do sistema — não deixar genérico, é o principal fator de aceitação e o principal alvo do revisor da App Store):

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>[texto explicando por que o app usa localização]</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>[texto explicando por que o app precisa de localização mesmo fechado]</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>[mesmo texto acima — chave legada, mas alguns fluxos do iOS ainda checam]</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
</array>
```

**Xcode:** Signing & Capabilities → Background Modes → marcar "Location updates". Editar só o plist não é suficiente em alguns setups de assinatura/release.

**Deployment target:** `>= 11.0` já é suficiente (é o que o podspec deste fork usa). Não precisa subir.

---

## 4. Como usar a API

Tudo isto está exposto em `package:geolocator/geolocator.dart` — não precisa importar `geolocator_apple` diretamente.

### 4.1 Permissão

O iOS exige um fluxo em dois passos: primeiro "When In Use", só depois "Always" (o sistema não mostra o prompt de Always se o app nunca teve When In Use). `requestAlwaysPermission()` já faz isso internamente — não precisa orquestrar os dois passos manualmente.

```dart
final permission = await Geolocator.requestAlwaysPermission();
if (permission != LocationPermission.always) {
  // Usuário negou, ou está preso em "When In Use". Oferecer um caminho
  // manual: Geolocator.openAppSettings() abre a tela do app em Ajustes.
  return;
}
```

Boas práticas de UX (não é o plugin que resolve isso, é o app): mostrar uma explicação **antes** de chamar `requestAlwaysPermission()` pela primeira vez — se o usuário rejeitar, só dá pra tentar de novo indo manualmente em Ajustes.

### 4.2 Iniciar o tracking

```dart
import 'package:geolocator/geolocator.dart';

await Geolocator.startBackgroundTracking(
  settings: const AppleBackgroundSettings(
    mode: BackgroundTrackingMode.hybrid, // recomendado — ver PLANO_BACKGROUND_IOS.md §2.1
    minimumDistanceMeters: 20,           // ajustar pro caso de uso (rota de entrega etc.)
    minimumInterval: Duration(seconds: 30),
    maxBufferedPositions: 50000,         // default; a fila poda sozinha além disso
  ),
);
```

Erros possíveis (capturar explicitamente, não deixar como exceção genérica):

```dart
try {
  await Geolocator.startBackgroundTracking(settings: settings);
} on BackgroundPermissionDeniedException {
  // Não tem Always. Chamar requestAlwaysPermission() primeiro.
} on BackgroundModesNotConfiguredException {
  // Info.plist/Xcode capability faltando — erro de configuração do app,
  // não do usuário. Não deveria acontecer em produção se o §3 foi seguido.
}
```

### 4.3 Drenar o buffer (protocolo drain → ack)

**Importante:** `drainBufferedPositions()` só *lê*, não remove. Só remove quando você confirma com `acknowledgePositions()`. Isso existe de propósito: se o app morrer no meio de um upload, o pior caso é reenviar um lote duplicado (o backend deduplica por posição), não perder dado.

```dart
Future<void> _uploadBufferedPositions() async {
  final positions = await Geolocator.drainBufferedPositions(limit: 500);
  if (positions.isEmpty) return;

  final uploadedIds = <int>[];
  for (final buffered in positions) {
    final ok = await meuBackend.enviarPosicao(
      lat: buffered.position.latitude,
      lng: buffered.position.longitude,
      timestamp: buffered.position.timestamp,
      recordedAt: buffered.recordedAt,   // quando o device gravou, != timestamp do fix
      source: buffered.source,           // continuous | significantChange | region | visit
    );
    if (ok) uploadedIds.add(buffered.id);
  }

  if (uploadedIds.isNotEmpty) {
    await Geolocator.acknowledgePositions(uploadedIds);
  }
}
```

Gatilhos sugeridos pra chamar isso: ao abrir o app, periodicamente com o app em foreground (`Timer.periodic`), e/ou ouvindo o stream de novidade:

```dart
Geolocator.getBufferUpdateStream().listen((count) {
  // Disparado sempre que o buffer cresce E há engine Flutter viva.
  // É só UX (avisa na hora) — não é o único jeito de saber que há dado
  // novo; um polling periódico continua sendo necessário porque isto não
  // dispara com o app totalmente fechado.
  _uploadBufferedPositions();
});
```

### 4.4 Parar / status

```dart
await Geolocator.stopBackgroundTracking();

final ativo = await Geolocator.isBackgroundTrackingActive();
final pendentes = await Geolocator.getBufferedPositionCount();
```

### 4.5 Referência rápida da API

| Método | O que faz |
|---|---|
| `Geolocator.requestAlwaysPermission()` | Fluxo de permissão em 2 passos, retorna `LocationPermission` |
| `Geolocator.startBackgroundTracking({required settings})` | Liga o tracking; `settings` é `AppleBackgroundSettings` no iOS |
| `Geolocator.stopBackgroundTracking()` | Desliga; não mexe no buffer já acumulado |
| `Geolocator.isBackgroundTrackingActive()` | `bool` |
| `Geolocator.getBufferedPositionCount()` | `int` |
| `Geolocator.drainBufferedPositions({limit = 500})` | Lê sem remover, `List<BufferedPosition>` |
| `Geolocator.acknowledgePositions(List<int> ids)` | Remove do buffer os `ids` confirmados |
| `Geolocator.clearBufferedPositions()` | Apaga tudo (cuidado — perde dado não enviado) |
| `Geolocator.getBufferUpdateStream()` | `Stream<int>`, só com engine viva |

`AppleBackgroundSettings` (todos os campos têm default, nenhum é obrigatório):

| Campo | Default | Nota |
|---|---|---|
| `mode` | `hybrid` | `continuous` \| `significant` \| `hybrid` |
| `accuracy` | `LocationAccuracy.best` | |
| `minimumDistanceMeters` | `0` | Filtro aplicado antes de gravar — independe do `distanceFilter` do SO |
| `minimumInterval` | `Duration.zero` | Idem, eixo tempo |
| `maxBufferedPositions` | `50000` | Poda automática além disso |
| `maxPositionAge` | `null` (sem TTL) | |
| `pauseLocationUpdatesAutomatically` | `false` | **Não mudar sem motivo forte** — historicamente o tracking pausa e não volta |
| `anchorRegionRadius` | `100` (metros) | Só usado em modo `hybrid` |
| `showBackgroundLocationIndicator` | `false` | Barra azul do iOS |
| `monitorVisits` | `false` | Ainda não consumido pelo nativo (ver §5) |

---

## 5. Limitações conhecidas — ler antes de prometer prazo

1. **Android não implementado.** Todo método novo lança `UnimplementedError` em `geolocator_android`. Se o app oficial roda em Android, **envolver as chamadas em `if (Platform.isIOS)`** ou equivalente. Não há timeline pra Android neste fork.
2. **Sem testes automatizados no código novo.** Foi decisão explícita deste ciclo (QA faz uma bateria própria, mais pesada, depois). O que existe hoje: smoke tests manuais rodados durante o desenvolvimento de cada peça (registrados nas mensagens de commit), e uma validação funcional do mecanismo de relaunch por SLC em device real durante a fase de spike. **A matriz de testes de campo completa do plano original (força-quit, jetsam, reboot, modo avião 24h, bateria, downgrade de permissão — em múltiplas versões de iOS) não foi executada.** Isso é o maior risco antes de ir pra produção — ver `PLANO_BACKGROUND_IOS.md` §5.3 pra reproduzir.
3. **iOS 17+ otimizado (`CLBackgroundActivitySession`/`CLMonitor`) não implementado** — de propósito, fora do escopo deste ciclo. O caminho clássico implementado cobre iOS 14–18 com funcionalidade completa; a diferença é confiabilidade extra nas versões mais novas, não uma feature faltando.
4. **`source` de cada posição não é 100% confiável em modo `hybrid`.** O CoreLocation entrega updates de `continuous` e de `significant` pelo mesmo callback, sem dizer qual gatilho produziu qual fix — é só metadado de diagnóstico, não afeta a posição em si nem a lógica de negócio.
5. **Web/Windows/Linux foram removidos deste fork.** Se o app oficial precisa dessas plataformas, este fork não serve como substituto direto do `geolocator` publicado — precisaria de outra estratégia (ex.: usar este fork só nas plataformas suportadas, publicado oficial nas demais, o que é mais complexo de manter).
6. **Revisão da App Store para uso de "Always"** é responsabilidade do app, não do plugin — preparar justificativa e idealmente vídeo demonstrando o caso de uso de logística. Pode adicionar semanas ao cronograma de lançamento se não for antecipado.

---

## 6. Checklist de integração

- [ ] `pubspec.yaml` do app oficial com os 3 `git:`/`dependency_overrides` do §2, mesmo `ref`
- [ ] `flutter pub get` limpo, `pubspec.lock` confirmando `source: git` nos três pacotes
- [ ] `Info.plist` com as 4 chaves do §3
- [ ] Xcode: Background Modes → Location updates habilitado
- [ ] Fluxo de UI pedindo `requestAlwaysPermission()` com explicação prévia
- [ ] `startBackgroundTracking` com tratamento dos dois erros específicos
- [ ] Rotina de drain→ack (upload real pro backend do app, dedup por posição do lado do backend)
- [ ] Testado em device físico real (simulador não reproduz relaunch) — no mínimo: app em background com tela bloqueada por 30min sem perder ponto
- [ ] Se o app suporta Android: chamadas novas isoladas atrás de `Platform.isIOS`

---

## 7. Se este fork continuar evoluindo

Antes de integrar, vale conferir se há commits mais novos em `main` (`git log origin/main` no fork) — o `ref` fixo acima é o estado no momento em que este roteiro foi escrito. Trocar o `ref` nos três `git:` do §2 pro commit mais recente se fizer sentido, sempre mantendo os três sincronizados no mesmo `ref`.
