-- ============================================================
-- HOMELY APP - Link host_profiles to profiles (for host name/email)
-- Run this in Supabase SQL Editor AFTER schema_split_host_profiles.sql
-- ============================================================

-- host_profiles.id already equals a valid profiles.id (both ultimately
-- reference auth.users.id), but Postgres/PostgREST needs an EXPLICIT
-- foreign key between host_profiles and profiles specifically for
-- Supabase's nested-select join syntax to auto-detect the
-- relationship (the same trick used for places -> cities elsewhere
-- in this project).
alter table public.host_profiles
  add constraint host_profiles_id_fkey_profiles
  foreign key (id) references public.profiles(id) on delete cascade;

-- ============================================================
-- Example: fetch a host's setup status ALONGSIDE their name/email
-- ============================================================

-- Plain SQL (run directly in SQL Editor):
select
  hp.*,
  p.full_name as host_name,
  p.email as host_email
from public.host_profiles hp
join public.profiles p on p.id = hp.id;

-- Supabase Flutter / PostgREST equivalent (nested select, one round
-- trip - same join syntax used by PlacesService.getPlaces()):
--
--   await _client
--       .from('host_profiles')
--       .select('*, profiles(full_name, email)')
--       .eq('id', userId)
--       .maybeSingle();
--
-- Returns a map where profile data sits under a nested 'profiles' key:
--   { id: ..., payout_setup_complete: ..., profiles: { full_name: ..., email: ... } }
