-- ============================================================
-- HOMELY APP - Fix: host can't update their own public info
-- Run this in Supabase SQL Editor AFTER schema_host_public_info.sql
-- ============================================================
-- Bug: editing your name as a host throws an error. Root cause:
-- schema_host_public_info.sql enabled RLS on host_public_info but
-- only ever added a SELECT policy ("Anyone can view public host
-- info"). The signup trigger (handle_new_user) can still populate a
-- host's row because it runs `security definer`, which bypasses RLS
-- entirely - but AuthService.updateProfile()'s client-side
-- `.upsert(...)` call runs as the logged-in host through normal
-- Postgrest, which IS subject to RLS. With no INSERT/UPDATE policy
-- granting anything, Postgres denies the write outright, which is
-- the error surfacing in EditProfileScreen when a host changes their
-- name.
--
-- Fix: add the same "own row only" INSERT/UPDATE policies every
-- other per-user table in this project already has (host_profiles,
-- profiles, etc.) - a host can only ever write their OWN row here,
-- never anyone else's.

create policy "Hosts can insert their own public info"
  on public.host_public_info for insert
  with check (auth.uid() = id);

create policy "Hosts can update their own public info"
  on public.host_public_info for update
  using (auth.uid() = id)
  with check (auth.uid() = id);