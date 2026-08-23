-- ============================================================
-- HOMELY APP - "New message" notification
-- Run this AFTER schema_notifications.sql and schema_messages.sql
-- ============================================================
-- Fires a notification the instant a message is inserted, same
-- trigger-driven approach as booking_confirmed/cancelled/rescheduled
-- in schema_notifications.sql, so it's never stale or missed and
-- doesn't rely on either side having the chat open.
--
-- messages.sender_id/recipient_id can be either the guest or the
-- host (chat is two-way), so this trigger - and the notification row
-- it inserts - is written generically for either direction. Today
-- only NotificationsScreen (guest-facing) actually reads from
-- `notifications`, so in practice this only surfaces when the
-- recipient is the guest; a host-side notification inbox can read
-- the exact same rows later with no further changes needed here.

-- 1. Extend the type check constraint - same drop/re-add pattern as
-- schema_checked_in.sql.
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'booking_confirmed',
    'booking_cancelled',
    'booking_rescheduled',
    'checkin_reminder',
    'checkin_log_reminder',
    'review_prompt',
    'suggestion',
    'new_message'
  ));

-- 2. Trigger function - looks up the sender's display name (guest ->
-- profiles, host -> host_public_info; whichever matches) and the
-- listing's title, then writes one notification to the recipient.
create or replace function public.notify_new_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_place_id uuid;
  v_place_title text;
  v_sender_name text;
  v_preview text;
begin
  select place_id into v_place_id from public.bookings where id = new.booking_id;
  select title into v_place_title from public.places where id = v_place_id;

  select coalesce(
    (select full_name from public.profiles where id = new.sender_id),
    (select full_name from public.host_public_info where id = new.sender_id)
  ) into v_sender_name;

  v_preview := case
    when length(new.body) > 120 then left(new.body, 117) || '...'
    else new.body
  end;

  insert into public.notifications (user_id, type, title, body, booking_id, place_id)
  values (
    new.recipient_id,
    'new_message',
    'New message from ' || coalesce(nullif(trim(v_sender_name), ''), 'someone') ||
      coalesce(' · ' || v_place_title, ''),
    v_preview,
    new.booking_id,
    v_place_id
  );
  return new;
end;
$$;

create trigger trg_notify_new_message
  after insert on public.messages
  for each row execute function public.notify_new_message();
