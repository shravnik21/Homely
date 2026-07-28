-- ============================================================
-- HOMELY APP - Public host info (name only) for guest display
-- Run this in Supabase SQL Editor
-- ============================================================
-- IMPORTANT SECURITY NOTE: host_profiles contains sensitive data
-- (bank account number, ID document URL, phone_verified, etc.) and
-- its RLS correctly restricts it to `auth.uid() = id` only - a host
-- can only read their OWN row. That means it CANNOT be used to show
-- a host's name to guests browsing a listing.
--
-- Instead of loosening host_profiles' RLS (which would risk exposing
-- bank details to any authenticated user), this creates a SEPARATE,
-- tiny table with only the one column that's actually meant to be
-- public: full_name. This is the same "duplicate + sync" pattern
-- already used for host_profiles vs profiles.

-- 1. New table - just id + full_name, nothing sensitive
create table if not exists public.host_public_info (
  id uuid primary key references public.host_profiles(id) on delete cascade,
  full_name text
);

alter table public.host_public_info enable row level security;

drop policy if exists "Anyone can view public host info" on public.host_public_info;
create policy "Anyone can view public host info"
  on public.host_public_info for select
  using (true);

-- 2. Backfill from existing hosts
insert into public.host_public_info (id, full_name)
select id, full_name from public.host_profiles
on conflict (id) do update set full_name = excluded.full_name;

-- 3. FK from places.host_id -> host_public_info.id, so PostgREST can
-- embed the host's name directly into the same query guests already
-- run (PlacesService.getPlaces()) - no extra round trip needed.
alter table public.places
  drop constraint if exists places_host_id_fkey_public_info;
alter table public.places
  add constraint places_host_id_fkey_public_info
  foreign key (host_id) references public.host_public_info(id) on delete set null;

-- 4. Keep host_public_info populated for future signups too
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

    insert into public.host_public_info (id, full_name)
    values (new.id, new.raw_user_meta_data->>'full_name')
    on conflict (id) do update set full_name = excluded.full_name;
  end if;

  return new;
end;
$$ language plpgsql security definer;
