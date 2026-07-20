import '../config/supabase_config.dart';
import '../models/place.dart';

/// Same service-layer pattern as AuthService/PlacesService/BookingService -
/// screens never talk to Supabase directly for wishlist reads/writes,
/// they call this instead.
class WishlistService {
  final _client = SupabaseConfig.client;

  /// Fetches the logged-in user's saved places, each joined with its
  /// images and city name - same nested-select technique as
  /// PlacesService.getPlaces(), so cards render with zero extra queries.
  Future<List<Place>> getWishlist() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final response = await _client
        .from('wishlists')
        .select(
            'place_id, created_at, places(*, cities(name), place_images(image_url, sort_order))')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => Place.fromMap(
            (row as Map<String, dynamic>)['places'] as Map<String, dynamic>))
        .toList();
  }

  /// Just the set of place ids the user has saved - cheap to fetch and
  /// enough for the Home/detail screens to know which hearts to fill
  /// in, without pulling every joined place record along with it.
  Future<Set<String>> getWishlistedPlaceIds() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {};

    final response = await _client
        .from('wishlists')
        .select('place_id')
        .eq('user_id', userId);

    return (response as List)
        .map((row) => row['place_id'] as String)
        .toSet();
  }

  /// Cheap existence check for a single place - used by the detail
  /// screen, which only needs to know about the one place it's
  /// showing rather than the whole saved-ids set.
  Future<bool> isWishlisted(String placeId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final response = await _client
        .from('wishlists')
        .select('id')
        .eq('user_id', userId)
        .eq('place_id', placeId)
        .maybeSingle();

    return response != null;
  }

  Future<void> addToWishlist(String placeId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('You must be logged in to save places.');
    }

    // upsert + ignoreDuplicates: if the row already exists (e.g. a
    // double-tap race) this is a harmless no-op instead of a unique
    // constraint error.
    await _client.from('wishlists').upsert(
      {'user_id': userId, 'place_id': placeId},
      onConflict: 'user_id,place_id',
      ignoreDuplicates: true,
    );
  }

  Future<void> removeFromWishlist(String placeId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client
        .from('wishlists')
        .delete()
        .eq('user_id', userId)
        .eq('place_id', placeId);
  }
}
