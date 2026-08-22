import 'package:flutter/material.dart';
import 'package:homely_app/config/app_theme.dart';
import 'package:homely_app/models/chat_message.dart';
import 'package:homely_app/services/messages_service.dart';
import 'package:homely_app/utils/network_error_helper.dart';

/// Booking-scoped chat between a guest and the host of the listing
/// they booked - one conversation per booking (see
/// schema_messages.sql), opened from either side's booking-detail
/// screen via a "Message" action. The same screen serves both roles;
/// [otherPartyName] / [otherPartyIsHost] are the only role-specific
/// bits, purely for the app bar and empty-state copy.
class ChatScreen extends StatefulWidget {
  final String bookingId;
  final String otherPartyId;
  final String otherPartyName;
  final bool otherPartyIsHost;
  final String placeTitle;

  const ChatScreen({
    super.key,
    required this.bookingId,
    required this.otherPartyId,
    required this.otherPartyName,
    required this.otherPartyIsHost,
    required this.placeTitle,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final MessagesService _messagesService = MessagesService();
  final TextEditingController _inputController = TextEditingController();
  late final Stream<List<ChatMessage>> _messagesStream;
  bool _isSending = false;

  String? get _myId => _messagesService.currentUserId;

  @override
  void initState() {
    super.initState();
    _messagesStream = _messagesService.watchMessages(widget.bookingId);
    // Fire-and-forget - this conversation is now open, so anything
    // sent to me on it should flip to read. Not critical if it fails
    // (e.g. offline), so no error handling needed beyond swallowing.
    _messagesService.markRead(widget.bookingId).catchError((_) {});
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _inputController.text;
    if (text.trim().isEmpty || _isSending) return;
    setState(() => _isSending = true);
    _inputController.clear();
    try {
      await _messagesService.sendMessage(
        bookingId: widget.bookingId,
        recipientId: widget.otherPartyId,
        body: text,
      );
    } catch (e) {
      if (!mounted) return;
      // Put the text back so nothing typed is lost.
      _inputController.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e, fallback: 'Could not send that message.')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _fmtTime(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        foregroundColor: AppColors.dark,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.otherPartyName,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.dark),
            ),
            Text(
              widget.placeTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.grey),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildMessageList()),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    final myId = _myId;
    return StreamBuilder<List<ChatMessage>>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                friendlyError(snapshot.error!, fallback: 'Could not load messages.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.grey, fontSize: 13),
              ),
            ),
          );
        }

        final messages = snapshot.data ?? [];
        if (messages.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Say hello to ${widget.otherPartyName} about '
                '${widget.placeTitle} - questions about check-in, the '
                'space, anything at all.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.grey, fontSize: 13, height: 1.5),
              ),
            ),
          );
        }

        // Reversed list + reversed data = newest message pinned to
        // the bottom without any manual scroll-controller juggling.
        final reversed = messages.reversed.toList();
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          itemCount: reversed.length,
          itemBuilder: (context, index) {
            final message = reversed[index];
            final mine = myId != null && message.sentBy(myId);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MessageBubble(message: message, mine: mine, timeLabel: _fmtTime(message.createdAt)),
            );
          },
        );
      },
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: AppColors.lightGrey,
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Message...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isSending ? null : _send,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final String timeLabel;

  const _MessageBubble({required this.message, required this.mine, required this.timeLabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: mine ? AppColors.primary : AppColors.lightGrey,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(mine ? 16 : 4),
                    bottomRight: Radius.circular(mine ? 4 : 16),
                  ),
                ),
                child: Text(
                  message.body,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: mine ? Colors.white : AppColors.dark,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  timeLabel,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.grey),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
