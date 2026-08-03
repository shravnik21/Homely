/// Property types a host can pick from - matches the DB check
/// constraint on places.type exactly (see schema_places.sql).
const kPropertyTypes = [
  'villa',
  'apartment',
  'cottage',
  'cabin',
  'bungalow',
  'holiday home',
  'beach house',
  'farmhouse',
  'penthouse',
  'homestay',
];

/// Amenities a host can toggle on - matches the icon lookup in
/// PlaceDetailScreen so anything selected here renders with the
/// right icon on the guest-facing listing.
const kAvailableAmenities = [
  'WiFi',
  'TV',
  'AC',
  'Kitchen',
  'Parking',
  'Pool',
  'Bonfire',
  'Lawn',
  'Power Backup',
  'Pet-Friendly',
  'Fireplace',
  'BBQ',
  'Bathtub',
];

/// Approximate center coordinates for the 5 cities Homely currently
/// operates in. Used by the wizard's "drop a pin" step to translate a
/// tap on the mock map into a believable lat/lng near that city.
const kCityCenters = {
  'Goa': (lat: 15.2993, lng: 74.1240),
  'Alibaug': (lat: 18.6414, lng: 72.8722),
  'Pune': (lat: 18.5204, lng: 73.8567),
  'Mumbai': (lat: 19.0760, lng: 72.8777),
  'Lonavala': (lat: 18.7546, lng: 73.4062),
};

/// A small curated bank of stock property photos a host can pick
/// from for their listing (up to 5). Standing in for a real
/// camera-roll / file upload until that's wired up to Supabase
/// Storage - swap `_HostPhotoPickerSheet` in listing_wizard_screen.dart
/// for a real picker (e.g. image_picker + Storage) when ready.
const kStockPhotoLibrary = [
  'https://images.unsplash.com/photo-1526308182272-d2fe5e5947d8?w=900&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxjb2xsZWN0aW9uLXBhZ2V8MXxaTnZjcjdDb0tyZ3x8ZW58MHx8fHx8',
  'https://images.unsplash.com/photo-1642798335847-f9906cb48cc2?w=900&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxjb2xsZWN0aW9uLXBhZ2V8NHxHaVVCSVVfUTBpb3x8ZW58MHx8fHx8',
  'https://images.unsplash.com/photo-1767348922680-2774f58e293c?w=900&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxjb2xsZWN0aW9uLXBhZ2V8M3xaNkxxMDFXUUlMZ3x8ZW58MHx8fHx8',
  'https://plus.unsplash.com/premium_photo-1663126831394-25b3e9c9e059?w=1600&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxjb2xsZWN0aW9uLXBhZ2V8Mnx0SUx6bURPZDZ4b3x8ZW58MHx8fHx8',
  'https://plus.unsplash.com/premium_photo-1675616575218-6457c9eb95be?w=900&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxjb2xsZWN0aW9uLXBhZ2V8NXwwMWg3ZVA5WmVRa3x8ZW58MHx8fHx8',
  'https://plus.unsplash.com/premium_photo-1678790909042-daaceb35933d?w=900&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxjb2xsZWN0aW9uLXBhZ2V8NHx1Z19Ic0hwN2NfQXx8ZW58MHx8fHx8',
  'https://plus.unsplash.com/premium_photo-1682377521715-95d16dc51943?w=900&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxjb2xsZWN0aW9uLXBhZ2V8NXxEc0ptUFZacV9UQXx8ZW58MHx8fHx8',
  'https://plus.unsplash.com/premium_photo-1685218029037-8ed21a0c7b7c?w=900&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxjb2xsZWN0aW9uLXBhZ2V8NXxfb1BtMldXZmtBUXx8ZW58MHx8fHx8',
  'https://plus.unsplash.com/premium_photo-1686090450346-f418fff5486e?w=900&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxjb2xsZWN0aW9uLXBhZ2V8NXxIc0hnU3ZRU05lTXx8ZW58MHx8fHx8',
  'https://plus.unsplash.com/premium_photo-1686782502531-feb0e6a56eb5?w=900&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxjb2xsZWN0aW9uLXBhZ2V8NXxLZlhzNlZtX2J5SXx8ZW58MHx8fHx8',
  'https://plus.unsplash.com/premium_photo-1687960116880-086e6fb4b404?q=80&w=1740&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
  'https://plus.unsplash.com/premium_photo-1724659217618-b39cd5a30ac9?q=80&w=1470&auto=format&fit=crop&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D',
  'https://plus.unsplash.com/premium_photo-1733514433306-7a63586e8381?w=900&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxjb2xsZWN0aW9uLXBhZ2V8MXxqU0FnMlRIRTdPRXx8ZW58MHx8fHx8',
  'https://plus.unsplash.com/premium_photo-1744390859826-d5813f87d17a?w=900&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxjb2xsZWN0aW9uLXBhZ2V8M3xuRWx6dXZRdldRc3x8ZW58MHx8fHx8',
];
