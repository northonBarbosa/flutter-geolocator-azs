/// An exception thrown when [GeolocatorPlatform.startBackgroundTracking] is
/// called but the host app is missing the platform configuration required
/// to keep running in the background (e.g. the `location` entry under
/// `UIBackgroundModes` in the iOS `Info.plist`).
class BackgroundModesNotConfiguredException implements Exception {
  /// Constructs the [BackgroundModesNotConfiguredException].
  const BackgroundModesNotConfiguredException(this.message);

  /// A [message] describing which configuration is missing.
  final String? message;

  @override
  String toString() {
    if (message == null || message == '') {
      return 'Background tracking requires additional platform '
          'configuration in the host app (e.g. `UIBackgroundModes: '
          '[location]` in the iOS Info.plist).';
    }
    return message!;
  }
}
