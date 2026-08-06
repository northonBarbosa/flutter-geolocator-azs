import 'dart:async';
import 'dart:math';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vector_math/vector_math.dart';

import 'enums/enums.dart';
import 'implementations/method_channel_geolocator.dart';
import 'models/models.dart';

/// The interface that implementations of geolocator  must implement.
///
/// Platform implementations should extend this class rather than implement it
/// as `geolocator` does not consider newly added methods to be breaking
/// changes. Extending this class (using `extends`) ensures that the subclass
/// will get the default implementation, while platform implementations that
/// `implements` this interface will be broken by newly added
/// [GeolocatorPlatform] methods.
abstract class GeolocatorPlatform extends PlatformInterface {
  /// Constructs a GeolocatorPlatform.
  GeolocatorPlatform() : super(token: _token);

  static final Object _token = Object();

  static GeolocatorPlatform _instance = MethodChannelGeolocator();

  /// The default instance of [GeolocatorPlatform] to use.
  ///
  /// Defaults to [MethodChannelGeolocator].
  static GeolocatorPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own
  /// platform-specific class that extends [GeolocatorPlatform] when they
  /// register themselves.
  static set instance(GeolocatorPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Returns a [Future] indicating if the user allows the App to access
  /// the device's location.
  ///
  /// Note: on the web platform not all browsers implement the [Permission API](https://developer.mozilla.org/en-US/docs/Web/API/Permissions_API)
  /// if this is the case the `LocationPermission.unableToDetermine` is returned
  /// as the plugin cannot determine the if permissions are granted or denied.
  Future<LocationPermission> checkPermission() {
    throw UnimplementedError(
      'checkPermission() has not been implemented.',
    );
  }

  /// Request permission to access the location of the device.
  ///
  /// Returns a [Future] which when completes indicates if the user granted
  /// permission to access the device's location.
  /// Throws a [PermissionDefinitionsNotFoundException] when the required
  /// platform specific configuration is missing (e.g. in the
  /// AndroidManifest.xml on Android or the Info.plist on iOS).
  /// A [PermissionRequestInProgressException] is thrown if permissions are
  /// requested while an earlier request has not yet been completed.
  Future<LocationPermission> requestPermission() {
    throw UnimplementedError('requestPermission() has not been implemented.');
  }

  /// Returns a [Future] containing a [bool] value indicating whether location
  /// services are enabled on the device.
  Future<bool> isLocationServiceEnabled() {
    throw UnimplementedError(
      'isLocationServiceEnabled() has not been implemented.',
    );
  }

  /// Returns the last known position stored on the users device.
  ///
  /// On Android you can force the plugin to use the old Android
  /// LocationManager implementation over the newer FusedLocationProvider by
  /// passing true to the [forceLocationManager] parameter. On iOS
  /// this parameter is ignored.
  /// When no position is available, null is returned.
  /// Throws a [PermissionDeniedException] when trying to request the device's
  /// location when the user denied access.
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) {
    throw UnimplementedError(
      'getLastKnownPosition() has not been implemented.',
    );
  }

