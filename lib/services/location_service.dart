import 'package:geolocator/geolocator.dart';

/// Result of asking for the device position.
sealed class LocationResult {
  const LocationResult();
}

class LocationFix extends LocationResult {
  const LocationFix(this.lat, this.lng, this.accuracy, {this.heading});
  final double lat;
  final double lng;

  /// Metres.
  final double accuracy;

  /// Direction of travel in degrees from north, when the device knows it.
  final double? heading;
}

class LocationFailure extends LocationResult {
  const LocationFailure(this.message);
  final String message;
}

typedef LocationProvider = Future<LocationResult> Function();

/// How long to wait for a position once permission is granted.
const locationTimeout = Duration(seconds: 6);

/// One-shot position via geolocator (web + mobile); never throws.
Future<LocationResult> currentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationFailure(
        'Location services are turned off. Pick a start point instead.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      return const LocationFailure(
        'Location permission was not granted. Pick a start point instead.',
      );
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: locationTimeout,
      ),
    );
    return LocationFix(pos.latitude, pos.longitude, pos.accuracy);
  } catch (_) {
    return const LocationFailure(
      'Could not get your location. Pick a start point instead.',
    );
  }
}

typedef LocationPermissionCheck = Future<bool> Function();

/// Whether location permission is already granted, without asking.
Future<bool> hasLocationPermission() async {
  try {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  } catch (_) {
    return false;
  }
}

typedef LocationStreamProvider = Stream<LocationFix> Function();

/// Live positions via geolocator (web + mobile). Call only after
/// [currentLocation] returned a fix, so permission is already granted.
/// Errors end nothing: they are dropped and the stream keeps going.
Stream<LocationFix> locationStream() {
  try {
    return Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 3,
          ),
        )
        .map(
          (p) => LocationFix(
            p.latitude,
            p.longitude,
            p.accuracy,
            heading:
                p.heading.isFinite &&
                    p.heading >= 0 &&
                    p.speed.isFinite &&
                    p.speed > 0.4
                ? p.heading
                : null,
          ),
        )
        .handleError((Object _) {});
  } catch (_) {
    return const Stream.empty();
  }
}
