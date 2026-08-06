/// An exception thrown when [GeolocatorPlatform.startBackgroundTracking] is
/// called without the app having been granted `LocationPermission.always`.
class BackgroundPermissionDeniedException implements Exception {
  /// Constructs the [BackgroundPermissionDeniedException].
  const BackgroundPermissionDeniedException(this.message);

  /// A [message] describing more details on the denied permission.
  final String? message;

  @override
  String toString() {
    if (message == null || message == '') {
      return 'Background tracking requires "Always" location permission. '
          'Request it first, for example via '
          'GeolocatorPlatform.requestAlwaysPermission().';
    }
    return message!;
  }
}
