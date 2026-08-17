-- ============================================================
-- HOMELY APP - Check-in method (replaces the plain self_checkin flag)
-- Run this AFTER schema_place_highlights.sql
-- ============================================================
-- schema_place_highlights.sql added a bare self_checkin boolean, but
-- "yes/no" doesn't actually tell a guest anything useful - a smart
-- lock and "the key is under a rock" are both technically "self
-- check-in" but very different experiences. This replaces it with:
--   - checkin_method: which of a fixed set of methods the host picked
--     (see the option list in ListingWizardScreen - stored as a
--     short key like 'smart_lock', not the display label, so the
--     label can be reworded later without a data migration)
--   - checkin_details: free text the host writes describing exactly
--     how it works for THEIR place (e.g. "Code is 1234, keypad is by
--     the front door") - shown as the highlight's description on
--     PlaceDetailScreen
-- Both nullable - "not set" is a valid state and simply means the
-- check-in row doesn't show up in Highlights at all (same idea as
-- highlight1/2 already being optional).

alter table public.places drop column if exists self_checkin;

alter table public.places
  add column if not exists checkin_method text;

alter table public.places
  add column if not exists checkin_details text;
