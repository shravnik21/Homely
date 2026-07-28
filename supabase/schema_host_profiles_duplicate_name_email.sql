-- ============================================================
-- HOMELY APP - Duplicate full_name & email onto host_profiles
-- Run this in Supabase SQL Editor
-- ============================================================
-- These are REAL columns on host_profiles now (not just referenced
-- via the FK join) - kept in sync with `profiles` whenever a host
-- updates their name via AuthService.updateProfile() (see the Dart
-- changes alongside this migration).

-- 1. Add the columns
alter table public.host_profiles
  add column if not exists full_name text,
  add column if not exists email text;

-- 2. Backfill existing host rows from profiles
update public.host_profiles hp
set
  full_name = p.full_name,
  email = p.email
from public.profiles p
where p.id = hp.id;

-- 3. Update the signup trigger so these are populated immediately
-- for any NEW host signup too.
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
    insert into public.host_profiles (id, full_name, email)
    values (new.id, new.raw_user_meta_data->>'full_name', new.email)
    on conflict (id) do update set
      full_name = excluded.full_name,
      email = excluded.email;
  end if;

  return new;
end;
$$ language plpgsql security definer;

-- ============================================================
-- Verify
-- ============================================================
select id, full_name, email, id_verification_status, payout_setup_complete, host_agreement_accepted
from public.host_profiles;
