-- ============================================================
-- HOMELY APP - Listing highlights (self check-in + 2 custom ones)
-- Run this AFTER schema_host_listings.sql
-- ============================================================
-- Powers the small "Highlights" row-list on PlaceDetailScreen -
-- Airbnb's own listing pages show a short icon+title+description row
-- for a few standout things about a place (e.g. "Self check-in",
-- "Great location"). This is a deliberately simplified version of
-- that idea: one fixed boolean toggle (self check-in) plus two fully
-- host-written slots, each with its own headline and one-line
-- description, set from a dedicated step in ListingWizardScreen.
--
-- No new RLS policies needed - "Hosts can update their own listings"
-- (schema_host_listings.sql) already covers every column on a place
-- row a host owns, these five included, and the existing
-- "Anyone can view published places" SELECT policy already covers
-- reading them back on the guest-facing detail screen.

alter table public.places
  add column if not exists self_checkin boolean not null default false;

alter table public.places
  add column if not exists highlight1_title text;

alter table public.places
  add column if not exists highlight1_description text;

alter table public.places
  add column if not exists highlight2_title text;

alter table public.places
  add column if not exists highlight2_description text;
