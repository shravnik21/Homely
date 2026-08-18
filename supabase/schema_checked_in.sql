-- ============================================================
-- HOMELY APP - Guest check-in confirmation
-- Run this AFTER schema_bookings.sql and schema_notifications.sql
-- ============================================================
-- Lets a guest log "I've arrived" once their stay is live, and lets
-- the host see that on their side. Mirrors schema_reschedule_tracking.sql's
-- approach: a single nullable timestamp column, set once by
-- BookingService.confirmCheckIn(), never unset.
--
-- No new RLS policy is needed - the existing "Users can cancel their
-- own bookings" UPDATE policy on `bookings` (schema_bookings.sql)
-- already covers every column a guest is allowed to touch on their
-- own row, this one included.

alter table public.bookings
  add column if not exists checked_in_at timestamptz;

-- New notification type for the "log your check-in" nudge - see
-- NotificationsService.generateTimeBasedNotifications(). Distinct
-- from the existing 'checkin_reminder' type, which is the PRE-arrival
-- "X days to go" countdown - this one fires once the stay is already
-- live and the guest hasn't confirmed yet.
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type in (
    'booking_confirmed',
    'booking_cancelled',
    'booking_rescheduled',
    'checkin_reminder',
    'checkin_log_reminder',
    'review_prompt',
    'suggestion'
  ));

-- Extends the same lazy-generation dedup index to cover the new type,
-- same one-per-booking shape as review_prompt (milestone_days stays
-- null for this type too).
drop index if exists public.notifications_lazy_unique_idx;
create unique index notifications_lazy_unique_idx
  on public.notifications (user_id, booking_id, type, milestone_days)
  where type in ('checkin_reminder', 'checkin_log_reminder', 'review_prompt');
