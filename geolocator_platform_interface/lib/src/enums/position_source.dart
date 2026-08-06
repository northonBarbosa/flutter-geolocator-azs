/// The platform mechanism that produced a [BufferedPosition].
enum PositionSource {
  /// Produced by standard, continuous location updates.
  continuous,

  /// Produced by significant-location-change monitoring.
  significantChange,

  /// Produced by region monitoring (e.g. the anchor region used by the
  /// `hybrid` [BackgroundTrackingMode] on iOS).
  region,

  /// Produced by visit monitoring.
  visit,
}
