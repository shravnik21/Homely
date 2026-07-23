-- ============================================================
-- HOMELY APP - Host onboarding tracking
-- Run this in Supabase SQL Editor
-- ============================================================

alter table public.profiles
  add column if not exists host_onboarding_completed boolean not null default false;
