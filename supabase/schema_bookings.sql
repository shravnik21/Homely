-- ============================================================
-- HOMELY APP - Phase 3 Schema (bookings)
-- Run this in Supabase SQL Editor
-- ============================================================

create table if not exists public.bookings (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  place_id uuid references public.places(id) on delete cascade not null,
  check_in date not null,
  check_out date not null,
  guests int not null default 1,
  total_price numeric not null,
  status text not null default 'confirmed',
  created_at timestamptz default now(),
  constraint valid_dates check (check_out > check_in)
);

alter table public.bookings enable row level security;

-- IMPORTANT CONTRAST WITH places' RLS:
-- places used `using (true)` - anyone can read, since listings are public.
-- bookings are PRIVATE - a user should only ever see/create/cancel
-- their OWN bookings. auth.uid() is the currently authenticated user's
-- id, automatically available to every RLS policy.
create policy "Users can view their own bookings"
  on public.bookings for select
  using (auth.uid() = user_id);

create policy "Users can create their own bookings"
  on public.bookings for insert
  with check (auth.uid() = user_id);

create policy "Users can cancel their own bookings"
  on public.bookings for update
  using (auth.uid() = user_id);

create index if not exists idx_bookings_user_id on public.bookings (user_id);
create index if not exists idx_bookings_place_id on public.bookings (place_id);
