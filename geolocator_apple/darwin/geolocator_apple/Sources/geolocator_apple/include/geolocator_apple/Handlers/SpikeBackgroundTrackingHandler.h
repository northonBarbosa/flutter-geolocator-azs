//
//  SpikeBackgroundTrackingHandler.h
//  geolocator_apple
//
//  Fase 0 do plano de background tracking (docs/PLANO_BACKGROUND_IOS.md):
//  código de validação para provar, em device real, que
//  startMonitoringSignificantLocationChanges relança o app depois de
//  terminação pelo sistema. Não é a arquitetura final (ver PositionStore /
//  TrackingStateStore / BackgroundTrackingHandler nas fases 3 e 4) — deve
//  ser substituído, não estendido.
//

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SpikeErrorHandler)(NSString *errorCode, NSString *errorDescription);

@interface SpikeBackgroundTrackingHandler : NSObject <CLLocationManagerDelegate>

/// Arma o startMonitoringSignificantLocationChanges e persiste que o spike
/// está ativo. Falha com erro se a permissão não for "Always".
- (void)startSpikeWithErrorHandler:(SpikeErrorHandler)errorHandler;

/// Desarma o monitoramento e limpa o estado de "ativo".
- (void)stopSpike;

- (BOOL)isSpikeActive;

/// Eventos registrados (mais recente por último), cap de 200 entradas.
- (NSArray<NSDictionary<NSString *, id> *> *)loggedEvents;

- (void)clearLog;

/// Chamado em application:didFinishLaunchingWithOptions:. Se o spike estava
/// ativo antes do relaunch, re-arma o monitoramento.
- (void)resumeIfNeeded;

/// Chamado em application:didFinishLaunchingWithOptions: com o valor de
/// UIApplicationLaunchOptionsLocationKey. Grava evidência do relaunch antes
/// de qualquer dependência da engine Flutter.
- (void)recordColdLaunchTriggeredByLocation:(BOOL)triggeredByLocation;

/// Se o processo atual foi (re)lançado por causa de um evento de
/// localização, segundo o próprio didFinishLaunchingWithOptions.
- (BOOL)wasLastLaunchTriggeredByLocation;

@end

NS_ASSUME_NONNULL_END
