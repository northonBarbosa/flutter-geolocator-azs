//
//  BackgroundTrackingHandler.m
//  geolocator_apple
//

#import "../include/geolocator_apple/Handlers/BackgroundTrackingHandler.h"

#import "../include/geolocator_apple/Constants/ErrorCodes.h"
#import "../include/geolocator_apple/Handlers/GeolocationHandler.h"
#import "../include/geolocator_apple/Handlers/PermissionHandler.h"
#import "../include/geolocator_apple/Storage/PositionStore.h"
#import "../include/geolocator_apple/Storage/TrackingStateStore.h"
#import "../include/geolocator_apple/Utils/LocationAccuracyMapper.h"

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif

typedef NS_ENUM(NSInteger, GeolocatorBackgroundTrackingMode) {
  GeolocatorBackgroundTrackingModeContinuous = 0,
  GeolocatorBackgroundTrackingModeSignificant = 1,
  GeolocatorBackgroundTrackingModeHybrid = 2,
};

static NSString *const kAnchorRegionIdentifier = @"geolocator_apple.background_tracking.anchor";
static NSTimeInterval const kMaxLocationAgeSeconds = 60.0;
static NSTimeInterval const kBackgroundTaskGracePeriodSeconds = 2.0;

@interface BackgroundTrackingHandler ()

@property(strong, nonatomic) CLLocationManager *locationManager;
@property(strong, nonatomic) PermissionHandler *permissionHandler;
@property(strong, nonatomic) TrackingStateStore *trackingStateStore;
@property(strong, nonatomic, nullable) PositionStore *positionStore;
@property(strong, nonatomic, nullable) NSString *sessionId;

@property(assign, nonatomic) GeolocatorBackgroundTrackingMode mode;
@property(assign, nonatomic) CLLocationAccuracy desiredAccuracy;
@property(assign, nonatomic) CLLocationDistance distanceFilter;
@property(assign, nonatomic) double minimumDistanceMeters;
@property(assign, nonatomic) NSTimeInterval minimumInterval;
@property(assign, nonatomic) NSInteger maxBufferedPositions;
@property(assign, nonatomic) NSTimeInterval maxPositionAgeSeconds;
@property(assign, nonatomic) double anchorRegionRadius;
@property(assign, nonatomic) BOOL pauseLocationUpdatesAutomatically;
@property(assign, nonatomic) BOOL showBackgroundLocationIndicator;

@end

@implementation BackgroundTrackingHandler

