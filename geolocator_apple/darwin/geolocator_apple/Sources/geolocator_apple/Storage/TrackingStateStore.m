//
//  TrackingStateStore.m
//  geolocator_apple
//

#import "../include/geolocator_apple/Storage/TrackingStateStore.h"

static NSString *const kIsTrackingEnabledKey =
    @"geolocator_apple.background_tracking.isEnabled";
static NSString *const kSessionIdKey =
    @"geolocator_apple.background_tracking.sessionId";
static NSString *const kSerializedSettingsKey =
    @"geolocator_apple.background_tracking.settings";
static NSString *const kHasAnchorKey =
    @"geolocator_apple.background_tracking.hasAnchor";
static NSString *const kAnchorLatitudeKey =
    @"geolocator_apple.background_tracking.anchorLatitude";
static NSString *const kAnchorLongitudeKey =
    @"geolocator_apple.background_tracking.anchorLongitude";
static NSString *const kHasLastEmittedKey =
    @"geolocator_apple.background_tracking.hasLastEmitted";
static NSString *const kLastEmittedLatitudeKey =
    @"geolocator_apple.background_tracking.lastEmittedLatitude";
static NSString *const kLastEmittedLongitudeKey =
    @"geolocator_apple.background_tracking.lastEmittedLongitude";
static NSString *const kLastEmittedTimestampMsKey =
    @"geolocator_apple.background_tracking.lastEmittedTimestampMs";

@implementation TrackingStateStore

- (BOOL)isTrackingEnabled {
  return [[NSUserDefaults standardUserDefaults] boolForKey:kIsTrackingEnabledKey];
}

- (nullable NSString *)sessionId {
  return [[NSUserDefaults standardUserDefaults] stringForKey:kSessionIdKey];
}

- (nullable NSDictionary<NSString *, id> *)serializedSettings {
  return [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSerializedSettingsKey];
}

- (void)startSessionWithSettings:(NSDictionary<NSString *, id> *)settings {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setBool:YES forKey:kIsTrackingEnabledKey];
  [defaults setObject:[[NSUUID UUID] UUIDString] forKey:kSessionIdKey];
  [defaults setObject:settings forKey:kSerializedSettingsKey];
  [defaults setBool:NO forKey:kHasAnchorKey];
  [defaults setBool:NO forKey:kHasLastEmittedKey];
}

- (void)stopSession {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setBool:NO forKey:kIsTrackingEnabledKey];
  [defaults removeObjectForKey:kSessionIdKey];
  [defaults removeObjectForKey:kSerializedSettingsKey];
  [defaults setBool:NO forKey:kHasAnchorKey];
  [defaults setBool:NO forKey:kHasLastEmittedKey];
}

- (BOOL)hasAnchor {
  return [[NSUserDefaults standardUserDefaults] boolForKey:kHasAnchorKey];
}

- (double)anchorLatitude {
  return [[NSUserDefaults standardUserDefaults] doubleForKey:kAnchorLatitudeKey];
}

- (double)anchorLongitude {
  return [[NSUserDefaults standardUserDefaults] doubleForKey:kAnchorLongitudeKey];
}

- (void)updateAnchorWithLatitude:(double)latitude longitude:(double)longitude {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setDouble:latitude forKey:kAnchorLatitudeKey];
  [defaults setDouble:longitude forKey:kAnchorLongitudeKey];
  [defaults setBool:YES forKey:kHasAnchorKey];
}

- (BOOL)hasLastEmitted {
  return [[NSUserDefaults standardUserDefaults] boolForKey:kHasLastEmittedKey];
}

- (double)lastEmittedLatitude {
  return [[NSUserDefaults standardUserDefaults] doubleForKey:kLastEmittedLatitudeKey];
}

- (double)lastEmittedLongitude {
  return [[NSUserDefaults standardUserDefaults] doubleForKey:kLastEmittedLongitudeKey];
}

- (NSInteger)lastEmittedTimestampMs {
  return [[NSUserDefaults standardUserDefaults] integerForKey:kLastEmittedTimestampMsKey];
}

- (void)updateLastEmittedLatitude:(double)latitude
                          longitude:(double)longitude
                     timestampMs:(NSInteger)timestampMs {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setDouble:latitude forKey:kLastEmittedLatitudeKey];
  [defaults setDouble:longitude forKey:kLastEmittedLongitudeKey];
  [defaults setInteger:timestampMs forKey:kLastEmittedTimestampMsKey];
  [defaults setBool:YES forKey:kHasLastEmittedKey];
}

@end
