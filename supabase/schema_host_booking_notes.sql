-- ============================================================
-- HOMELY APP - Private host notes on a booking
-- Run this AFTER schema_bookings.sql and schema_host_bookings.sql
-- ============================================================
-- Powers the "Notes" section on the host's booking-detail screen -
-- a free-text field only the host who owns the listing can see or
-- edit, e.g. "Guest asked for early check-in", "Bring extra towels".

-- 1. New nullable column on bookings - guests never see or set this,
-- it's purely for the host's own reference.
alter table public.bookings
  add column if not exists host_notes text;

-- 2. Hosts can update bookings on their own listings (needed so they
-- can save host_notes - the existing "Users can cancel their own
-- bookings" policy only covers the guest's own row, not the host's
-- side of the same booking).
drop policy if exists "Hosts can update bookings on their own listings" on public.bookings;
create policy "Hosts can update bookings on their own listings"
  on public.bookings for update
  using (
    exists (
      select 1 from public.places p
      where p.id = bookings.place_id and p.host_id = auth.uid()
    )
  );