- (instancetype)init {
  self = [super init];
  if (self) {
    _trackingStateStore = [[TrackingStateStore alloc] init];
    _permissionHandler = [[PermissionHandler alloc] init];
#if TARGET_OS_IOS
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(applicationDidEnterBackground)
               name:UIApplicationDidEnterBackgroundNotification
             object:nil];
#endif
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (CLLocationManager *)getLocationManager {
  if (!_locationManager) {
    _locationManager = [[CLLocationManager alloc] init];
    _locationManager.delegate = self;
  }
  return _locationManager;
}

#pragma mark - Start / Stop / Resume

- (void)startWithSettings:(NSDictionary<NSString *, id> *)settings
              errorHandler:(BackgroundTrackingErrorHandler)errorHandler {
#if TARGET_OS_IOS
  if ([self.permissionHandler checkPermission] != kCLAuthorizationStatusAuthorizedAlways) {
    errorHandler(GeolocatorErrorBackgroundPermissionDenied,
                 @"Background tracking requires \"Always\" location permission. Request it "
                 @"first via requestAlwaysPermission().");
    return;
  }

  if (![GeolocationHandler shouldEnableBackgroundLocationUpdates]) {
    errorHandler(GeolocatorErrorBackgroundModesNotConfigured,
                 @"UIBackgroundModes is missing the \"location\" entry in the app's "
                 @"Info.plist.");
    return;
  }
#endif

  [self applySettingsDictionary:settings];
  self.positionStore =
      [[PositionStore alloc] initWithMaxBufferedPositions:self.maxBufferedPositions
                                     maxPositionAgeSeconds:self.maxPositionAgeSeconds];
  [self.trackingStateStore startSessionWithSettings:settings];
  self.sessionId = self.trackingStateStore.sessionId;

  [self armTriggersForCurrentMode];
}

- (void)stop {
  CLLocationManager *manager = [self getLocationManager];
  [manager stopUpdatingLocation];
  [manager stopMonitoringSignificantLocationChanges];
  [self stopMonitoringAnchorRegion];

  [self.trackingStateStore stopSession];
  self.sessionId = nil;
}

- (BOOL)isActive {
  return self.trackingStateStore.isTrackingEnabled;
}

- (void)resumeFromPersistedStateIfNeeded {
  if (!self.trackingStateStore.isTrackingEnabled) {
    return;
  }

  NSDictionary<NSString *, id> *settings = self.trackingStateStore.serializedSettings;
  if (settings == nil) {
    return;
  }

  self.sessionId = self.trackingStateStore.sessionId;
  [self applySettingsDictionary:settings];
  self.positionStore =
      [[PositionStore alloc] initWithMaxBufferedPositions:self.maxBufferedPositions
                                     maxPositionAgeSeconds:self.maxPositionAgeSeconds];

  [self armTriggersForCurrentMode];
}

#pragma mark - Configuração

// [settings] espelha BackgroundTrackingSettings.toJson() (Fase 1). As
// chaves específicas do Apple (anchorRegionRadius,
// pauseLocationUpdatesAutomatically, showBackgroundLocationIndicator) ainda
// não são enviadas por nenhum caller real — isso chega quando
// AppleBackgroundSettings for construído (fase 7/8) — por isso os defaults
// abaixo.
- (void)applySettingsDictionary:(NSDictionary<NSString *, id> *)settings {
  self.mode = (GeolocatorBackgroundTrackingMode)[settings[@"mode"] integerValue];
  self.desiredAccuracy = [LocationAccuracyMapper toCLLocationAccuracy:settings[@"accuracy"]];
  self.distanceFilter = [settings[@"distanceFilter"] doubleValue];
  self.minimumDistanceMeters = [settings[@"minimumDistanceMeters"] doubleValue];
  self.minimumInterval = [settings[@"minimumIntervalMillis"] doubleValue] / 1000.0;
  self.maxBufferedPositions = [settings[@"maxBufferedPositions"] integerValue];

  id maxAgeMillis = settings[@"maxPositionAgeMillis"];
  self.maxPositionAgeSeconds =
      (maxAgeMillis == nil || maxAgeMillis == [NSNull null]) ? 0 : [maxAgeMillis doubleValue] / 1000.0;

  id anchorRadius = settings[@"anchorRegionRadius"];
  self.anchorRegionRadius = anchorRadius != nil ? [anchorRadius doubleValue] : 100.0;

  id pauseAutomatically = settings[@"pauseLocationUpdatesAutomatically"];
  self.pauseLocationUpdatesAutomatically =
      pauseAutomatically != nil ? [pauseAutomatically boolValue] : NO;

  id showIndicator = settings[@"showBackgroundLocationIndicator"];
  self.showBackgroundLocationIndicator = showIndicator != nil ? [showIndicator boolValue] : NO;
}

#pragma mark - Gatilhos por modo

- (void)armTriggersForCurrentMode {
  switch (self.mode) {
    case GeolocatorBackgroundTrackingModeContinuous:
      [self armContinuousUpdates];
      break;
    case GeolocatorBackgroundTrackingModeSignificant:
      [self armSignificantLocationChanges];
      break;
    case GeolocatorBackgroundTrackingModeHybrid:
      [self armContinuousUpdates];
      [self armSignificantLocationChanges];
      [self armAnchorRegionIfPossible];
      break;
  }
}

- (void)armContinuousUpdates {
  CLLocationManager *manager = [self getLocationManager];
  manager.desiredAccuracy = self.desiredAccuracy;
  manager.distanceFilter = self.distanceFilter;
  if (@available(iOS 6.0, macOS 10.15, *)) {
    manager.activityType = CLActivityTypeOther;
    // Default NO: se true, a retomada depende de
    // locationManagerDidResumeLocationUpdates:, e historicamente o tracking
    // pausa e não volta (docs/PLANO_BACKGROUND_IOS.md §1.2f).
    manager.pausesLocationUpdatesAutomatically = self.pauseLocationUpdatesAutomatically;
  }
#if TARGET_OS_IOS
  manager.allowsBackgroundLocationUpdates = [GeolocationHandler shouldEnableBackgroundLocationUpdates];
  manager.showsBackgroundLocationIndicator = self.showBackgroundLocationIndicator;
#endif
  [manager startUpdatingLocation];
}

- (void)armSignificantLocationChanges {
  if (![CLLocationManager significantLocationChangeMonitoringAvailable]) {
    return;
  }
  [[self getLocationManager] startMonitoringSignificantLocationChanges];
}

#pragma mark - Região âncora (modo hybrid)

- (void)armAnchorRegionIfPossible {
  if (![CLLocationManager isMonitoringAvailableForClass:[CLCircularRegion class]]) {
    return;
  }

  if (self.trackingStateStore.hasAnchor) {
    [self repositionAnchorRegionToLatitude:self.trackingStateStore.anchorLatitude
                                  longitude:self.trackingStateStore.anchorLongitude];
    return;
  }

  // Sem âncora persistida ainda (primeiro start): usa a última posição
  // conhecida em cache, se houver. Caso contrário a âncora só é armada
  // quando o primeiro fix chegar (ver didUpdateLocations:).
  CLLocation *lastKnown = [self getLocationManager].location;
  if (lastKnown != nil) {
    [self repositionAnchorRegionToLatitude:lastKnown.coordinate.latitude
                                  longitude:lastKnown.coordinate.longitude];
  }
}

- (void)repositionAnchorRegionToLatitude:(double)latitude longitude:(double)longitude {
  [self stopMonitoringAnchorRegion];

  CLLocationCoordinate2D center = CLLocationCoordinate2DMake(latitude, longitude);
  CLCircularRegion *region = [[CLCircularRegion alloc] initWithCenter:center
                                                                 radius:self.anchorRegionRadius
                                                             identifier:kAnchorRegionIdentifier];
  region.notifyOnEntry = NO;
  region.notifyOnExit = YES;
  [[self getLocationManager] startMonitoringForRegion:region];
  [self.trackingStateStore updateAnchorWithLatitude:latitude longitude:longitude];
}

- (void)stopMonitoringAnchorRegion {
  CLLocationManager *manager = [self getLocationManager];
  for (CLRegion *region in manager.monitoredRegions) {
    if ([region.identifier isEqualToString:kAnchorRegionIdentifier]) {
      [manager stopMonitoringForRegion:region];
    }
  }
}

- (void)repositionAnchorRegionIfNeededForLocation:(CLLocation *)location {
  if (!self.trackingStateStore.hasAnchor) {
    [self repositionAnchorRegionToLatitude:location.coordinate.latitude
                                  longitude:location.coordinate.longitude];
    return;
  }

  CLLocation *anchor =
      [[CLLocation alloc] initWithLatitude:self.trackingStateStore.anchorLatitude
                                  longitude:self.trackingStateStore.anchorLongitude];
  CLLocationDistance distanceFromAnchor = [location distanceFromLocation:anchor];
  if (distanceFromAnchor > self.anchorRegionRadius / 2.0) {
    [self repositionAnchorRegionToLatitude:location.coordinate.latitude
                                  longitude:location.coordinate.longitude];
  }
}

#pragma mark - Filtros

- (BOOL)isLocationValid:(CLLocation *)location {
  if (location.horizontalAccuracy < 0) {
    return NO;
  }
  NSTimeInterval ageInSeconds = -[location.timestamp timeIntervalSinceNow];
  return ageInSeconds <= kMaxLocationAgeSeconds;
}

// minimumDistanceMeters/minimumInterval são aplicados aqui, e não via
// CLLocationManager.distanceFilter, porque o distanceFilter do SO é
// ignorado no SLC e é resetado a cada troca de gatilho — este filtro é a
// garantia de que a fila não infla, independente de qual gatilho produziu
// o ponto, e sobrevive a relaunches porque lê/grava no TrackingStateStore.
- (BOOL)passesMinimumFilters:(CLLocation *)location {
  if (!self.trackingStateStore.hasLastEmitted) {
    return YES;
  }

  NSTimeInterval lastEmittedSeconds = self.trackingStateStore.lastEmittedTimestampMs / 1000.0;
  NSTimeInterval elapsed = [location.timestamp timeIntervalSince1970] - lastEmittedSeconds;
  if (self.minimumInterval > 0 && elapsed < self.minimumInterval) {
    return NO;
  }

  if (self.minimumDistanceMeters > 0) {
    CLLocation *lastEmittedLocation =
        [[CLLocation alloc] initWithLatitude:self.trackingStateStore.lastEmittedLatitude
                                    longitude:self.trackingStateStore.lastEmittedLongitude];
    if ([location distanceFromLocation:lastEmittedLocation] < self.minimumDistanceMeters) {
      return NO;
    }
  }

  return YES;
}

- (void)recordEmittedLocation:(CLLocation *)location {
  NSInteger timestampMs = (NSInteger)([location.timestamp timeIntervalSince1970] * 1000);
  [self.trackingStateStore updateLastEmittedLatitude:location.coordinate.latitude
                                            longitude:location.coordinate.longitude
                                          timestampMs:timestampMs];
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager
      didUpdateLocations:(NSArray<CLLocation *> *)locations {
  if (self.positionStore == nil || self.sessionId == nil) {
    return;
  }

  NSMutableArray<CLLocation *> *accepted = [NSMutableArray arrayWithCapacity:locations.count];
  for (CLLocation *location in locations) {
    if (![self isLocationValid:location] || ![self passesMinimumFilters:location]) {
      continue;
    }
    [accepted addObject:location];
    [self recordEmittedLocation:location];
  }

  if (accepted.count == 0) {
    return;
  }

  [self.positionStore insertLocations:accepted source:@"continuous" sessionId:self.sessionId];

  if (self.mode == GeolocatorBackgroundTrackingModeHybrid) {
    [self repositionAnchorRegionIfNeededForLocation:accepted.lastObject];
  }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
  NSLog(@"[geolocator_apple] BackgroundTrackingHandler: didFailWithError: %@",
        error.localizedDescription);
}

- (void)locationManager:(CLLocationManager *)manager
       didDetermineState:(CLRegionState)state
               forRegion:(CLRegion *)region {
  if (![region.identifier isEqualToString:kAnchorRegionIdentifier]) {
    return;
  }
  if (state != CLRegionStateOutside || self.positionStore == nil || self.sessionId == nil) {
    return;
  }

  // Saiu da âncora: sinal de movimento. Se o processo foi relançado só por
  // isso (SLC ainda não disparou), garante que os updates contínuos estão
  // religados; a âncora em si é reposicionada no próximo fix aceito.
  if (self.mode == GeolocatorBackgroundTrackingModeHybrid) {
    [self armContinuousUpdates];
  }
}

- (void)locationManagerDidPauseLocationUpdates:(CLLocationManager *)manager {
  NSLog(@"[geolocator_apple] BackgroundTrackingHandler: updates pausados pelo sistema.");
}

- (void)locationManagerDidResumeLocationUpdates:(CLLocationManager *)manager {
  NSLog(@"[geolocator_apple] BackgroundTrackingHandler: updates retomados pelo sistema.");
}

- (void)locationManager:(CLLocationManager *)manager
    didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
  [self handleAuthorizationChange:status];
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager
    API_AVAILABLE(ios(14.0), macos(11.0)) {
  [self handleAuthorizationChange:manager.authorizationStatus];
}

// Se o usuário rebaixar a permissão de Always durante o tracking (em
// Ajustes, fora do app), para de forma limpa em vez de continuar queimando
// bateria sem conseguir produzir nada.
- (void)handleAuthorizationChange:(CLAuthorizationStatus)status {
  if (![self isActive] || status == kCLAuthorizationStatusNotDetermined) {
    return;
  }
  if (status != kCLAuthorizationStatusAuthorizedAlways) {
    NSLog(@"[geolocator_apple] BackgroundTrackingHandler: permissão mudou para %ld durante "
          @"tracking ativo, parando.",
          (long)status);
    [self stop];
  }
}

#pragma mark - Background task

#if TARGET_OS_IOS
- (void)applicationDidEnterBackground {
  if (![self isActive]) {
    return;
  }

  UIApplication *application = [UIApplication sharedApplication];
  __block UIBackgroundTaskIdentifier taskId = UIBackgroundTaskInvalid;
  taskId = [application beginBackgroundTaskWithExpirationHandler:^{
    [application endBackgroundTask:taskId];
  }];

  if (taskId == UIBackgroundTaskInvalid) {
    return;
  }

  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kBackgroundTaskGracePeriodSeconds * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        [application endBackgroundTask:taskId];
      });
}
#endif

@end
