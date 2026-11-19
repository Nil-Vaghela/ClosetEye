import 'package:geolocator/geolocator.dart';

/// Approximate location for weather. Never throws; returns null if unavailable
/// or the user said no. Cached for the app session.
class CoarseLocation {
  CoarseLocation._();
  static Position? _cached;
  static DateTime? _at;

  static Future<({double lat, double lon})?> get() async {
    try {
      if (_cached != null && DateTime.now().difference(_at!).inMinutes < 60) {
        return (lat: _cached!.latitude, lon: _cached!.longitude);
      }
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
          ).timeout(const Duration(seconds: 8));
      _cached = pos;
      _at = DateTime.now();
      return (lat: pos.latitude, lon: pos.longitude);
    } catch (_) {
      return null;
    }
  }
}
