-- ============================================================
-- HOMELY APP - Guest notifications
-- Run this AFTER schema_reschedule_tracking.sql and
-- schema_cancellation_fee.sql
-- ============================================================
-- Trip/booking updates for the guest: confirmations, cancellations
-- (with the refund/fee that was actually applied), reschedules (all
-- trigger-driven - fired the instant the underlying booking row
-- changes, so they're never stale or missed), plus time-based nudges
-- (a "days to go" check-in countdown at a few checkpoints, a
-- post-stay review prompt, and generic "suggestion" messages) that
-- NotificationsService generates lazily from the client whenever the
-- guest opens the Notifications screen, since this project has no
-- server-side cron job to run those on a schedule. Idempotency for
-- THOSE is enforced by the partial unique index below, so opening the
-- screen twice in a row never creates duplicates.

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in (
    'booking_confirmed',
    'booking_cancelled',
    'booking_rescheduled',
    'checkin_reminder',
    'review_prompt',
    'suggestion'
  )),
  title text not null,
  body text not null,
  -- Nullable: a generic 'suggestion' notification isn't tied to any
  -- one booking/place.
  booking_id uuid references public.bookings(id) on delete cascade,
  place_id uuid references public.places(id) on delete set null,
  -- Which "days-to-go" checkpoint a checkin_reminder was generated
  -- at (3, 1, or 0) - lets a single booking get more than one
  -- reminder as the trip approaches (a 3-days-out nudge AND a
  -- day-of one) while still never generating the SAME checkpoint
  -- twice. Always null for every other notification type.
  milestone_days int,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

-- Only applies to the lazily-generated types - booking_confirmed/
-- cancelled/rescheduled are trigger-only and a booking CAN legitimately
-- be rescheduled more than once, so those should be free to produce a
-- fresh notification every time rather than being deduplicated.
-- milestone_days is part of the key so a checkin_reminder can fire
-- again at each new checkpoint (3 days out, 1 day out, day-of)
-- without ever repeating the SAME checkpoint - see
-- NotificationsService.generateTimeBasedNotifications.
create unique index if not exists notifications_lazy_unique_idx
  on public.notifications (user_id, booking_id, type, milestone_days)
  where type in ('checkin_reminder', 'review_prompt');

alter table public.notifications enable row level security;

-- Small formatting helper so the trigger functions below don't repeat
-- this logic - deliberately NOT comma-grouped (unlike formatInr() on
-- the Dart side, which uses Indian lakh-style grouping) since matching
-- that exactly in SQL isn't worth the complexity for a notification
-- sentence; the guest sees the fully-formatted amount on the actual
-- booking detail screen regardless.
create or replace function public.rupee_amount(amount numeric)
returns text
language sql
immutable
as $$
  select '₹' || trim(to_char(round(amount), 'FM999999999'));
$$;

create policy "Users can view their own notifications"
  on public.notifications for select
  using (auth.uid() = user_id);

-- Lets NotificationsService's lazy generation (checkin_reminder,
-- review_prompt, suggestion) insert as the logged-in guest. The
-- trigger-driven types below insert via `security definer` functions
-- instead, which bypass RLS entirely - this policy is only exercised
-- by the client-side inserts.
create policy "Users can insert their own notifications"
  on public.notifications for insert
  with check (auth.uid() = user_id);

-- Marking as read is the only update a guest ever needs to make.
create policy "Users can update their own notifications"
  on public.notifications for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- ------------------------------------------------------------
-- Trigger: new booking -> "booking confirmed" notification
-- ------------------------------------------------------------
-- security definer because a guest's own RLS on `notifications` would
-- still technically allow this (auth.uid() = user_id holds), but
-- using the same definer pattern as get_booked_ranges/get_blocked_dates
-- keeps all trigger-side writes consistent and immune to any future
-- RLS tightening on this table.
create or replace function public.notify_booking_confirmed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
begin
  select title into v_title from public.places where id = new.place_id;

  insert into public.notifications (user_id, type, title, body, booking_id, place_id)
  values (
    new.user_id,
    'booking_confirmed',
    'Booking confirmed',
    'Your stay at ' || coalesce(v_title, 'your listing') || ' is confirmed for ' ||
      to_char(new.check_in, 'DD Mon') || ' - ' || to_char(new.check_out, 'DD Mon') || '.',
    new.id,
    new.place_id
  );
  return new;
end;
$$;

create trigger trg_notify_booking_confirmed
  after insert on public.bookings
  for each row execute function public.notify_booking_confirmed();


-- ------------------------------------------------------------
-- Trigger: booking cancelled / rescheduled -> matching notification
-- ------------------------------------------------------------
create or replace function public.notify_booking_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_refund_note text;
begin
  select title into v_title from public.places where id = new.place_id;

  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    -- cancelBooking() (booking_service.dart) always sets
    -- cancellation_fee/refund_amount in the SAME update that sets
    -- status='cancelled', so both are already on NEW by the time this
    -- fires. Guarded with IS NOT NULL anyway in case a booking is
    -- ever cancelled through some other path that skips them.
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

    insert into public.notifications (user_id, type, title, body, booking_id, place_id)
    values (
      new.user_id,
      'booking_cancelled',
      'Booking cancelled',
      'Your booking at ' || coalesce(v_title, 'your listing') || ' has been cancelled.' || v_refund_note,
      new.id,
      new.place_id
    );
  end if;

  if new.rescheduled_at is not null
     and new.rescheduled_at is distinct from old.rescheduled_at then
    insert into public.notifications (user_id, type, title, body, booking_id, place_id)
    values (
      new.user_id,
      'booking_rescheduled',
      'Booking rescheduled',
      'Your stay at ' || coalesce(v_title, 'your listing') || ' moved to ' ||
        to_char(new.check_in, 'DD Mon') || ' - ' || to_char(new.check_out, 'DD Mon') || '.',
      new.id,
      new.place_id
    );
  end if;

  return new;
end;
$$;

create trigger trg_notify_booking_status_change
  after update on public.bookings
  for each row execute function public.notify_booking_status_change();
