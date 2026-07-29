import 'package:homely_app/config/supabase_config.dart';
import 'package:homely_app/models/place.dart';

/// Same pattern as AuthService: this is the ONLY file that runs
/// database queries for places. Screens call these methods and get
/// back typed Place objects - they never touch Supabase directly.
class PlacesService {
  final _client = SupabaseConfig.client;

  /// Fetches every place, each with its images and city name attached
  /// in a SINGLE network round trip.
  ///
  /// The select string below is Supabase's "nested select" syntax:
  ///   '*, cities(name), place_images(image_url, sort_order)'
  /// Because `places.city_id` has a foreign key to `cities.id`, and
  /// `place_images.place_id` has a foreign key to `places.id`,
  /// Supabase (via PostgREST) can auto-join and nest the related rows
  /// into the JSON response for us - no manual JOIN or second query.
  Future<List<Place>> getPlaces({String? city, String? type}) async {
    var query = _client
        .from('places')
        .select(
            '*, cities(name), place_images(image_url, sort_order), host_public_info(full_name)')
        // Belt-and-suspenders alongside the RLS policy in
        // schema_host_listings.sql - guests should never see a host's
        // draft or paused listings, even if a future service-role
        // query bypasses RLS.
        .eq('status', 'published');

    if (city != null && city.isNotEmpty) {
      // filters on a nested/related table's column
      query = query.eq('cities.name', city);
    }
    if (type != null && type.isNotEmpty) {
      query = query.eq('type', type);
    }

    // TWO-LEVEL sort, both deterministic:
    // 1. cities.display_order - keeps every place grouped under its
    //    city, in the fixed city sequence (Goa, Alibaug, Lonavala,
    //    Mumbai, Pune, ...) regardless of table storage order.
    // 2. created_at, then id - orders places WITHIN a city by when
    //    they were added, so a newly created listing always joins
    //    the end of its own city's group instead of appearing
    //    anywhere else. `id` is a final tiebreaker for any rows that
    //    share an identical created_at (e.g. the original seed data,
    //    all inserted in one script) - guarantees a stable order
    //    even then, immune to future UPDATEs reshuffling ties.
    final response = await query
        .order('display_order', ascending: true, referencedTable: 'cities')
        .order('created_at', ascending: true)
        .order('id', ascending: true);
    return (response as List)
        .map((row) => Place.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Distinct list of city names, used to populate the city
  /// chips/tabs on the Home screen.
  Future<List<String>> getCities() async {
    final response = await _client.from('cities').select('name').order('name');
    return (response as List).map((row) => row['name'] as String).toList();
  }
}
