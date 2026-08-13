//
//  BackgroundTrackingHandler.h
//  geolocator_apple
//
//  Núcleo do tracking em background (docs/PLANO_BACKGROUND_IOS.md §3.3,
//  fase 4). Possui um CLLocationManager dedicado, separado dos usados por
//  GeolocationHandler: o ciclo de vida deste é completamente diferente —
//  precisa existir desde application:didFinishLaunchingWithOptions: até
//  stopBackgroundTracking, sem relação com o stream Dart. Compartilhar o
//  manager levaria a um stopUpdatingLocation do stream de foreground
//  derrubando o tracking de background.
//

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BackgroundTrackingErrorHandler)(NSString *errorCode,
                                                NSString *errorDescription);

/// Postada sempre que uma ou mais posições são gravadas no buffer. O
/// `userInfo` contém a contagem atual sob a chave `kBufferCountUserInfoKey`.
/// Puramente UX (BufferStreamHandler ouve isso pra avisar o Dart em tempo
/// real quando há engine viva) — a corretude do tracking não depende disso.
FOUNDATION_EXPORT NSString *const GeolocatorBufferDidGrowNotification;
FOUNDATION_EXPORT NSString *const kBufferCountUserInfoKey;

@interface BackgroundTrackingHandler : NSObject <CLLocationManagerDelegate>

/// Valida permissão `authorizedAlways` e `UIBackgroundModes: [location]`,
/// persiste o estado (TrackingStateStore) e arma os gatilhos do modo
/// escolhido. [settings] espelha as chaves de
/// `BackgroundTrackingSettings.toJson()` (geolocator_platform_interface).
- (void)startWithSettings:(NSDictionary<NSString *, id> *)settings
              errorHandler:(BackgroundTrackingErrorHandler)errorHandler;

/// Desarma tudo (updates contínuos, SLC, região âncora) e limpa o estado
/// persistido. As posições já gravadas no PositionStore não são afetadas.
- (void)stop;

/// Se há uma sessão de tracking ativa, segundo o estado persistido.
- (BOOL)isActive;

/// Chamado em application:didFinishLaunchingWithOptions:. Lê o
/// TrackingStateStore e re-arma tudo se o tracking estava ligado — é assim
/// que o tracking sobrevive a um relaunch causado pelo SLC/região após o
/// sistema ter terminado o processo.
- (void)resumeFromPersistedStateIfNeeded;

/// Número de posições atualmente no buffer. Funciona mesmo se o tracking
/// não estiver ativo neste processo — pode haver posições deixadas por uma
/// sessão anterior ainda não drenadas.
- (NSUInteger)bufferedPositionCount;

/// Lê até [limit] posições do buffer sem removê-las (protocolo drain→ack).
- (NSArray<NSDictionary<NSString *, id> *> *)drainPositionsWithLimit:(NSUInteger)limit;

/// Remove as posições com os `id`s informados do buffer.
- (void)acknowledgePositionIds:(NSArray<NSNumber *> *)ids;

/// Remove todas as posições do buffer.
- (void)clearBufferedPositions;

@end

NS_ASSUME_NONNULL_END
