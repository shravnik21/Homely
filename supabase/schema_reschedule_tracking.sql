-- ============================================================
-- HOMELY APP - Reschedule tracking
-- Run this AFTER schema_bookings.sql
-- ============================================================
-- Mirrors schema_cancellation_fee.sql's approach for cancellations:
-- rescheduleBooking() (see booking_service.dart) simply overwrites
-- check_in/check_out in place, so without these columns there'd be
-- no way to tell a host *when* a guest rescheduled or what the dates
-- used to be. Backs the "Booking updates" card on the host dashboard
-- (HostHomeScreen), which surfaces recent cancellations AND
-- reschedules across all of a host's listings.

alter table public.bookings
  add column if not exists rescheduled_at timestamptz,
  add column if not exists previous_check_in date,
  add column if not exists previous_check_out date;
