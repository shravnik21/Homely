import 'package:homely_app/config/supabase_config.dart';
import 'package:homely_app/models/chat_message.dart';

/// Same service-layer pattern as BookingService/NotificationsService -
/// screens never talk to Supabase directly. Backs the booking-scoped
/// chat between a guest and the host of the listing they booked (see
/// schema_messages.sql) - one conversation per booking, so there's
/// never any ambiguity about which trip a message is about.
class MessagesService {
  final _client = SupabaseConfig.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  /// Live view of every message on [bookingId], oldest first -
  /// Supabase Realtime pushes new rows the instant either side sends
  /// one, so ChatScreen never has to poll.
  Stream<List<ChatMessage>> watchMessages(String bookingId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('booking_id', bookingId)
        .order('created_at')
        .map((rows) => rows.map(ChatMessage.fromMap).toList());
  }

  Future<void> sendMessage({
    required String bookingId,
    required String recipientId,
    required String body,
  }) async {
    final senderId = currentUserId;
    if (senderId == null) throw Exception('Not logged in.');
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    await _client.from('messages').insert({
      'booking_id': bookingId,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'body': trimmed,
    });
  }

  /// Marks every unread message on [bookingId] sent TO the current
  /// user as read - called when ChatScreen opens, so the other side's
  /// "seen" state (and any future unread badge) reflects reality as
  /// soon as the conversation is actually viewed.
  Future<void> markRead(String bookingId) async {
    final userId = currentUserId;
    if (userId == null) return;
    await _client
        .from('messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('booking_id', bookingId)
        .eq('recipient_id', userId)
        .isFilter('read_at', null);
  }

  /// Unread count across every booking where the current user is a
  /// participant - not wired into any badge yet, but kept here so
  /// both the host and guest sides share one definition of "unread"
  /// whenever that lands.
  Future<int> getUnreadCount() async {
    final userId = currentUserId;
    if (userId == null) return 0;
    final response = await _client
        .from('messages')
        .select('id')
        .eq('recipient_id', userId)
        .isFilter('read_at', null);
    return (response as List).length;
  }
}
