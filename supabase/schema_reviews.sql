-- ============================================================
-- HOMELY APP - Ratings & Reviews Schema
-- Run this in Supabase SQL Editor AFTER schema_bookings.sql and
-- schema_host_listings.sql have already been run.
-- ============================================================

-- 1. REVIEWS TABLE ----------------------------------------------------
-- One row per completed stay. `reviewer_name` is stored directly on
-- the row (instead of embedding `profiles` via a PostgREST join) on
-- purpose: `profiles` RLS intentionally only lets a user read their
-- OWN row (see setup.sql) - the same reasoning that led to creating
-- `host_public_info` as a separate table in schema_host_public_info.sql
-- rather than loosening `profiles`. Reviews need to be publicly
-- readable by ANY guest browsing a listing, so the reviewer's display
-- name is captured once at submit time instead.
create table if not exists public.reviews (
  id uuid default gen_random_uuid() primary key,
  -- unique -> a booking can only ever have one review, which is what
  -- enforces "one review per completed stay" at the database level
  -- (ReviewService.hasReviewedBooking() just checks this ahead of
  -- time so the UI never lets a guest try twice).
  booking_id uuid references public.bookings(id) on delete cascade not null unique,
  place_id uuid references public.places(id) on delete cascade not null,
  reviewer_id uuid references auth.users(id) on delete cascade not null,
  reviewer_name text not null,
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz default now()
);

alter table public.reviews enable row level security;

-- 2. INSERT POLICY -----------------------------------------------------
-- A guest can only insert a review for a booking that is: (a) their
-- own, (b) for the place_id they're claiming, (c) still confirmed
-- (not cancelled), and (d) already checked out (checkout date has
-- passed) - i.e. genuinely "completed", mirroring Booking.isUpcoming's
-- definition on the Dart side. This is enforced server-side so it
-- can't be bypassed even if a client bug let the button show early.
create policy "Guests can review their own completed bookings"
  on public.reviews for insert
  with check (
    auth.uid() = reviewer_id
    and exists (
      select 1 from public.bookings b
      where b.id = reviews.booking_id
        and b.user_id = auth.uid()
        and b.place_id = reviews.place_id
        and b.status = 'confirmed'
        and b.check_out < current_date
    )
  );

-- 3. SELECT POLICIES -----------------------------------------------------
-- Anyone (including logged-out guests browsing) can read reviews for
-- a published listing - same "public listings are public" reasoning
-- as schema_places.sql's own select policy.
create policy "Anyone can view reviews for published listings"
  on public.reviews for select
  using (
    exists (
      select 1 from public.places p
      where p.id = reviews.place_id and p.status = 'published'
    )
  );

-- A host can see every review left on any of their own listings,
-- regardless of that listing's current status (paused/draft), same
-- "hosts see their own stuff regardless of status" exception used
-- throughout schema_host_listings.sql.
create policy "Hosts can view reviews for their own listings"
  on public.reviews for select
  using (
    exists (
      select 1 from public.places p
      where p.id = reviews.place_id and p.host_id = auth.uid()
    )
  );

-- A guest can always see their own review (e.g. to confirm they've
-- already reviewed a booking / show "Your review" on the booking
-- details screen), even in the unlikely case the listing was later
-- unpublished.
create policy "Reviewers can view their own reviews"
  on public.reviews for select
  using (auth.uid() = reviewer_id);

-- 4. INDEXES -----------------------------------------------------
create index if not exists idx_reviews_place_id on public.reviews (place_id);
create index if not exists idx_reviews_reviewer_id on public.reviews (reviewer_id);

-- ============================================================
-- NOTE - seeding dummy reviews for testing:
-- reviews.booking_id must point at a real row in `bookings` that is
-- already confirmed with a check_out date in the past (the insert
-- policy above requires it), so dummy reviews can't simply be
-- inserted against made-up ids. Easiest path for testing: complete a
-- real booking flow with a check-out date in the past (or backdate
-- an existing test booking's check_out via the SQL editor), then
-- submit a review through the app itself, OR temporarily insert as
-- the `service_role` key (which bypasses RLS) with a booking_id
-- that already satisfies the same conditions.
-- ============================================================
