//
//  SpikeBackgroundTrackingHandler.m
//  geolocator_apple
//

#import "../include/geolocator_apple/Handlers/SpikeBackgroundTrackingHandler.h"
#import "../include/geolocator_apple/Handlers/GeolocationHandler.h"

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif

static NSString *const kSpikeIsActiveKey = @"geolocator_apple.spike.isActive";
static NSString *const kSpikeEventsKey = @"geolocator_apple.spike.events";
static NSString *const kSpikeLastLaunchWasLocationKey = @"geolocator_apple.spike.lastLaunchWasLocation";
static NSUInteger const kSpikeMaxLoggedEvents = 200;

@interface SpikeBackgroundTrackingHandler ()

@property(strong, nonatomic) CLLocationManager *locationManager;

@end

@implementation SpikeBackgroundTrackingHandler

- (CLLocationManager *)getLocationManager {
  if (!_locationManager) {
    _locationManager = [[CLLocationManager alloc] init];
    _locationManager.delegate = self;
#if TARGET_OS_IOS
    _locationManager.pausesLocationUpdatesAutomatically = NO;
    _locationManager.allowsBackgroundLocationUpdates =
        [GeolocationHandler shouldEnableBackgroundLocationUpdates];
#endif
  }
  return _locationManager;
}

- (void)startSpikeWithErrorHandler:(SpikeErrorHandler)errorHandler {
  if (![CLLocationManager significantLocationChangeMonitoringAvailable]) {
    errorHandler(@"SPIKE_SLC_UNAVAILABLE",
                 @"significantLocationChangeMonitoringAvailable retornou NO neste device.");
    return;
  }

  CLAuthorizationStatus status = [[self getLocationManager] authorizationStatus];
  if (status != kCLAuthorizationStatusAuthorizedAlways) {
    errorHandler(@"SPIKE_ALWAYS_PERMISSION_REQUIRED",
                 @"É preciso permissão \"Always\" (conceda manualmente em "
                 @"Ajustes > Privacidade > Localização para este app — o fluxo "
                 @"de dois passos automático é item de outra fase do plano).");
    return;
  }

  [self appendLogEventWithSource:@"spikeStart" location:nil];
  [[self getLocationManager] startMonitoringSignificantLocationChanges];
  [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kSpikeIsActiveKey];
}

- (void)stopSpike {
  [[self getLocationManager] stopMonitoringSignificantLocationChanges];
  [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kSpikeIsActiveKey];
  [self appendLogEventWithSource:@"spikeStop" location:nil];
}

- (BOOL)isSpikeActive {
  return [[NSUserDefaults standardUserDefaults] boolForKey:kSpikeIsActiveKey];
}

- (void)resumeIfNeeded {
  if (![self isSpikeActive]) {
    return;
  }
  [self appendLogEventWithSource:@"resumeAfterRelaunch" location:nil];
  [[self getLocationManager] startMonitoringSignificantLocationChanges];
}

- (void)recordColdLaunchTriggeredByLocation:(BOOL)triggeredByLocation {
  [[NSUserDefaults standardUserDefaults] setBool:triggeredByLocation
                                           forKey:kSpikeLastLaunchWasLocationKey];
  if (triggeredByLocation) {
    [self appendLogEventWithSource:@"coldLaunchLocationKey" location:nil];
  }
}

- (BOOL)wasLastLaunchTriggeredByLocation {
  return [[NSUserDefaults standardUserDefaults] boolForKey:kSpikeLastLaunchWasLocationKey];
}

- (NSArray<NSDictionary<NSString *, id> *> *)loggedEvents {
  NSArray *events = [[NSUserDefaults standardUserDefaults] arrayForKey:kSpikeEventsKey];
  return events ?: @[];
}

- (void)clearLog {
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSpikeEventsKey];
}

- (void)appendLogEventWithSource:(NSString *)source location:(nullable CLLocation *)location {
  NSMutableDictionary<NSString *, id> *event = [NSMutableDictionary dictionary];
  event[@"source"] = source;
  event[@"recordedAtMs"] = @((long long)([[NSDate date] timeIntervalSince1970] * 1000));
  event[@"appState"] = [self appStateDescription];
  if (location != nil) {
    event[@"latitude"] = @(location.coordinate.latitude);
    event[@"longitude"] = @(location.coordinate.longitude);
    event[@"horizontalAccuracy"] = @(location.horizontalAccuracy);
    event[@"timestampMs"] = @((long long)([location.timestamp timeIntervalSince1970] * 1000));
  }

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSArray<NSDictionary<NSString *, id> *> *existing = [defaults arrayForKey:kSpikeEventsKey] ?: @[];
  NSMutableArray<NSDictionary<NSString *, id> *> *updated = [existing mutableCopy];
  [updated addObject:event];

  if (updated.count > kSpikeMaxLoggedEvents) {
    NSUInteger overflow = updated.count - kSpikeMaxLoggedEvents;
    [updated removeObjectsInRange:NSMakeRange(0, overflow)];
  }

  [defaults setObject:updated forKey:kSpikeEventsKey];
}

- (NSString *)appStateDescription {
#if TARGET_OS_IOS
  switch (UIApplication.sharedApplication.applicationState) {
    case UIApplicationStateActive:
      return @"active";
    case UIApplicationStateInactive:
      return @"inactive";
    case UIApplicationStateBackground:
      return @"background";
  }
#endif
  return @"unknown";
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
  for (CLLocation *location in locations) {
    [self appendLogEventWithSource:@"significantChange" location:location];
  }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
  [self appendLogEventWithSource:[NSString stringWithFormat:@"error:%@", error.localizedDescription]
                         location:nil];
}

@end
