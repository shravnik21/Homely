-- ============================================================
-- HOMELY APP - Host-created listings (Add/Edit/Pause/Delete)
-- Run this in Supabase SQL Editor AFTER schema_places.sql and
-- schema_split_host_profiles.sql have already been run.
-- ============================================================

-- 1. OWNERSHIP + LIFECYCLE COLUMNS ON `places` ----------------------
-- host_id is nullable so the existing seed_places.sql rows (which
-- have no owning host) keep working exactly as before - they just
-- read as "platform listings" with no host attached.
alter table public.places
  add column if not exists host_id uuid references auth.users(id) on delete cascade;

-- Existing rows default to 'published' so nothing already on the app
-- disappears from guest search when this migration runs. New
-- listings created via the host wizard explicitly set 'draft' or
-- 'published' themselves (see ListingService) rather than relying on
-- this column default.
alter table public.places
  add column if not exists status text not null default 'published'
    check (status in ('draft', 'published', 'paused'));

alter table public.places
  add column if not exists house_rules text;

-- Placeholders for the future "drop a pin" location step - nullable
-- and unused by the app until that's built; address/city cover
-- location for now.
alter table public.places
  add column if not exists latitude double precision;

alter table public.places
  add column if not exists longitude double precision;

create index if not exists idx_places_host_id on public.places (host_id);


-- 2. ROW LEVEL SECURITY -----------------------------------------------
-- Replace the old "anyone can view every place" policy with one that
-- only exposes PUBLISHED listings to the general public (guests
-- browsing anonymously or logged in) - drafts and paused listings
-- must stay invisible to guests.
drop policy if exists "Anyone can view places" on public.places;

create policy "Anyone can view published places"
  on public.places for select
  using (status = 'published');

-- A host can see ALL of their own listings regardless of status
-- (draft/paused/published) - needed for "Your Listings" and the
-- listing switcher.
create policy "Hosts can view their own listings"
  on public.places for select
  using (auth.uid() = host_id);

create policy "Hosts can insert their own listings"
  on public.places for insert
  with check (auth.uid() = host_id);

create policy "Hosts can update their own listings"
  on public.places for update
  using (auth.uid() = host_id);

create policy "Hosts can delete their own listings"
  on public.places for delete
  using (auth.uid() = host_id);

-- place_images: same ownership check, via a join back to places
-- since place_images itself has no host_id column.
drop policy if exists "Anyone can view place images" on public.place_images;

create policy "Anyone can view images of published places"
  on public.place_images for select
  using (
    exists (
      select 1 from public.places p
      where p.id = place_images.place_id and p.status = 'published'
    )
  );

create policy "Hosts can view images of their own listings"
  on public.place_images for select
  using (
    exists (
      select 1 from public.places p
      where p.id = place_images.place_id and p.host_id = auth.uid()
    )
  );

create policy "Hosts can insert images on their own listings"
  on public.place_images for insert
  with check (
    exists (
      select 1 from public.places p
      where p.id = place_images.place_id and p.host_id = auth.uid()
    )
  );

create policy "Hosts can update images on their own listings"
  on public.place_images for update
  using (
    exists (
      select 1 from public.places p
      where p.id = place_images.place_id and p.host_id = auth.uid()
    )
  );

create policy "Hosts can delete images on their own listings"
  on public.place_images for delete
  using (
    exists (
      select 1 from public.places p
      where p.id = place_images.place_id and p.host_id = auth.uid()
    )
  );


-- 3. STORAGE BUCKET FOR LISTING PHOTOS --------------------------------
-- PUBLIC (unlike host-documents) - listing photos need to load
-- directly via CachedNetworkImage for any guest browsing, logged in
-- or not, same as the Unsplash URLs used in seed_places.sql.
insert into storage.buckets (id, name, public)
values ('listing-images', 'listing-images', true)
on conflict (id) do nothing;

-- Upload path convention: listing-images/{host_id}/{place_id}/{filename}
create policy "Hosts can upload their own listing photos"
  on storage.objects for insert
  with check (
    bucket_id = 'listing-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Hosts can update their own listing photos"
  on storage.objects for update
  using (
    bucket_id = 'listing-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Hosts can delete their own listing photos"
  on storage.objects for delete
  using (
    bucket_id = 'listing-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Anyone can view listing photos"
  on storage.objects for select
  using (bucket_id = 'listing-images');
