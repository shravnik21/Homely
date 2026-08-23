-- ============================================================
-- HOMELY APP - Host-side notifications
-- Run this AFTER schema_notifications.sql, schema_reschedule_tracking.sql,
-- schema_cancellation_fee.sql, schema_reviews.sql, and
-- schema_message_notifications.sql
-- ============================================================
-- Mirrors the guest-facing notification system for the host side of
-- the very same `notifications` table - a host is just another
-- auth.users row, so no new table is needed. This adds:
--   - two NEW, independent trigger functions - notify_host_new_booking()
--     and notify_host_booking_status_change() - registered as
--     SEPARATE triggers on `bookings` alongside the existing
--     notify_booking_confirmed()/notify_booking_status_change() from
--     schema_notifications.sql. Deliberately NOT folded into those
--     two functions (an earlier version of this file did that via
--     `create or replace function`) so any customization already
--     made to the original guest-side functions is left completely
--     untouched - Postgres is fine running multiple AFTER triggers
--     for the same event on the same table, one per concern,
--   - a new trigger-driven type (new_review) fired on `reviews`
--     insert - already its own separate function/trigger, no change
--     needed there,
--   - a new lazily-generated type (checkin_pin_reminder) - see
--     HostNotificationsService.generateTimeBasedNotifications() -
--     for a host whose upcoming guest is checking into a smart-lock
--     listing and hasn't been sent the door code yet.
-- `new_message` (schema_message_notifications.sql) already works for
-- a host recipient with zero changes - that trigger was written
-- generically for either direction from day one.

-- 1. Extend the type check constraint - same drop/re-add pattern as
-- schema_checked_in.sql / schema_message_notifications.sql.
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
    'new_message',
    'host_new_booking',
    'host_booking_cancelled',
    'host_booking_rescheduled',
    'new_review',
    'checkin_pin_reminder'
  ));

-- 2. Extend the lazy-generation dedup index to cover
-- checkin_pin_reminder - one-shot, same shape as checkin_log_reminder
-- (milestone_days stays null).
drop index if exists public.notifications_lazy_unique_idx;
create unique index notifications_lazy_unique_idx
  on public.notifications (user_id, booking_id, type, milestone_days)
  where type in ('checkin_reminder', 'checkin_log_reminder', 'review_prompt', 'checkin_pin_reminder');


-- ------------------------------------------------------------
-- Trigger: new booking -> notify the host.
-- Runs as its OWN "after insert on bookings" trigger, alongside
-- (not instead of) trg_notify_booking_confirmed from
-- schema_notifications.sql, which still handles the guest-facing
-- 'booking_confirmed' notification exactly as before.
-- ------------------------------------------------------------
create or replace function public.notify_host_new_booking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_host_id uuid;
  v_guest_name text;
begin
  select title, host_id into v_title, v_host_id
  from public.places where id = new.place_id;

  if v_host_id is null then
    return new;
  end if;

  select full_name into v_guest_name from public.profiles where id = new.user_id;

  insert into public.notifications (user_id, type, title, body, booking_id, place_id)
  values (
    v_host_id,
    'host_new_booking',
    'New booking',
    coalesce(nullif(trim(v_guest_name), ''), 'A guest') || ' booked ' ||
      coalesce(v_title, 'your listing') || ' for ' ||
      to_char(new.check_in, 'DD Mon') || ' - ' || to_char(new.check_out, 'DD Mon') || '.',
    new.id,
    new.place_id
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_host_new_booking on public.bookings;
create trigger trg_notify_host_new_booking
  after insert on public.bookings
  for each row execute function public.notify_host_new_booking();


-- ------------------------------------------------------------
-- Trigger: booking cancelled/rescheduled -> notify the host.
-- Runs as its OWN "after update on bookings" trigger, alongside
-- (not instead of) trg_notify_booking_status_change from
-- schema_notifications.sql, which still handles the guest-facing
-- 'booking_cancelled'/'booking_rescheduled' notifications exactly as
-- before. Mirrors that function's OLD/NEW comparisons so both
-- triggers agree on what "just changed", but stays entirely
-- separate - editing one never risks the other.
-- ------------------------------------------------------------
create or replace function public.notify_host_booking_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_host_id uuid;
  v_guest_name text;
  v_refund_note text;
begin
  select title, host_id into v_title, v_host_id
  from public.places where id = new.place_id;

  if v_host_id is null then
    return new;
  end if;

  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    -- Same refund-note logic as notify_booking_status_change() - see
    -- that function in schema_notifications.sql for why these two
    -- columns are guaranteed to already be set on NEW here.
    if new.refund_amount is not null then
      v_refund_note := ' Refund: ' || rupee_amount(new.refund_amount) ||
        case
          when new.cancellation_fee is not null and new.cancellation_fee > 0
            then ' (cancellation fee ' || rupee_amount(new.cancellation_fee) || ' applied).'
          else '.'
        end;
    else
      v_refund_note := '';
    end if;

    select full_name into v_guest_name from public.profiles where id = new.user_id;

    insert into public.notifications (user_id, type, title, body, booking_id, place_id)
    values (
      v_host_id,
      'host_booking_cancelled',
      'Booking cancelled',
      coalesce(nullif(trim(v_guest_name), ''), 'A guest') || ' cancelled their stay at ' ||
        coalesce(v_title, 'your listing') || ' (' ||
        to_char(new.check_in, 'DD Mon') || ' - ' || to_char(new.check_out, 'DD Mon') || ').' ||
        v_refund_note,
      new.id,
      new.place_id
    );
  end if;

  if new.rescheduled_at is not null
     and new.rescheduled_at is distinct from old.rescheduled_at then
    select full_name into v_guest_name from public.profiles where id = new.user_id;

    insert into public.notifications (user_id, type, title, body, booking_id, place_id)
    values (
      v_host_id,
      'host_booking_rescheduled',
      'Booking rescheduled',
      coalesce(nullif(trim(v_guest_name), ''), 'A guest') || ' moved their stay at ' ||
        coalesce(v_title, 'your listing') || ' to ' ||
        to_char(new.check_in, 'DD Mon') || ' - ' || to_char(new.check_out, 'DD Mon') || '.',
      new.id,
      new.place_id
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_host_booking_status_change on public.bookings;
create trigger trg_notify_host_booking_status_change
  after update on public.bookings
  for each row execute function public.notify_host_booking_status_change();


-- ------------------------------------------------------------
-- Trigger: new review -> notify the host
-- ------------------------------------------------------------
create or replace function public.notify_new_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_host_id uuid;
begin
  select title, host_id into v_title, v_host_id
  from public.places where id = new.place_id;

  if v_host_id is null then
    return new;
  end if;

  insert into public.notifications (user_id, type, title, body, booking_id, place_id)
  values (
    v_host_id,
    'new_review',
    'New review',
    coalesce(nullif(trim(new.reviewer_name), ''), 'A guest') || ' left a ' ||
      new.rating::text || '-star review for ' || coalesce(v_title, 'your listing') || '.',
    new.booking_id,
    new.place_id
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_new_review on public.reviews;
create trigger trg_notify_new_review
  after insert on public.reviews
  for each row execute function public.notify_new_review();
