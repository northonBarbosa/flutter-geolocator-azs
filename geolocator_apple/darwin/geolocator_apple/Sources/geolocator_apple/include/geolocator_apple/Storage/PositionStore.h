//
//  PositionStore.h
//  geolocator_apple
//
//  Fila persistente de posições (docs/PLANO_BACKGROUND_IOS.md §3.3). O
//  caminho crítico (CoreLocation -> aqui) nunca depende da engine Flutter
//  estar viva — o Dart é só um consumidor opcional que drena quando pode.
//

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Fila persistente de posições em SQLite (WAL).
///
/// Thread-safety: a conexão é aberta com `SQLITE_OPEN_FULLMUTEX`, então
/// todos os métodos públicos podem ser chamados de qualquer thread sem
/// sincronização adicional por parte de quem chama.
@interface PositionStore : NSObject

/// [maxBufferedPositions] <= 0 desativa o cap por contagem.
/// [maxPositionAgeSeconds] <= 0 desativa a poda por idade (TTL).
- (instancetype)initWithMaxBufferedPositions:(NSInteger)maxBufferedPositions
                       maxPositionAgeSeconds:(NSTimeInterval)maxPositionAgeSeconds;

/// Insere [locations] em uma única transação. [source] deve corresponder a
/// um dos casos do enum `PositionSource` do lado Dart (ex.
/// `"significantChange"`) — ver `PositionSourceIndexFromString` em
/// PositionStore.m para o mapeamento exato usado em `queryPositionsWithLimit:`.
///
/// Não valida nem filtra os fixes (idade, acurácia etc.) — isso é
/// responsabilidade de quem produz [locations] (`BackgroundTrackingHandler`,
/// fase 4 do plano). Depois de inserir, poda a fila se necessário.
- (void)insertLocations:(NSArray<CLLocation *> *)locations
                  source:(NSString *)source
               sessionId:(NSString *)sessionId;

/// Lê até [limit] posições, as mais antigas primeiro, sem removê-las da
/// fila. As chaves de cada dicionário correspondem ao que
/// `BufferedPosition.fromMap` (geolocator_platform_interface) espera.
- (NSArray<NSDictionary<NSString *, id> *> *)queryPositionsWithLimit:(NSUInteger)limit;

/// Número de posições atualmente na fila.
- (NSUInteger)positionCount;

/// Remove as posições com os `id`s informados (ver protocolo drain→ack).
- (void)acknowledgePositionIds:(NSArray<NSNumber *> *)ids;

/// Remove todas as posições da fila.
- (void)clearAllPositions;

@end

NS_ASSUME_NONNULL_END
