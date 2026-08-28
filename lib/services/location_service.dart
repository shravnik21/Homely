import 'dart:convert';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// One free-text search result: a human-readable place name plus the
/// coordinates it resolves to.
class PlaceSearchResult {
  final String displayName;
  final LatLng location;
  const PlaceSearchResult({required this.displayName, required this.location});
}

/// Wraps the location-related things the host wizard's map step
/// needs, all of which can fail in ordinary, non-buggy ways (no
/// signal, permission denied, city not found, no matches) - callers
/// should treat an empty/null result as "couldn't resolve this", not
/// as an error to surface loudly.
class LocationService {
  const LocationService();

  /// Best-effort lat/lng for a typed city/place name, using the
  /// device's own geocoder (Apple's on iOS, Google's on Android) -
  /// this is what centers the wizard's map somewhere sensible before
  /// the host drags the pin to the exact spot themselves. Returns
  /// null on no match rather than throwing, since "couldn't guess
  /// where that is yet" is routine while a host is still typing.
  Future<LatLng?> geocodeCity(String cityName) async {
    final trimmed = cityName.trim();
    if (trimmed.isEmpty) return null;
    try {
      final results = await geocoding.locationFromAddress('$trimmed, India');
      if (results.isEmpty) return null;
      return LatLng(results.first.latitude, results.first.longitude);
    } catch (_) {
      // No match, or the platform geocoder is unavailable (e.g. no
      // Google Play Services on some Android emulators) - either way
      // the map just falls back to its current camera position.
      return null;
    }
  }

  /// The device's current position, requesting permission first if
  /// needed. Returns null (rather than throwing) if location
  /// services are off, permission is denied, or the device can't get
  /// a fix in time - the "Use my current location" button should
  /// just silently no-op in that case, since the host can always drop
  /// the pin manually instead.
  Future<LatLng?> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Free-text place search for the wizard's map search box - lets a
  /// host type any place name ("Baga Beach", "Connaught Place, Delhi"
  /// ...) and get a short list of matching locations to jump to,
  /// rather than only being able to search the city/street they've
  /// already typed into the address fields.
  ///
  /// Uses OpenStreetMap's Nominatim search API - free, no API key,
  /// consistent with the rest of the map (see TileLayer in
  /// listing_wizard_screen.dart). Nominatim's usage policy requires a
  /// descriptive User-Agent identifying the app, and asks callers not
  /// to fire requests on every keystroke - the wizard debounces calls
  /// to this before sending them.
  ///
  /// Returns an empty list on no matches, no connection, or any other
  /// failure - the search box should just show "no results" rather
  /// than an error for something this routine.
  Future<List<PlaceSearchResult>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': trimmed,
        'format': 'json',
        'limit': '6',
        'countrycodes': 'in',
      });
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'homely_app (Flutter; Supabase-backed)'},
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];

      final results = jsonDecode(response.body) as List;
      return results.map((r) {
        final map = r as Map<String, dynamic>;
        return PlaceSearchResult(
          displayName: map['display_name'] as String,
          location: LatLng(
            double.parse(map['lat'] as String),
            double.parse(map['lon'] as String),
          ),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
