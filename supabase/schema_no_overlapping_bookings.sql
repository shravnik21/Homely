-- ============================================================
-- HOMELY APP - Belt-and-suspenders double-booking prevention
-- Run this AFTER schema_bookings.sql
-- ============================================================
-- schema_place_availability.sql's get_booked_ranges() + the
-- AvailabilityService/availability_date_range_sheet.dart calendar it
-- powers stop a guest from PICKING overlapping dates in the UI - but
-- that's a read-then-act check with a real race window: two guests
-- can both load the calendar, both see the same nights as free, and
-- both submit within moments of each other. Nothing in the schema
-- itself was stopping the second insert/update from going through
-- and silently double-booking the place.
--
-- A Postgres EXCLUDE constraint closes that window at the one place
-- it actually needs closing: the database itself. Whichever request
-- reaches Postgres second gets rejected outright (error code
-- 23P01/'exclusion_violation'), no matter what the client believed
-- was available.

-- EXCLUDE constraints need GiST support for the `=` operator on
-- place_id (a plain uuid) alongside `&&` (overlap) on the date range
-- - btree_gist supplies exactly that bridge.
create extension if not exists btree_gist;

alter table public.bookings
  add constraint no_overlapping_bookings
  exclude using gist (
    place_id with =,
    -- '[)' = check-in inclusive, check-out exclusive - matches the
    -- app's own convention (see AvailabilityService) that the
    -- checkout day itself is open for the next guest's check-in.
    daterange(check_in, check_out, '[)') with &&
  )
  -- Cancelled bookings shouldn't block anything - two cancelled
  -- bookings (or a cancelled one and a live one) are allowed to
  -- "overlap" freely.
  where (status <> 'cancelled');
