import '../enums/background_tracking_mode.dart';
import '../enums/location_accuracy.dart';

/// Platform-agnostic configuration for
/// [GeolocatorPlatform.startBackgroundTracking].
///
/// Platform packages that need additional, platform-specific knobs should
/// extend this class (see `AppleBackgroundSettings` in `geolocator_apple`).
class BackgroundTrackingSettings {
  /// Initializes a new [BackgroundTrackingSettings] instance.
  const BackgroundTrackingSettings({
    this.mode = BackgroundTrackingMode.hybrid,
    this.accuracy = LocationAccuracy.best,
    this.distanceFilter = 0,
    this.minimumDistanceMeters = 0,
    this.minimumInterval = Duration.zero,
    this.maxBufferedPositions = 50000,
    this.maxPositionAge,
  });

  /// The strategy used to keep producing positions in the background.
  ///
  /// Defaults to [BackgroundTrackingMode.hybrid].
  final BackgroundTrackingMode mode;

  /// The desired accuracy passed to the underlying platform location
  /// updates. Defaults to [LocationAccuracy.best].
  final LocationAccuracy accuracy;

  /// The OS-level distance filter (in meters), applied by the platform
  /// before a location update is even delivered to the plugin.
  ///
  /// This saves battery by suppressing wake-ups, but platforms may ignore it
  /// for triggers other than continuous updates (e.g. significant-location-
  /// change monitoring on iOS), and it is not guaranteed to survive a switch
  /// between [BackgroundTrackingMode]s. Use [minimumDistanceMeters] for a
  /// filter that is guaranteed to apply regardless of which trigger produced
  /// the position.
  final int distanceFilter;

  /// The minimum distance (in meters) between two buffered positions,
  /// enforced by the plugin itself before a position is written to the
  /// buffer. Defaults to 0 (no filter).
  final int minimumDistanceMeters;

  /// The minimum time between two buffered positions, enforced by the
  /// plugin itself before a position is written to the buffer. Defaults to
  /// [Duration.zero] (no filter).
  final Duration minimumInterval;

  /// The maximum number of positions kept in the buffer. Once exceeded, the
  /// oldest positions are discarded. Defaults to 50000.
  final int maxBufferedPositions;

  /// The maximum age a buffered position is allowed to reach before it is
  /// pruned. When null (the default) positions are never pruned by age.
  final Duration? maxPositionAge;

  /// Serializes this instance to a map that can be sent over a method
  /// channel. Platform-specific subclasses should override this and add
  /// their own fields on top of `super.toJson()`.
  Map<String, dynamic> toJson() => {
        'mode': mode.index,
        'accuracy': accuracy.index,
        'distanceFilter': distanceFilter,
        'minimumDistanceMeters': minimumDistanceMeters,
        'minimumIntervalMillis': minimumInterval.inMilliseconds,
        'maxBufferedPositions': maxBufferedPositions,
        'maxPositionAgeMillis': maxPositionAge?.inMilliseconds,
      };
}
