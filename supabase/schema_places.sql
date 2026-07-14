-- ============================================================
-- HOMELY APP - Phase 2 Schema (cities, places, place_images)
-- Run this FIRST in Supabase SQL Editor, then run seed_places.sql
-- ============================================================

-- 1. CITIES
create table if not exists public.cities (
  id uuid default gen_random_uuid() primary key,
  name text unique not null,
  created_at timestamptz default now()
);

-- 2. PLACES
create table if not exists public.places (
  id uuid default gen_random_uuid() primary key,
  city_id uuid references public.cities(id) on delete cascade,
  title text not null,
  type text not null check (type in ('villa', 'apartment', 'cottage', 'cabin', 'bungalow', 'holiday home', 'beach house', 'farmhouse', 'penthouse', 'homestay')),
  price_per_night numeric not null,
  max_guests int not null default 2,
  bedrooms int default 1,
  bathrooms int default 1,
  address text,
  description text,
  amenities text[] default '{}',
  created_at timestamptz default now()
);

-- 3. PLACE IMAGES (5 per place)
create table if not exists public.place_images (
  id uuid default gen_random_uuid() primary key,
  place_id uuid references public.places(id) on delete cascade,
  image_url text not null,
  sort_order int default 0
);

-- 4. ROW LEVEL SECURITY
-- These are public listings - anyone (even logged-out users, via the anon key)
-- should be able to READ them. Only Supabase dashboard / service_role can write for now.
alter table public.cities enable row level security;
alter table public.places enable row level security;
alter table public.place_images enable row level security;

create policy "Anyone can view cities" on public.cities for select using (true);
create policy "Anyone can view places" on public.places for select using (true);
create policy "Anyone can view place images" on public.place_images for select using (true);

-- 5. HELPFUL INDEX for the common query pattern (places filtered by city)
create index if not exists idx_places_city_id on public.places (city_id);
create index if not exists idx_place_images_place_id on public.place_images (place_id);
