import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:homely_app/config/supabase_config.dart';
import 'package:homely_app/models/place.dart';

/// Everything the host "Add a Listing" wizard and listing management
/// screens need. Kept separate from PlacesService (which is the
/// guest-facing, read-only, published-only query surface) since this
/// is a completely different concern: a host's own write access to
/// their own rows, across every status (draft/published/paused).
class ListingService {
  final SupabaseClient _client = SupabaseConfig.client;

  String? get _hostId => _client.auth.currentUser?.id;

  static const int maxPhotos = 5;

  /// Every listing belonging to the current host, any status,
  /// newest-first - used by "Your Listings" and the listing switcher.
  Future<List<Place>> getMyListings() async {
    final hostId = _hostId;
    if (hostId == null) return [];
    final response = await _client
        .from('places')
        .select('*, cities(name), place_images(image_url, sort_order)')
        .eq('host_id', hostId)
        .order('created_at', ascending: false);
    return (response as List)
        .map((row) => Place.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<Place?> getListingById(String placeId) async {
    final response = await _client
        .from('places')
        .select('*, cities(name), place_images(image_url, sort_order)')
        .eq('id', placeId)
        .maybeSingle();
    if (response == null) return null;
    return Place.fromMap(response);
  }

  Future<List<Map<String, dynamic>>> getCities() async {
    final response =
        await _client.from('cities').select('id, name').order('name');
    return (response as List).cast<Map<String, dynamic>>();
  }

  /// Creates the listing's DB row right after the wizard's first step
  /// (property type), so every later step - including photo uploads,
  /// which need a real place_id - has something to attach to, and so
  /// "Save Draft" never has extra work to do: the row already exists.
  /// Placeholder values fill in the columns not collected yet; every
  /// later step overwrites them via updateListing().
  Future<String> createDraftListing({required String type}) async {
    final hostId = _hostId;
    if (hostId == null) throw Exception('Not logged in.');

    final response = await _client
        .from('places')
        .insert({
          'host_id': hostId,
          'type': type,
          'title': 'Untitled listing',
          'price_per_night': 0,
          'max_guests': 2,
          'bedrooms': 1,
          'bathrooms': 1,
          'status': 'draft',
        })
        .select('id')
        .single();
    return response['id'] as String;
  }

  /// Generic partial update - each wizard step calls this with just
  /// the fields it collected (e.g. {'city_id': ..., 'address': ...}).
  Future<void> updateListing(String placeId, Map<String, dynamic> fields) async {
    await _client.from('places').update(fields).eq('id', placeId);
  }

  Future<void> publishListing(String placeId) async {
    await _client
        .from('places')
        .update({'status': 'published'}).eq('id', placeId);
  }

  Future<void> pauseListing(String placeId) async {
    await _client.from('places').update({'status': 'paused'}).eq('id', placeId);
  }

  Future<void> unpauseListing(String placeId) async {
    await _client
        .from('places')
        .update({'status': 'published'}).eq('id', placeId);
  }

  /// Deletes the listing row - place_images cascade-delete with it
  /// (see schema_places.sql's `on delete cascade`), but the actual
  /// files in Storage don't, so those are removed first.
  Future<void> deleteListing(String placeId, List<String> storagePaths) async {
    if (storagePaths.isNotEmpty) {
      try {
        await _client.storage.from('listing-images').remove(storagePaths);
      } catch (_) {
        // Non-fatal - an orphaned file in Storage is cheap; failing
        // to delete the listing itself because of a Storage hiccup
        // would be much worse for the host.
      }
    }
    await _client.from('places').delete().eq('id', placeId);
  }

  // ---- Photos -----------------------------------------------------

  /// Uploads one photo under listing-images/{host_id}/{place_id}/...
  /// and returns its public URL (the bucket is public - see
  /// schema_host_listings.sql - so this URL works directly in
  /// CachedNetworkImage with no extra auth, same as the Unsplash URLs
  /// seed_places.sql uses).
  Future<String> uploadListingPhoto(String placeId, File file) async {
    final hostId = _hostId;
    if (hostId == null) throw Exception('Not logged in.');

    final ext = file.path.split('.').last;
    final fileName = '${DateTime.now().microsecondsSinceEpoch}.$ext';
    final path = '$hostId/$placeId/$fileName';

    await _client.storage.from('listing-images').upload(path, file);
    return _client.storage.from('listing-images').getPublicUrl(path);
  }

  /// Replaces every place_images row for this listing in one go,
  /// matching whatever order the host arranged photos in on the
  /// Photos step (index 0 = cover photo, via sort_order).
  Future<void> savePhotoOrder(String placeId, List<String> imageUrls) async {
    await _client.from('place_images').delete().eq('place_id', placeId);
    if (imageUrls.isEmpty) return;
    await _client.from('place_images').insert([
      for (var i = 0; i < imageUrls.length; i++)
        {'place_id': placeId, 'image_url': imageUrls[i], 'sort_order': i},
    ]);
  }

  /// Removes a single uploaded file from Storage (used when a host
  /// deletes a photo mid-wizard, before saving the final order).
  Future<void> deleteStorageFile(String publicUrl) async {
    try {
      final path = _pathFromPublicUrl(publicUrl);
      if (path != null) {
        await _client.storage.from('listing-images').remove([path]);
      }
    } catch (_) {
      // Non-fatal - see deleteListing() reasoning above.
    }
  }

  String? _pathFromPublicUrl(String url) {
    const marker = '/listing-images/';
    final index = url.indexOf(marker);
    if (index == -1) return null;
    return url.substring(index + marker.length);
  }
}
