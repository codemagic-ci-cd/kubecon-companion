import 'package:geolocator/geolocator.dart';

/// Result of asking for the device position.
sealed class LocationResult {
  const LocationResult();
}

class LocationFix extends LocationResult {
  const LocationFix(this.lat, this.lng, this.accuracy);
  final double lat;
  final double lng;

  /// Metres.
  final double accuracy;
}

class LocationFailure extends LocationResult {
  const LocationFailure(this.message);
  final String message;
}

typedef LocationProvider = Future<LocationResult> Function();

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
        timeLimit: Duration(seconds: 15),
      ),
    );
    return LocationFix(pos.latitude, pos.longitude, pos.accuracy);
  } catch (_) {
    return const LocationFailure(
      'Could not get your location. Pick a start point instead.',
    );
  }
}
