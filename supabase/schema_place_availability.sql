-- ============================================================
-- HOMELY APP - Guest-facing availability calendar
-- Run this AFTER schema_bookings.sql
-- ============================================================
-- bookings' RLS ("Users can view their own bookings") is correct and
-- should stay as-is - a guest has no business seeing who else booked
-- what, for how much. But the booking screen's date picker still
-- needs to know WHICH DATES are already taken for a place, so guests
-- can't pick a range that double-books a listing.
--
-- Standard fix: a `security definer` function that deliberately
-- returns nothing but bare date ranges - no user_id, no guest name,
-- no price - so it's safe to expose to any authenticated guest even
-- though the underlying table isn't. Same pattern already used by
-- handle_new_user() in host_public_info_error_fix.sql.

create or replace function public.get_booked_ranges(
  p_place_id uuid,
  p_exclude_booking_id uuid default null
)
returns table (check_in date, check_out date)
language sql
security definer
set search_path = public
as $$
  select check_in, check_out
  from public.bookings
  where place_id = p_place_id
    and status <> 'cancelled'
    -- No point blocking dates that have already passed.
    and check_out >= current_date
    -- Lets the reschedule flow ask "what's booked, ignoring MY OWN
    -- current booking" - otherwise a booking would block out its own
    -- existing dates and a guest could never keep any overlapping
    -- night while rescheduling.
    and (p_exclude_booking_id is null or id <> p_exclude_booking_id);
$$;

grant execute on function public.get_booked_ranges(uuid, uuid) to authenticated;
