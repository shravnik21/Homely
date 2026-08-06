-- ============================================================
-- HOMELY APP - Cancellation fee tracking
-- Run this AFTER schema_bookings.sql
-- ============================================================
-- Backs the sliding-scale cancellation policy in
-- lib/services/cancellation_policy.dart: the fee/refund a guest is
-- charged depends on how many days before check-in they cancel.
-- These columns record what was actually applied at the moment of
-- cancellation, so the numbers shown later (guest's booking detail,
-- host's payout view) never drift even if the policy itself changes
-- in a future release.

alter table public.bookings
  add column if not exists cancellation_fee numeric,
  add column if not exists refund_amount numeric,
  add column if not exists cancelled_at timestamptz;