  /// Returns the current position.
  ///
  /// You can control the settings used for retrieving the location by supplying
  /// [locationSettings].
  ///
  /// Calling the [getCurrentPosition] method will request the platform to
  /// obtain a location fix. Depending on the availability of different location
  /// services, this can take several seconds. The recommended use would be to
  /// call the [getLastKnownPosition] method to receive a cached position and
  /// update it with the result of the [getCurrentPosition] method.
  ///
  /// **Note**: On Android, when setting the location accuracy, the location
  /// *accuracy* is interpreted as
  /// [location *priority*](https://developers.google.com/android/reference/com/google/android/gms/location/Priority#constants).
  /// The interpretation works as follows:
  ///
  /// [LocationAccuracy.lowest] -> [PRIORITY_PASSIVE](https://developers.google.com/android/reference/com/google/android/gms/location/Priority#public-static-final-int-priority_passive):
  /// Ensures that no extra power will be used to derive locations. This
  /// enforces that the request will act as a passive listener that will only
  /// receive "free" locations calculated on behalf of other clients, and no
  /// locations will be calculated on behalf of only this request.
  ///
  /// [LocationAccuracy.low] -> [PRIORITY_LOW_POWER](https://developers.google.com/android/reference/com/google/android/gms/location/Priority#public-static-final-int-priority_low_power):
  /// Requests a tradeoff that favors low power usage at the possible expense of
  /// location accuracy.
  ///
  /// [LocationAccuracy.medium] -> [PRIORITY_BALANCED_POWER_ACCURACY](https://developers.google.com/android/reference/com/google/android/gms/location/Priority#public-static-final-int-priority_balanced_power_accuracy):
  /// Requests a tradeoff that is balanced between location accuracy and power
  /// usage.
  ///
  /// [LocationAccuracy.high]+ -> [PRIORITY_HIGH_ACCURACY](https://developers.google.com/android/reference/com/google/android/gms/location/Priority#public-static-final-int-priority_high_accuracy):
  /// Requests a tradeoff that favors highly accurate locations at the possible
  /// expense of additional power usage.
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) {
    throw UnimplementedError('getCurrentPosition() has not been implemented.');
  }

  /// Fires when the location Service is manually disabled or enabled.
  ///
  /// An instance of [LocationServiceStatus] will be emitted each time the
  /// location service is enabled or disabled.
  Stream<ServiceStatus> getServiceStatusStream() {
    throw UnimplementedError(
        'getServiceStatusStream() has not been implemented.');
  }

  /// Fires whenever the location changes inside the bounds of the
  /// [desiredAccuracy].
  ///
  /// This event starts all location sensors on the device and will keep them
  /// active until you cancel listening to the stream or when the application
  /// is killed.
  ///
  /// ```
  /// StreamSubscription<Position> positionStream = getPositionStream()
  ///     .listen((Position position) {
  ///       // Handle position changes
  ///     });
  ///
  /// // When no longer needed cancel the subscription
  /// positionStream.cancel();
  /// ```
  ///
  /// You can control the precision of the location updates by supplying the
  /// [desiredAccuracy] parameter (defaults to "best"). The [distanceFilter]
  /// parameter controls the minimum distance the device needs to move before
  /// the update is emitted (default value is 0 indicator no filter is used).
  /// On Android you can force the use of the Android LocationManager instead
  /// of the FusedLocationProvider by setting the [forceLocationManager]
  /// parameter of [LocationSettings] to true. Using the [timeInterval]
  /// of [LocationSettings] you can control the amount of time that needs to
  /// pass before the next position update is send.
  ///
  /// Throws a [PermissionDeniedException] when trying to request the device's
  /// location when the user denied access.
  /// Throws a [LocationServiceDisabledException] when the user allowed access,
  /// but the location services of the device are disabled.
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) {
    throw UnimplementedError('getPositionStream() has not been implemented.');
  }

  /// Asks the user for Temporary Precise location access (iOS 14 or above).
  ///
  /// Returns [LocationAccuracyStatus.precise] if the user already gave
  /// permission to use Precise Accuracy. If the user uses iOS 13 or below,
  /// [LocationAccuracyStatus.precise] will also be returned. On other platforms
  /// an PlatformException will be thrown.
  ///
  /// The `required` property [purposeKey] should correspond with the [key]
  /// value set in the [NSLocationTemporaryUsageDescriptionDictionary]
  /// dictionary, which should be added to the `Info.plist` as stated in the
  /// [documentation](https://developer.apple.com/documentation/bundleresources/information_property_list/nslocationtemporaryusagedescriptiondictionary).
  ///
  /// Throws a [PermissionDefinitionsNotFoundException] when the key
  /// `NSLocationTemporaryUsageDescriptionDictionary` has not been set in the
  /// `Infop.list`.
  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({
    required String purposeKey,
  }) async {
    throw UnimplementedError(
        'requestTemporaryFullAccuracy() has not been implemented');
  }

  /// Returns a [Future] containing a [LocationAccuracyStatus].
  ///
  /// When on iOS the user has given permission for approximate location,
  /// [LocationAccuracyStatus.reduced] will be returned, if the user gave
  /// permission for precise/full accuracy location, [LocationAccuracyStatus.precise]
  /// will be returned.
  /// When executing the method on platforms that don't support location
  /// accuracy features [LocationAccuracyStatus.unknown] should be returned.
  Future<LocationAccuracyStatus> getLocationAccuracy() async {
    throw UnimplementedError('getLocationAccuracy() has not been implemented.');
  }

  /// Opens the App settings page.
  ///
  /// Returns [true] if the app settings page could be opened, otherwise
  /// [false] is returned.
  Future<bool> openAppSettings() async {
    throw UnimplementedError('openAppSettings() has not been implemented.');
  }

  /// Opens the location settings page.
  ///
  /// Returns [true] if the location settings page could be opened, otherwise
  /// [false] is returned.
  Future<bool> openLocationSettings() async {
    throw UnimplementedError(
        'openLocationSettings() has not been implemented.');
  }

  /// Calculates the distance between the supplied coordinates in meters.
  ///
  /// The distance between the coordinates is calculated using the Haversine
  /// formula (see https://en.wikipedia.org/wiki/Haversine_formula). The
  /// supplied coordinates [startLatitude], [startLongitude], [endLatitude] and
  /// [endLongitude] should be supplied in degrees.
  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    var earthRadius = 6378137.0;
    var dLat = _toRadians(endLatitude - startLatitude);
    var dLon = _toRadians(endLongitude - startLongitude);

    var a = pow(sin(dLat / 2), 2) +
        pow(sin(dLon / 2), 2) *
            cos(_toRadians(startLatitude)) *
            cos(_toRadians(endLatitude));
    var c = 2 * asin(sqrt(a));

    return earthRadius * c;
  }

  static double _toRadians(double degree) {
    return degree * pi / 180;
  }

  // --- Fase 0/1 do plano de background tracking
  // (docs/PLANO_BACKGROUND_IOS.md): contrato para tracking em background que
  // sobrevive a suspensão e a terminação pelo app. Todos os métodos abaixo
  // usam UnimplementedError como default para não quebrar plataformas que
  // ainda não implementam o recurso (ex.: Android, nesta fase). ---

  /// Starts producing [Position] updates in the background, persisted on the
  /// platform side so they survive the app being suspended or terminated by
  /// the system.
  ///
  /// Requires `LocationPermission.always` to have been granted; call
  /// [requestAlwaysPermission] first. Throws a
  /// [BackgroundPermissionDeniedException] if that permission is missing,
  /// and a [BackgroundModesNotConfiguredException] if the host app is
  /// missing the platform configuration required to run in the background.
  ///
  /// Positions are not delivered directly to Dart. Use
  /// [getBufferUpdateStream] to know when new positions are available, then
  /// [drainBufferedPositions] to read them and [acknowledgePositions] to
  /// remove them from the buffer once safely handed off.
  Future<void> startBackgroundTracking({
    required BackgroundTrackingSettings settings,
  }) {
    throw UnimplementedError(
      'startBackgroundTracking() has not been implemented.',
    );
  }

  /// Stops background tracking started by [startBackgroundTracking].
  ///
  /// Already buffered positions are left untouched; drain them with
  /// [drainBufferedPositions] if needed.
  Future<void> stopBackgroundTracking() {
    throw UnimplementedError(
      'stopBackgroundTracking() has not been implemented.',
    );
  }

  /// Returns whether background tracking is currently active.
  Future<bool> isBackgroundTrackingActive() {
    throw UnimplementedError(
      'isBackgroundTrackingActive() has not been implemented.',
    );
  }

  /// Returns the number of positions currently sitting in the buffer.
  Future<int> getBufferedPositionCount() {
    throw UnimplementedError(
      'getBufferedPositionCount() has not been implemented.',
    );
  }

  /// Reads up to [limit] buffered positions without removing them from the
  /// buffer.
  ///
  /// Positions are only removed once you call [acknowledgePositions] with
  /// their [BufferedPosition.id]s, so that a failure between reading and
  /// safely handing off the positions (e.g. the app being killed mid-upload)
  /// never loses data — at worst, the same batch is drained again.
  Future<List<BufferedPosition>> drainBufferedPositions({int limit = 500}) {
    throw UnimplementedError(
      'drainBufferedPositions() has not been implemented.',
    );
  }

  /// Removes the positions identified by [ids] (see
  /// [BufferedPosition.id]) from the buffer.
  Future<void> acknowledgePositions(List<int> ids) {
    throw UnimplementedError(
      'acknowledgePositions() has not been implemented.',
    );
  }

  /// Removes all positions currently sitting in the buffer.
  Future<void> clearBufferedPositions() {
    throw UnimplementedError(
      'clearBufferedPositions() has not been implemented.',
    );
  }

  /// Fires with the current buffered-position count whenever new positions
  /// are added to the buffer while the Flutter engine is alive.
  ///
  /// This is purely a UX convenience — background tracking does not depend
  /// on the engine being alive to keep buffering positions. Use
  /// [getBufferedPositionCount] to poll the count on demand.
  Stream<int> getBufferUpdateStream() {
    throw UnimplementedError(
      'getBufferUpdateStream() has not been implemented.',
    );
  }

  /// Requests `LocationPermission.always`, following whatever platform
  /// specific flow is required (e.g. the mandatory two-step "when in use"
  /// then "always" flow on iOS).
  Future<LocationPermission> requestAlwaysPermission() {
    throw UnimplementedError(
      'requestAlwaysPermission() has not been implemented.',
    );
  }

  /// Calculates the initial bearing between two points
  ///
  /// The initial bearing will most of the time be different than the end
  /// bearing, see https://www.movable-type.co.uk/scripts/latlong.html#bearing.
  /// The supplied coordinates [startLatitude], [startLongitude], [endLatitude]
  /// and [endLongitude] should be supplied in degrees.
  double bearingBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    var startLongitudeRadians = radians(startLongitude);
    var startLatitudeRadians = radians(startLatitude);
    var endLongitudeRadians = radians(endLongitude);
    var endLatitudeRadians = radians(endLatitude);

    var y = sin(endLongitudeRadians - startLongitudeRadians) *
        cos(endLatitudeRadians);
    var x = cos(startLatitudeRadians) * sin(endLatitudeRadians) -
        sin(startLatitudeRadians) *
            cos(endLatitudeRadians) *
            cos(endLongitudeRadians - startLongitudeRadians);

    return degrees(atan2(y, x));
  }
}
