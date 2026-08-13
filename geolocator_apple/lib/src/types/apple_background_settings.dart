import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import 'activity_type.dart';

/// iOS-specific configuration for background tracking, extending
/// [BackgroundTrackingSettings] with knobs that only make sense on iOS.
class AppleBackgroundSettings extends BackgroundTrackingSettings {
  /// Initializes a new [AppleBackgroundSettings] instance.
  ///
  /// The following default values are used:
  /// - showBackgroundLocationIndicator: false
  /// - pauseLocationUpdatesAutomatically: false
  /// - activityType: ActivityType.other
  /// - anchorRegionRadius: 100 (meters)
  /// - monitorVisits: false
  const AppleBackgroundSettings({
    this.showBackgroundLocationIndicator = false,
    this.pauseLocationUpdatesAutomatically = false,
    this.activityType = ActivityType.other,
    this.anchorRegionRadius = 100,
    this.monitorVisits = false,
    super.mode,
    super.accuracy,
    super.distanceFilter,
    super.minimumDistanceMeters,
    super.minimumInterval,
    super.maxBufferedPositions,
    super.maxPositionAge,
  });

  /// Shows the blue "background location indicator" bar while background
  /// tracking is active and the app is in the background.
  final bool showBackgroundLocationIndicator;

  /// Allows CoreLocation to pause updates automatically to save battery.
  ///
  /// Defaults to `false`: when `true`, resuming depends on the app
  /// correctly handling `locationManagerDidResumeLocationUpdates:` — in
  /// practice this has historically left tracking paused and never
  /// resumed, so keep this off unless you have a specific reason not to.
  final bool pauseLocationUpdatesAutomatically;

  /// A cue CoreLocation uses to decide when updates may be automatically
  /// paused. Only relevant when [pauseLocationUpdatesAutomatically] is
  /// `true`.
  final ActivityType activityType;

  /// Radius (in meters) of the circular "anchor" region used by
  /// `BackgroundTrackingMode.hybrid` as a relaunch safety net.
  final double anchorRegionRadius;

  /// Whether to also monitor visits (`CLVisit`) as an additional
  /// background relaunch trigger.
  final bool monitorVisits;

  /// Returns a JSON representation of this class.
  @override
  Map<String, dynamic> toJson() {
    return super.toJson()
      ..addAll({
        'showBackgroundLocationIndicator': showBackgroundLocationIndicator,
        'pauseLocationUpdatesAutomatically': pauseLocationUpdatesAutomatically,
        'activityType': activityType.index,
        'anchorRegionRadius': anchorRegionRadius,
        'monitorVisits': monitorVisits,
      });
  }
}
