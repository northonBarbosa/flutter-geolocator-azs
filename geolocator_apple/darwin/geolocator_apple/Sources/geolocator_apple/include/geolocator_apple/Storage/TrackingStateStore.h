//
//  TrackingStateStore.h
//  geolocator_apple
//
//  Estado do tracking em background (docs/PLANO_BACKGROUND_IOS.md §3.3),
//  persistido em NSUserDefaults — precisa ser lido em
//  application:didFinishLaunchingWithOptions:, o mais cedo possível e sem
//  I/O bloqueante, por isso não é o SQLite do PositionStore.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TrackingStateStore : NSObject

/// Se o tracking estava ligado da última vez que foi configurado. Reflete
/// só a intenção persistida, não a permissão nem o estado real do
/// CLLocationManager.
@property (nonatomic, readonly) BOOL isTrackingEnabled;

/// Identifica a sessão (ciclo start/stop) atual. nil se não houver sessão
/// ativa.
@property (nonatomic, readonly, nullable) NSString *sessionId;

/// As configurações serializadas passadas para o último
/// startSessionWithSettings:. nil se não houver sessão ativa.
@property (nonatomic, readonly, nullable) NSDictionary<NSString *, id> *serializedSettings;

/// Marca o tracking como ativo, gera um novo sessionId (UUID) e persiste
/// [settings]. Sobrescreve qualquer sessão anterior e zera âncora/filtros.
- (void)startSessionWithSettings:(NSDictionary<NSString *, id> *)settings;

/// Marca o tracking como inativo e limpa sessionId/settings/âncora/filtros.
- (void)stopSession;

/// Se já existe uma posição-âncora persistida.
@property (nonatomic, readonly) BOOL hasAnchor;
@property (nonatomic, readonly) double anchorLatitude;
@property (nonatomic, readonly) double anchorLongitude;

/// Reposiciona a região-âncora usada pelo modo `hybrid` no iOS.
- (void)updateAnchorWithLatitude:(double)latitude longitude:(double)longitude;

/// Se já existe uma última posição emitida persistida.
@property (nonatomic, readonly) BOOL hasLastEmitted;
@property (nonatomic, readonly) double lastEmittedLatitude;
@property (nonatomic, readonly) double lastEmittedLongitude;
@property (nonatomic, readonly) NSInteger lastEmittedTimestampMs;

/// Registra a última posição efetivamente gravada no PositionStore. Usado
/// pra aplicar minimumDistanceMeters/minimumInterval através de relaunches
/// — sem persistir isso, todo relaunch reseta os filtros e a fila enche.
- (void)updateLastEmittedLatitude:(double)latitude
                          longitude:(double)longitude
                     timestampMs:(NSInteger)timestampMs;

@end

NS_ASSUME_NONNULL_END
