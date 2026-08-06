/// The strategy used by [GeolocatorPlatform.startBackgroundTracking] to keep
/// producing positions while the app is backgrounded or terminated by the
/// system.
enum BackgroundTrackingMode {
  /// Keeps standard location updates running (high precision, high battery
  /// cost). Does **not** relaunch the app after the system terminates it.
  continuous,

  /// Relies only on significant-location-change monitoring (and, on iOS,
  /// region monitoring). Low precision (hundreds of meters), very low
  /// battery cost, and survives app termination by the system.
  significant,

  /// Runs [continuous] while the app is alive and keeps [significant] armed
  /// at all times as a safety net that re-arms [continuous] after a
  /// system-triggered relaunch. This is the recommended default.
  hybrid,
}
