/// Represents one row from `places`, joined with its `place_images`.
/// This mirrors exactly what PlacesService.getPlaces() returns from Supabase.
class Place {
  final String id;
  final String? cityId;
  final String cityName;
  final String title;
  final String type; // villa | apartment | cottage | cabin | bungalow | holiday home | beach house | farmhouse | penthouse | homestay
  final num pricePerNight;
  final int maxGuests;
  final int bedrooms;
  final int bathrooms;
  final String address;
  final String description;
  final List<String> amenities;
  final List<String> photoUrls;
  // Null for the platform's own seeded places (no owning host).
  // Set for anything created via the host "Add a Listing" wizard.
  final String? hostId;
  final String? hostName;
  // 'draft' | 'published' | 'paused'. Seeded places default to
  // 'published' (see schema_host_listings.sql).
  final String status;
  final String? houseRules;
  final double? latitude;
  final double? longitude;

  Place({
    required this.id,
    this.cityId,
    required this.cityName,
    required this.title,
    required this.type,
    required this.pricePerNight,
    required this.maxGuests,
    required this.bedrooms,
    required this.bathrooms,
    required this.address,
    required this.description,
    required this.amenities,
    required this.photoUrls,
    this.hostId,
    this.hostName,
    this.status = 'published',
    this.houseRules,
    this.latitude,
    this.longitude,
  });
  bool get isDraft => status == 'draft';
  bool get isPaused => status == 'paused';
  bool get isActive => status == 'published';


  /// The first photo, used as the card thumbnail. Falls back to a
  /// placeholder if a place somehow has no images yet.
  String get coverImage => photoUrls.isNotEmpty
      ? photoUrls.first
      : 'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2';

  /// Seeded demo places have no owning host (hostId/hostName are
  /// null) - shown as "Anonymous Host" rather than leaving a blank
  /// or crashing on a null name.
  String get hostDisplayName {
    if (hostName == null || hostName!.trim().isEmpty) return 'Anonymous Host';
    return hostName!.trim();
  }

  /// Builds a Place from the raw JSON map Supabase returns.
  /// Supabase's nested select (`places(*, place_images(*))`) returns
  /// place_images as a List<dynamic> under the key 'place_images',
  /// and the related city as a Map under 'cities' (because of the
  /// foreign key join we wrote in the query).
  factory Place.fromMap(Map<String, dynamic> map) {
    final imagesRaw = (map['place_images'] as List<dynamic>? ?? []);
    // sort by sort_order so photo 1 is always first, regardless of
    // what order Postgres happens to return rows in
    imagesRaw.sort((a, b) =>
        (a['sort_order'] as int? ?? 0).compareTo(b['sort_order'] as int? ?? 0));

    return Place(
      id: map['id'] as String,
      cityId: map['city_id'] as String?,
      cityName: (map['cities']?['name'] as String?) ?? '',
      title: map['title'] as String? ?? 'Untitled place',
      type: map['type'] as String? ?? 'villa',
      pricePerNight: map['price_per_night'] as num? ?? 0,
      maxGuests: map['max_guests'] as int? ?? 1,
      bedrooms: map['bedrooms'] as int? ?? 1,
      bathrooms: map['bathrooms'] as int? ?? 1,
      address: map['address'] as String? ?? '',
      description: map['description'] as String? ?? '',
      amenities: (map['amenities'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      photoUrls:
          imagesRaw.map((img) => img['image_url'] as String).toList(),
      hostId: map['host_id'] as String?,
      hostName: (map['host_public_info']?['full_name'] as String?),
      status: map['status'] as String? ?? 'published',
      houseRules: map['house_rules'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }
}
