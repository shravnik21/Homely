/// One row from `messages` - a single message in the booking-scoped
/// conversation between a guest and the host of the listing they
/// booked. See schema_messages.sql.
class ChatMessage {
  final String id;
  final String bookingId;
  final String senderId;
  final String recipientId;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  const ChatMessage({
    required this.id,
    required this.bookingId,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  bool sentBy(String userId) => senderId == userId;

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      bookingId: map['booking_id'] as String,
      senderId: map['sender_id'] as String,
      recipientId: map['recipient_id'] as String,
      body: map['body'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      readAt: map['read_at'] != null
          ? DateTime.parse(map['read_at'] as String).toLocal()
          : null,
    );
  }
}
