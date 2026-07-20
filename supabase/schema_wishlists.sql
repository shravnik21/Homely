-- ============================================================
-- HOMELY APP - Wishlist Schema
-- Run this in Supabase SQL Editor
-- ============================================================

create table if not exists public.wishlists (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  place_id uuid references public.places(id) on delete cascade not null,
  created_at timestamptz default now(),
  -- a user can only save a given place once - re-tapping the heart
  -- toggles it off rather than creating duplicate rows
  constraint unique_user_place unique (user_id, place_id)
);

alter table public.wishlists enable row level security;

-- Same private-data pattern as bookings: a user should only ever see,
-- add to, or remove from THEIR OWN wishlist.
create policy "Users can view their own wishlist"
  on public.wishlists for select
  using (auth.uid() = user_id);

create policy "Users can add to their own wishlist"
  on public.wishlists for insert
  with check (auth.uid() = user_id);

create policy "Users can remove from their own wishlist"
  on public.wishlists for delete
  using (auth.uid() = user_id);

create index if not exists idx_wishlists_user_id on public.wishlists (user_id);
create index if not exists idx_wishlists_place_id on public.wishlists (place_id);
