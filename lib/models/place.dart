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
  // checkinMethod is one of a fixed set of keys (see the option list
  // in ListingWizardScreen) with checkinDetails as the host's own
  // free-text description of exactly how it works for their place;
  // highlight1/2 are fully host-written on top of that - see
  // schema_place_highlights.sql / schema_place_checkin_method.sql. A
  // highlight only actually shows on PlaceDetailScreen once its title
  // (or, for check-in, checkinMethod) is set; the description is
  // optional even then.
  final String? checkinMethod;
  final String? checkinDetails;
  final String? highlight1Title;
  final String? highlight1Description;
  final String? highlight2Title;
  final String? highlight2Description;
  // Which of the three cancellation policies this listing uses - one
  // of 'flexible' | 'moderate' | 'strict' (see
  // schema_cancellation_policy_type.sql). 'moderate' is the DB
  // default, so every listing created before this feature behaves
  // exactly as it always did. The two flexible* fields are only ever
  // set when cancellationPolicyType == 'flexible' - the host's own
  // chosen free-cancellation cutoff (in days before check-in) and the
  // fee percentage that applies after it (see CancellationPolicy).
  final String cancellationPolicyType;
  final int? cancellationFlexibleFreeDays;
  final num? cancellationFlexibleFeePercent;

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
    this.checkinMethod,
    this.checkinDetails,
    this.highlight1Title,
    this.highlight1Description,
    this.highlight2Title,
    this.highlight2Description,
    this.cancellationPolicyType = 'moderate',
    this.cancellationFlexibleFreeDays,
    this.cancellationFlexibleFeePercent,
  });
  bool get isDraft => status == 'draft';
  bool get isPaused => status == 'paused';
  bool get isActive => status == 'published';

  /// Minimum photos required before a listing can be published -
  /// shared by the wizard's Review step and the shortcut "Publish
  /// Listing" action on ListingManageScreen, so both enforce the same
  /// bar.
  static const int kMinPhotosToPublish = 3;

  /// Everything still missing before this listing can go from draft
  /// to published, worded for direct display to the host (e.g.
  /// "Before publishing, please add: a title, at least 3 photos.").
  /// Empty list means it's ready. Mirrors every required field across
  /// every step of ListingWizardScreen - a title, city, address,
  /// description, nightly price, minimum photos, at least one
  /// amenity, and house rules - so a listing can never be published
  /// with a page left unfinished, whether that's checked from inside
  /// the wizard's Review step or from the listing's Manage screen
  /// directly.
  static List<String> missingRequirementsForPublish(Place place) {
    final missing = <String>[];
    if (place.title.trim().isEmpty || place.title == 'Untitled listing') {
      missing.add('a title');
    }
    if (place.cityId == null) missing.add('a city');
    if (place.address.trim().isEmpty) missing.add('an address');
    if (place.description.trim().isEmpty) missing.add('a description');
    if (place.pricePerNight <= 0) missing.add('a nightly price');
    if (place.photoUrls.length < kMinPhotosToPublish) {
      missing.add('at least $kMinPhotosToPublish photos');
    }
    if (place.amenities.isEmpty) missing.add('at least one amenity');
    if ((place.houseRules ?? '').trim().isEmpty) missing.add('house rules');
    if ((place.checkinMethod ?? '').trim().isEmpty) {
      missing.add('a check-in method');
    } else if (place.checkinMethod == 'other' &&
        (place.checkinDetails ?? '').trim().isEmpty) {
      // "Other" is a placeholder, not an actual method - a guest
      // reading "Other: (nothing written)" on the listing page would
      // learn nothing about how to actually get in, so it only
      // counts as answered once the host has described it themselves.
      missing.add('a description of your check-in method');
    }
    if (place.cancellationPolicyType == 'flexible' &&
        (place.cancellationFlexibleFreeDays == null ||
            place.cancellationFlexibleFeePercent == null)) {
      // A Flexible listing with no chosen cutoff/fee yet is an
      // unfinished policy, not a valid one - same idea as "Other"
      // check-in above, this only counts as answered once the host
      // has actually filled in their own numbers.
      missing.add('your custom cancellation policy details');
    }
    return missing;
  }

  bool get isReadyToPublish => missingRequirementsForPublish(this).isEmpty;


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
      checkinMethod: map['checkin_method'] as String?,
      checkinDetails: map['checkin_details'] as String?,
      highlight1Title: map['highlight1_title'] as String?,
      highlight1Description: map['highlight1_description'] as String?,
      highlight2Title: map['highlight2_title'] as String?,
      highlight2Description: map['highlight2_description'] as String?,
      cancellationPolicyType:
          map['cancellation_policy_type'] as String? ?? 'moderate',
      cancellationFlexibleFreeDays:
          map['cancellation_flexible_free_days'] as int?,
      cancellationFlexibleFeePercent:
          map['cancellation_flexible_fee_percent'] as num?,
    );
  }

  /// Whether PlaceDetailScreen's Highlights section has anything to
  /// show at all - lets that section hide itself completely rather
  /// than rendering an empty header for a listing the host hasn't
  /// added any highlights to.
  bool get hasHighlights =>
      (checkinMethod != null && checkinMethod!.trim().isNotEmpty) ||
      (highlight1Title != null && highlight1Title!.trim().isNotEmpty) ||
      (highlight2Title != null && highlight2Title!.trim().isNotEmpty);
}
