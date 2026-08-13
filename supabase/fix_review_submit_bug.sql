-- ============================================================
-- FIX: Reviews couldn't be submitted on the guest's checkout day
-- Run this once in the Supabase SQL Editor.
-- ============================================================
-- The old policy required check_out < current_date (strictly
-- BEFORE today). The app's UI shows "Leave a review" starting on
-- checkout day itself, so any review submitted on that day was
-- silently rejected by this policy. This widens it to <= so the
-- database agrees with what the app already shows.

drop policy if exists "Guests can review their own completed bookings" on public.reviews;

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
        and b.check_out <= current_date
    )
  );
