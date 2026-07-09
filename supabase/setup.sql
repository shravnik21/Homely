-- ============================================================
-- FARMSTAY APP - Supabase Setup (Phase 1: Auth + Profiles)
-- Run this in Supabase Dashboard -> SQL Editor
-- ============================================================

-- 1. PROFILES TABLE
-- Stores extra user info beyond what auth.users holds.
create table if not exists public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  full_name text,
  email text,
  phone text,
  avatar_url text,
  created_at timestamp with time zone default now()
);

-- 2. ENABLE ROW LEVEL SECURITY
alter table public.profiles enable row level security;

-- 3. POLICIES: a user can only read/update their OWN profile
create policy "Users can view their own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update their own profile"
  on public.profiles for update
  using (auth.uid() = id);

create policy "Users can insert their own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

-- 4. TRIGGER: auto-create a profile row whenever someone signs up
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, new.raw_user_meta_data->>'full_name', new.email);
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============================================================
-- NOTES:
-- - Go to Authentication -> Providers -> Email and make sure
--   "Confirm email" is toggled the way you want (OFF is easier
--   while testing so you don't need to click a verification link).
-- - Go to Project Settings -> API to get your Project URL and
--   anon public key for the .env file.
-- ============================================================
