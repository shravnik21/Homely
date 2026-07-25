-- ============================================================
-- HOMELY APP - Split host-specific data out of `profiles`
-- Run this in Supabase SQL Editor AFTER setup.sql, add_role_column.sql,
-- schema_host_onboarding.sql, and schema_host_verification.sql have
-- already been run (this migrates data OUT of those columns).
-- ============================================================

-- 1. NEW TABLE: host_profiles
-- Holds ONLY host-specific data. `profiles` stays generic/guest-facing
-- (full_name, email, phone, avatar_url, role, created_at).
create table if not exists public.host_profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  host_onboarding_completed boolean not null default false,
  id_verification_status text not null default 'not_started'
    check (id_verification_status in ('not_started', 'pending', 'verified')),
  id_document_url text,
  phone_verified boolean not null default false,
  bank_account_holder text,
  bank_account_number text,
  bank_ifsc text,
  upi_id text,
  payout_setup_complete boolean not null default false,
  host_agreement_accepted boolean not null default false,
  host_agreement_accepted_at timestamptz,
  created_at timestamptz default now()
);

alter table public.host_profiles enable row level security;

create policy "Hosts can view their own host profile"
  on public.host_profiles for select
  using (auth.uid() = id);

create policy "Hosts can update their own host profile"
  on public.host_profiles for update
  using (auth.uid() = id);

create policy "Hosts can insert their own host profile"
  on public.host_profiles for insert
  with check (auth.uid() = id);

-- 2. BACKFILL: copy existing host data out of profiles for any
-- accounts that already have role = 'host' (e.g. your own test
-- accounts created before this migration).
insert into public.host_profiles (
  id, host_onboarding_completed, id_verification_status, id_document_url,
  phone_verified, bank_account_holder, bank_account_number, bank_ifsc,
  upi_id, payout_setup_complete, host_agreement_accepted, host_agreement_accepted_at
)
select
  id, host_onboarding_completed, id_verification_status, id_document_url,
  phone_verified, bank_account_holder, bank_account_number, bank_ifsc,
  upi_id, payout_setup_complete, host_agreement_accepted, host_agreement_accepted_at
from public.profiles
where role = 'host'
on conflict (id) do nothing;

-- 3. UPDATE SIGNUP TRIGGER: also create a host_profiles row
-- automatically whenever someone signs up with role = 'host'.
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, email, role)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.email,
    coalesce(new.raw_user_meta_data->>'role', 'guest')
  );

  if coalesce(new.raw_user_meta_data->>'role', 'guest') = 'host' then
    insert into public.host_profiles (id) values (new.id)
    on conflict (id) do nothing;
  end if;

  return new;
end;
$$ language plpgsql security definer;

-- 4. CLEAN UP: remove the now-duplicated host-specific columns from
-- profiles - it goes back to being guest/generic-only.
alter table public.profiles
  drop column if exists host_onboarding_completed,
  drop column if exists id_verification_status,
  drop column if exists id_document_url,
  drop column if exists phone_verified,
  drop column if exists bank_account_holder,
  drop column if exists bank_account_number,
  drop column if exists bank_ifsc,
  drop column if exists upi_id,
  drop column if exists payout_setup_complete,
  drop column if exists host_agreement_accepted,
  drop column if exists host_agreement_accepted_at;
