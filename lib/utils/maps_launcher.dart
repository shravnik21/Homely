import 'package:url_launcher/url_launcher.dart';

/// Opens the device's native Maps app for directions - Google Maps'
/// own universal directions URL works on both Android and iOS (it
/// opens the Google Maps app if installed, Apple Maps' equivalent
/// isn't needed since this URL falls back to a browser map either
/// way), and needs no API key since it's just a deep link, not an SDK
/// call.
class MapsLauncher {
  const MapsLauncher._();

  /// Directions to an exact [latitude]/[longitude] - used whenever a
  /// listing has a host-dropped pin (see Place.latitude/longitude).
  static Future<bool> openDirections({
    required double latitude,
    required double longitude,
  }) {
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '$latitude,$longitude',
    });
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Directions to a free-text address - fallback for older listings
  /// that were created before the map pin step existed and so have
  /// no latitude/longitude saved, only an address string.
  static Future<bool> openDirectionsToAddress(String address) {
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': address,
    });
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
