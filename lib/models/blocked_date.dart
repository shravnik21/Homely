/// One date a host has manually blocked off on one of their listings
/// (personal use, maintenance, an off-platform booking, etc) -
/// mirrors a row from `blocked_dates`, joined with the place's title
/// purely for display on the host calendar. See
/// schema_blocked_dates.sql.
class BlockedDate {
  final String placeId;
  final String placeTitle;
  final DateTime date;

  const BlockedDate({
    required this.placeId,
    required this.placeTitle,
    required this.date,
  });

  factory BlockedDate.fromMap(Map<String, dynamic> map) {
    final place = map['places'] as Map<String, dynamic>? ?? {};
    return BlockedDate(
      placeId: map['place_id'] as String,
      placeTitle: place['title'] as String? ?? 'Listing',
      date: DateTime.parse(map['date'] as String),
    );
  }
}
