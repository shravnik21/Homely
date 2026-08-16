-- ============================================================
-- HOMELY APP - Host-blocked dates
-- Run this AFTER schema_place_availability.sql
-- ============================================================
-- Lets a host manually mark a date as unavailable on one of their
-- listings (e.g. personal use, maintenance, off-platform booking) -
-- independent of any guest booking. One row per (place, date) rather
-- than a date range, since the host toggles individual dates on/off
-- straight from the calendar (tap a free date to block it, tap a
-- blocked date to unblock it).

create table if not exists public.blocked_dates (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references public.places(id) on delete cascade,
  date date not null,
  created_at timestamptz not null default now(),
  unique (place_id, date)
);

create index if not exists blocked_dates_place_id_idx
  on public.blocked_dates (place_id);

alter table public.blocked_dates enable row level security;

-- A host can view/add/remove blocked dates only for places they own -
-- same ownership check used throughout schema_host_listings.sql.
create policy "Hosts manage blocked dates on their own places"
on public.blocked_dates
for all
using (
  exists (
    select 1 from public.places
    where places.id = blocked_dates.place_id
      and places.host_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.places
    where places.id = blocked_dates.place_id
      and places.host_id = auth.uid()
  )
);

-- Guest-facing read: same "security definer, bare dates only" pattern
-- as get_booked_ranges() in schema_place_availability.sql - lets any
-- authenticated guest see WHICH dates a host has blocked for a place
-- (so the booking/reschedule calendar can grey them out right next to
-- already-booked dates) without exposing the blocked_dates table
-- itself, which stays host-only via the RLS policy above.
create or replace function public.get_blocked_dates(p_place_id uuid)
returns table (date date)
language sql
security definer
set search_path = public
as $$
  select date
  from public.blocked_dates
  where place_id = p_place_id
    -- No point returning dates that have already passed.
    and date >= current_date;
$$;

grant execute on function public.get_blocked_dates(uuid) to authenticated;
