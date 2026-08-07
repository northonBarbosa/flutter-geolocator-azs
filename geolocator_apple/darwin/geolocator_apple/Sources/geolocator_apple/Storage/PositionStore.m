//
//  PositionStore.m
//  geolocator_apple
//

#import "../include/geolocator_apple/Storage/PositionStore.h"

#import <sqlite3.h>

static NSInteger const kPruneEveryNInsertedRows = 20;

/// Mapeia o texto gravado na coluna `source` pro índice do enum
/// `PositionSource` do lado Dart (geolocator_platform_interface):
/// continuous(0), significantChange(1), region(2), visit(3).
static NSInteger PositionSourceIndexFromString(NSString *source) {
  if ([source isEqualToString:@"significantChange"]) {
    return 1;
  }
  if ([source isEqualToString:@"region"]) {
    return 2;
  }
  if ([source isEqualToString:@"visit"]) {
    return 3;
  }
  return 0; // "continuous" e qualquer valor desconhecido.
}

@interface PositionStore ()

@property (assign, nonatomic) sqlite3 *db;
@property (assign, nonatomic) NSInteger maxBufferedPositions;
@property (assign, nonatomic) NSTimeInterval maxPositionAgeSeconds;
@property (assign, nonatomic) NSUInteger rowsInsertedSincePrune;

@end

@implementation PositionStore

- (instancetype)initWithMaxBufferedPositions:(NSInteger)maxBufferedPositions
                       maxPositionAgeSeconds:(NSTimeInterval)maxPositionAgeSeconds {
  self = [super init];
  if (self) {
    _maxBufferedPositions = maxBufferedPositions;
    _maxPositionAgeSeconds = maxPositionAgeSeconds;
    _rowsInsertedSincePrune = 0;
    [self openDatabase];
  }
  return self;
}

- (void)dealloc {
  if (self.db != NULL) {
    sqlite3_close(self.db);
  }
}

#pragma mark - Setup

- (NSString *)databaseDirectoryPath {
  NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
      NSApplicationSupportDirectory, NSUserDomainMask, YES);
  NSString *appSupportDirectory = paths.firstObject;
  return [appSupportDirectory stringByAppendingPathComponent:@"geolocator_apple"];
}

- (NSString *)databasePath {
  return [[self databaseDirectoryPath]
      stringByAppendingPathComponent:@"background_positions.sqlite"];
}

- (void)openDatabase {
  NSString *directoryPath = [self databaseDirectoryPath];
  NSFileManager *fileManager = [NSFileManager defaultManager];

  // Seta a proteção no diretório: os arquivos -wal/-shm que o SQLite cria
  // por baixo dos panos herdam essa proteção automaticamente, sem depender
  // de reabrir o app pra reafirmar.
  [fileManager createDirectoryAtPath:directoryPath
          withIntermediateDirectories:YES
                           attributes:@{
                             NSFileProtectionKey :
                                 NSFileProtectionCompleteUntilFirstUserAuthentication
                           }
                                error:nil];

  NSString *path = [self databasePath];

  int openResult = sqlite3_open_v2(
      path.UTF8String, &_db,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL);

  if (openResult != SQLITE_OK) {
    NSLog(@"[geolocator_apple] PositionStore: falha ao abrir o banco (%d): %s",
          openResult, sqlite3_errmsg(_db));
    return;
  }

  // Reafirma a proteção no arquivo do banco em si: essa é a armadilha mais
  // cara do projeto — se o arquivo herdar NSFileProtectionComplete, toda
  // escrita falha enquanto o device está com a tela bloqueada, que é
  // justamente 90% do tempo real de uso do tracking.
  [fileManager setAttributes:@{
    NSFileProtectionKey : NSFileProtectionCompleteUntilFirstUserAuthentication
  }
                 ofItemAtPath:path
                        error:nil];

  [self execSQL:@"PRAGMA journal_mode=WAL;"];
  [self execSQL:@"CREATE TABLE IF NOT EXISTS positions ("
                @"  id                 INTEGER PRIMARY KEY AUTOINCREMENT,"
                @"  latitude           REAL    NOT NULL,"
                @"  longitude          REAL    NOT NULL,"
                @"  accuracy           REAL,"
                @"  altitude           REAL,"
                @"  altitude_accuracy  REAL,"
                @"  speed              REAL,"
                @"  speed_accuracy     REAL,"
                @"  heading            REAL,"
                @"  heading_accuracy   REAL,"
                @"  floor              INTEGER,"
                @"  is_mocked          INTEGER NOT NULL DEFAULT 0,"
                @"  timestamp_ms       INTEGER NOT NULL,"
                @"  recorded_at_ms     INTEGER NOT NULL,"
                @"  source             TEXT    NOT NULL,"
                @"  session_id         TEXT    NOT NULL"
                @");"];
  [self execSQL:@"CREATE INDEX IF NOT EXISTS idx_positions_recorded "
                @"ON positions(recorded_at_ms);"];
}

