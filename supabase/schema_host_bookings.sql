-- ============================================================
-- HOMELY APP - Host visibility into bookings on their own listings
-- Run this AFTER schema_bookings.sql and schema_host_listings.sql
-- ============================================================

-- 1. Hosts can see bookings made on places they own (guests can
-- already see their own bookings via the existing policy in
-- schema_bookings.sql - this just adds the host's side of it).
create policy "Hosts can view bookings on their own listings"
  on public.bookings for select
  using (
    exists (
      select 1 from public.places p
      where p.id = bookings.place_id and p.host_id = auth.uid()
    )
  );

-- 2. Hosts can see the (limited) profile info - just the name - of
-- guests who booked one of their listings, so the Host Home /
-- bookings list can show who booked instead of just a booking id.
-- Existing policy in setup.sql already lets a user see their OWN
-- profile; this adds the host's narrow, booking-scoped exception.
create policy "Hosts can view profiles of their guests"
  on public.profiles for select
  using (
    exists (
      select 1 from public.bookings b
      join public.places p on p.id = b.place_id
      where b.user_id = profiles.id and p.host_id = auth.uid()
    )
  );
