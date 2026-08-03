import 'package:homely_app/config/supabase_config.dart';
import 'package:homely_app/models/place.dart';

/// Same pattern as PlacesService, but for the write-side / host-owned
/// half of `places`: creating drafts, editing, publishing, pausing
/// and deleting a host's own listings, plus managing their photos.
/// PlacesService stays guest-only (read, published listings only) so
/// the two responsibilities don't get tangled together.
class HostListingsService {
  final _client = SupabaseConfig.client;

  String get _hostId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw Exception('You must be logged in to manage listings.');
    }
    return id;
  }

  /// Every listing belonging to the current host, any status
  /// (draft/active/paused), newest first - this is what powers the
  /// "listing switcher" on My Listings / Host Home.
  Future<List<Place>> getMyListings() async {
    final response = await _client
        .from('places')
        .select('*, cities(name), place_images(image_url, sort_order)')
        .eq('host_id', _hostId)
        .order('created_at', ascending: false);
    return (response as List)
        .map((row) => Place.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<Place?> getListing(String id) async {
    final response = await _client
        .from('places')
        .select('*, cities(name), place_images(image_url, sort_order)')
        .eq('id', id)
        .eq('host_id', _hostId)
        .maybeSingle();
    return response == null ? null : Place.fromMap(response);
  }

  /// Every city a listing can currently be created in. For now this
  /// is deliberately restricted to the 5 cities Homely already
  /// operates in (Goa, Alibaug, Pune, Mumbai, Lonavala) - "any city
  /// in India" is a later expansion.
  Future<List<Map<String, String>>> getAvailableCities() async {
    final response =
        await _client.from('cities').select('id, name').order('name');
    return (response as List)
        .map((row) => {
              'id': row['id'] as String,
              'name': row['name'] as String,
            })
        .toList();
  }

  /// Creates a new listing row. Used both for "Save as Draft" (status
  /// left as 'draft') and for publishing directly from the review
  /// step (status: 'active'). Returns the new place's id so the
  /// wizard can keep editing/saving the same row afterwards instead
  /// of creating duplicates.
  Future<String> createListing({
    required String cityId,
    required String title,
    required String type,
    required num pricePerNight,
    required int maxGuests,
    required int bedrooms,
    required int bathrooms,
    required String address,
    required String description,
    required List<String> amenities,
    double? latitude,
    double? longitude,
    String status = 'draft',
  }) async {
    final response = await _client
        .from('places')
        .insert({
          'host_id': _hostId,
          'city_id': cityId,
          'title': title,
          'type': type,
          'price_per_night': pricePerNight,
          'max_guests': maxGuests,
          'bedrooms': bedrooms,
          'bathrooms': bathrooms,
          'address': address,
          'description': description,
          'amenities': amenities,
          'latitude': latitude,
          'longitude': longitude,
          'status': status,
        })
        .select('id')
        .single();
    return response['id'] as String;
  }

  /// Updates an existing listing's fields (any status). Also used to
  /// change status itself (draft -> active on publish, active <->
  /// paused from My Listings).
  Future<void> updateListing({
    required String id,
    String? cityId,
    String? title,
    String? type,
    num? pricePerNight,
    int? maxGuests,
    int? bedrooms,
    int? bathrooms,
    String? address,
    String? description,
    List<String>? amenities,
    double? latitude,
    double? longitude,
    String? status,
  }) async {
    await _client.from('places').update({
      if (cityId != null) 'city_id': cityId,
      if (title != null) 'title': title,
      if (type != null) 'type': type,
      if (pricePerNight != null) 'price_per_night': pricePerNight,
      if (maxGuests != null) 'max_guests': maxGuests,
      if (bedrooms != null) 'bedrooms': bedrooms,
      if (bathrooms != null) 'bathrooms': bathrooms,
      if (address != null) 'address': address,
      if (description != null) 'description': description,
      if (amenities != null) 'amenities': amenities,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (status != null) 'status': status,
    }).eq('id', id).eq('host_id', _hostId);
  }

  /// Replaces ALL photos for a listing in one go, in the order given
  /// (index 0 = cover photo). Simplest way to support add / remove /
  /// reorder / "set cover" from the wizard's photo step without
  /// juggling partial inserts and updates - the wizard always holds
  /// the full, current photo list locally, so this just makes the DB
  /// match it exactly.
  Future<void> setImages(String placeId, List<String> imageUrls) async {
    await _client.from('place_images').delete().eq('place_id', placeId);
    if (imageUrls.isEmpty) return;
    await _client.from('place_images').insert([
      for (var i = 0; i < imageUrls.length; i++)
        {'place_id': placeId, 'image_url': imageUrls[i], 'sort_order': i},
    ]);
  }

  Future<void> publishListing(String id) =>
      updateListing(id: id, status: 'active');

  Future<void> pauseListing(String id) =>
      updateListing(id: id, status: 'paused');

  Future<void> unpauseListing(String id) =>
      updateListing(id: id, status: 'active');

  /// Deletes a listing entirely (its photos cascade-delete via the
  /// place_images -> places foreign key). Pausing, not deleting, is
  /// the usual way to temporarily hide a listing - this is for when a
  /// host really doesn't want it back.
  Future<void> deleteListing(String id) async {
    await _client.from('places').delete().eq('id', id).eq('host_id', _hostId);
  }
}
