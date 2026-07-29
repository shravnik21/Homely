-- ============================================================
-- HOMELY APP - Fix: stable, city-grouped ordering for places
-- Run this in Supabase SQL Editor
-- ============================================================
-- Root cause: `places` was being sorted only by created_at, but all
-- 25 seeded demo places were inserted in one script/transaction, so
-- they share near-identical timestamps. With no real tiebreaker,
-- Postgres can return ties in a different order after ANY later
-- UPDATE touches those rows (like the recent host-listings
-- migrations did) - which is exactly what scrambled the city
-- grouping you saw.

-- 1. Give cities a fixed display order
alter table public.cities
  add column if not exists display_order integer;

update public.cities set display_order = 1 where name = 'Goa';
update public.cities set display_order = 2 where name = 'Alibaug';
update public.cities set display_order = 3 where name = 'Lonavala';
update public.cities set display_order = 4 where name = 'Mumbai';
update public.cities set display_order = 5 where name = 'Pune';

-- Any future city you add (see: "any place in India" expansion)
-- just needs a display_order value too - it'll slot in wherever
-- you set it, and NEW listings within a city always sort AFTER
-- existing ones there (see the query change below), so a newly
-- added place always joins the end of its own city's group rather
-- than getting mixed in anywhere else.
