-- ============================================================
-- HOMELY APP - Guest/host "delete" (hide) a past booking
-- Run this AFTER schema_bookings.sql and schema_host_booking_notes.sql
-- ============================================================
-- Powers swipe-to-delete on MyBookingsScreen (guest) and
-- HostBookingsScreen (host). This is a soft delete, not a real one -
-- the booking row itself is never removed, since it's still the
-- source of truth for the OTHER side (a guest hiding a stay from
-- their own list shouldn't erase the host's record of it, and vice
-- versa), and reviews/notifications still reference it via
-- booking_id. Each side just gets its own "hide this from MY list"
-- flag.
--
-- No new RLS policies are needed: the guest-facing
-- "Users can cancel their own bookings" UPDATE policy and the
-- host-facing "Hosts can update bookings on their own listings"
-- UPDATE policy (schema_host_booking_notes.sql) already cover every
-- column on a row they're each allowed to touch, these two new ones
-- included.

alter table public.bookings
  add column if not exists hidden_by_guest boolean not null default false;

alter table public.bookings
  add column if not exists hidden_by_host boolean not null default false;