- (void)execSQL:(NSString *)sql {
  char *errorMessage = NULL;
  if (sqlite3_exec(self.db, sql.UTF8String, NULL, NULL, &errorMessage) != SQLITE_OK) {
    NSLog(@"[geolocator_apple] PositionStore: falha ao executar SQL (%@): %s", sql,
          errorMessage);
    sqlite3_free(errorMessage);
  }
}

#pragma mark - Escrita

- (void)insertLocations:(NSArray<CLLocation *> *)locations
                  source:(NSString *)source
               sessionId:(NSString *)sessionId {
  if (self.db == NULL || locations.count == 0) {
    return;
  }

  static const char *insertSQL =
      "INSERT INTO positions (latitude, longitude, accuracy, altitude, "
      "altitude_accuracy, speed, speed_accuracy, heading, heading_accuracy, "
      "floor, is_mocked, timestamp_ms, recorded_at_ms, source, session_id) "
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";

  sqlite3_stmt *statement = NULL;
  if (sqlite3_prepare_v2(self.db, insertSQL, -1, &statement, NULL) != SQLITE_OK) {
    NSLog(@"[geolocator_apple] PositionStore: falha ao preparar insert: %s",
          sqlite3_errmsg(self.db));
    return;
  }

  long long recordedAtMs = (long long)([[NSDate date] timeIntervalSince1970] * 1000);
  const char *sourceUTF8 = source.UTF8String;
  const char *sessionIdUTF8 = sessionId.UTF8String;

  [self execSQL:@"BEGIN IMMEDIATE TRANSACTION;"];

  for (CLLocation *location in locations) {
    sqlite3_reset(statement);
    sqlite3_clear_bindings(statement);

    BOOL isMocked = NO;
    if (@available(iOS 15.0, macOS 12.0, *)) {
      isMocked = location.sourceInformation.isSimulatedBySoftware;
    }

    double courseAccuracy = 0.0;
    if (@available(iOS 13.4, macOS 10.15.4, *)) {
      courseAccuracy = location.courseAccuracy;
    }

    long long timestampMs =
        (long long)([location.timestamp timeIntervalSince1970] * 1000);

    sqlite3_bind_double(statement, 1, location.coordinate.latitude);
    sqlite3_bind_double(statement, 2, location.coordinate.longitude);
    sqlite3_bind_double(statement, 3, location.horizontalAccuracy);
    sqlite3_bind_double(statement, 4, location.altitude);
    sqlite3_bind_double(statement, 5, location.verticalAccuracy);
    sqlite3_bind_double(statement, 6, location.speed);
    sqlite3_bind_double(statement, 7, location.speedAccuracy);
    sqlite3_bind_double(statement, 8, location.course);
    sqlite3_bind_double(statement, 9, courseAccuracy);

    if (location.floor != nil) {
      sqlite3_bind_int(statement, 10, (int)location.floor.level);
    } else {
      sqlite3_bind_null(statement, 10);
    }

    sqlite3_bind_int(statement, 11, isMocked ? 1 : 0);
    sqlite3_bind_int64(statement, 12, timestampMs);
    sqlite3_bind_int64(statement, 13, recordedAtMs);
    sqlite3_bind_text(statement, 14, sourceUTF8, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 15, sessionIdUTF8, -1, SQLITE_TRANSIENT);

    if (sqlite3_step(statement) != SQLITE_DONE) {
      NSLog(@"[geolocator_apple] PositionStore: falha ao inserir posição: %s",
            sqlite3_errmsg(self.db));
    }
  }

  [self execSQL:@"COMMIT;"];
  sqlite3_finalize(statement);

  self.rowsInsertedSincePrune += locations.count;
  if (self.rowsInsertedSincePrune >= kPruneEveryNInsertedRows) {
    self.rowsInsertedSincePrune = 0;
    [self prune];
  }
}

#pragma mark - Leitura

