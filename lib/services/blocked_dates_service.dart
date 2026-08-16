import 'package:homely_app/config/supabase_config.dart';
import 'package:homely_app/models/blocked_date.dart';

/// Read/write access to `blocked_dates` for the current host. Mirrors
/// HostBookingsService's pattern (screens never touch Supabase
/// directly) - unlike that one, this table's RLS already scopes rows
/// to "places I own" directly (see schema_blocked_dates.sql), so
/// reads/writes go straight through `.from('blocked_dates')` with no
/// need for a security-definer function on the host side. The
/// security-definer `get_blocked_dates` function in that same schema
/// file is only for the GUEST-facing read, used by
/// AvailabilityService instead.
class BlockedDatesService {
  final _client = SupabaseConfig.client;

  /// Every date currently blocked across ALL of the host's listings,
  /// each with its listing's title attached - powers the host
  /// calendar screen.
  Future<List<BlockedDate>> getBlockedDatesForMyListings() async {
    final hostId = _client.auth.currentUser?.id;
    if (hostId == null) return [];

    final response = await _client
        .from('blocked_dates')
        .select('place_id, date, places!inner(title, host_id)')
        .eq('places.host_id', hostId);

    return (response as List)
        .cast<Map<String, dynamic>>()
        .map((row) => BlockedDate.fromMap(row))
        .toList();
  }

  /// Blocks [date] on [placeId], preventing guests from booking or
  /// rescheduling into it (AvailabilityService folds blocked dates in
  /// alongside booked ones). `upsert` rather than `insert` so
  /// tapping an already-blocked date twice in a row (e.g. a fast
  /// double-tap) doesn't throw on the table's unique constraint.
  Future<void> blockDate({required String placeId, required DateTime date}) async {
    await _client.from('blocked_dates').upsert(
      {'place_id': placeId, 'date': _isoDate(date)},
      onConflict: 'place_id,date',
    );
  }

  /// Un-blocks [date] on [placeId], making it bookable again. A
  /// no-op (not an error) if it wasn't blocked in the first place.
  Future<void> unblockDate({required String placeId, required DateTime date}) async {
    await _client
        .from('blocked_dates')
        .delete()
        .eq('place_id', placeId)
        .eq('date', _isoDate(date));
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