- (NSArray<NSDictionary<NSString *, id> *> *)queryPositionsWithLimit:(NSUInteger)limit {
  if (self.db == NULL) {
    return @[];
  }

  static const char *querySQL =
      "SELECT id, latitude, longitude, accuracy, altitude, altitude_accuracy, "
      "speed, speed_accuracy, heading, heading_accuracy, floor, is_mocked, "
      "timestamp_ms, recorded_at_ms, source, session_id FROM positions "
      "ORDER BY id ASC LIMIT ?;";

  sqlite3_stmt *statement = NULL;
  if (sqlite3_prepare_v2(self.db, querySQL, -1, &statement, NULL) != SQLITE_OK) {
    NSLog(@"[geolocator_apple] PositionStore: falha ao preparar query: %s",
          sqlite3_errmsg(self.db));
    return @[];
  }

  sqlite3_bind_int64(statement, 1, (sqlite3_int64)limit);

  NSMutableArray<NSDictionary<NSString *, id> *> *results = [NSMutableArray array];

  while (sqlite3_step(statement) == SQLITE_ROW) {
    NSMutableDictionary<NSString *, id> *row = [NSMutableDictionary dictionary];
    row[@"id"] = @(sqlite3_column_int64(statement, 0));
    row[@"latitude"] = @(sqlite3_column_double(statement, 1));
    row[@"longitude"] = @(sqlite3_column_double(statement, 2));
    row[@"accuracy"] = @(sqlite3_column_double(statement, 3));
    row[@"altitude"] = @(sqlite3_column_double(statement, 4));
    row[@"altitude_accuracy"] = @(sqlite3_column_double(statement, 5));
    row[@"speed"] = @(sqlite3_column_double(statement, 6));
    row[@"speed_accuracy"] = @(sqlite3_column_double(statement, 7));
    row[@"heading"] = @(sqlite3_column_double(statement, 8));
    row[@"heading_accuracy"] = @(sqlite3_column_double(statement, 9));

    if (sqlite3_column_type(statement, 10) != SQLITE_NULL) {
      row[@"floor"] = @(sqlite3_column_int(statement, 10));
    }

    row[@"is_mocked"] = @(sqlite3_column_int(statement, 11) != 0);
    row[@"timestamp"] = @(sqlite3_column_int64(statement, 12));
    row[@"recordedAtMillis"] = @(sqlite3_column_int64(statement, 13));

    const unsigned char *sourceText = sqlite3_column_text(statement, 14);
    NSString *source = sourceText != NULL
        ? [NSString stringWithUTF8String:(const char *)sourceText]
        : @"continuous";
    row[@"source"] = @(PositionSourceIndexFromString(source));

    const unsigned char *sessionIdText = sqlite3_column_text(statement, 15);
    row[@"sessionId"] = sessionIdText != NULL
        ? [NSString stringWithUTF8String:(const char *)sessionIdText]
        : @"";

    [results addObject:row];
  }

  sqlite3_finalize(statement);
  return results;
}

- (NSUInteger)positionCount {
  if (self.db == NULL) {
    return 0;
  }

  static const char *countSQL = "SELECT COUNT(*) FROM positions;";
  sqlite3_stmt *statement = NULL;
  NSUInteger count = 0;

  if (sqlite3_prepare_v2(self.db, countSQL, -1, &statement, NULL) == SQLITE_OK) {
    if (sqlite3_step(statement) == SQLITE_ROW) {
      count = (NSUInteger)sqlite3_column_int64(statement, 0);
    }
  }
  sqlite3_finalize(statement);
  return count;
}

#pragma mark - Remoção

- (void)acknowledgePositionIds:(NSArray<NSNumber *> *)ids {
  if (self.db == NULL || ids.count == 0) {
    return;
  }

  NSMutableArray<NSString *> *placeholders = [NSMutableArray arrayWithCapacity:ids.count];
  for (NSUInteger i = 0; i < ids.count; i++) {
    [placeholders addObject:@"?"];
  }

  NSString *sql = [NSString
      stringWithFormat:@"DELETE FROM positions WHERE id IN (%@);",
                        [placeholders componentsJoinedByString:@","]];

  sqlite3_stmt *statement = NULL;
  if (sqlite3_prepare_v2(self.db, sql.UTF8String, -1, &statement, NULL) != SQLITE_OK) {
    NSLog(@"[geolocator_apple] PositionStore: falha ao preparar ack: %s",
          sqlite3_errmsg(self.db));
    return;
  }

  [ids enumerateObjectsUsingBlock:^(NSNumber *_Nonnull idNumber, NSUInteger idx,
                                     BOOL *_Nonnull stop) {
    sqlite3_bind_int64(statement, (int)(idx + 1), idNumber.longLongValue);
  }];

  if (sqlite3_step(statement) != SQLITE_DONE) {
    NSLog(@"[geolocator_apple] PositionStore: falha ao remover posições "
          @"reconhecidas: %s",
          sqlite3_errmsg(self.db));
  }

  sqlite3_finalize(statement);
}

- (void)clearAllPositions {
  [self execSQL:@"DELETE FROM positions;"];
}

#pragma mark - Poda

- (void)prune {
  if (self.db == NULL) {
    return;
  }

  if (self.maxPositionAgeSeconds > 0) {
    long long cutoffMs = (long long)(([[NSDate date] timeIntervalSince1970] -
                                       self.maxPositionAgeSeconds) *
                                      1000);
    NSString *sql = [NSString
        stringWithFormat:@"DELETE FROM positions WHERE recorded_at_ms < %lld;",
                          cutoffMs];
    [self execSQL:sql];
  }

  if (self.maxBufferedPositions > 0) {
    NSUInteger count = [self positionCount];
    if (count > (NSUInteger)self.maxBufferedPositions) {
      NSUInteger excess = count - (NSUInteger)self.maxBufferedPositions;
      NSString *sql = [NSString
          stringWithFormat:@"DELETE FROM positions WHERE id IN (SELECT id FROM "
                            @"positions ORDER BY id ASC LIMIT %lu);",
                            (unsigned long)excess];
      [self execSQL:sql];
    }
  }
}

@end
