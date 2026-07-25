-- ============================================================
-- HOMELY APP - Host verification, payouts & agreement
-- Run this in Supabase SQL Editor
-- ============================================================

-- 1. New columns on profiles for host setup tracking
alter table public.profiles
  add column if not exists id_verification_status text not null default 'not_started'
    check (id_verification_status in ('not_started', 'pending', 'verified')),
  add column if not exists id_document_url text,
  add column if not exists phone_verified boolean not null default false,
  add column if not exists bank_account_holder text,
  add column if not exists bank_account_number text,
  add column if not exists bank_ifsc text,
  add column if not exists upi_id text,
  add column if not exists payout_setup_complete boolean not null default false,
  add column if not exists host_agreement_accepted boolean not null default false,
  add column if not exists host_agreement_accepted_at timestamptz;

-- 2. Storage bucket for government ID uploads
-- Run this part in the Supabase Dashboard -> Storage -> "New bucket"
-- if the SQL insert below doesn't work in your project (bucket
-- creation via SQL requires the storage extension to be exposed,
-- which it usually is on Supabase, but the dashboard UI always works
-- as a fallback):
insert into storage.buckets (id, name, public)
values ('host-documents', 'host-documents', false)
on conflict (id) do nothing;

-- 3. Storage RLS: a host can only upload/view files inside a folder
-- named after their own user id (host-documents/{user_id}/...) -
-- this is the standard Supabase Storage pattern for private
-- per-user files.
create policy "Hosts can upload their own ID documents"
  on storage.objects for insert
  with check (
    bucket_id = 'host-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Hosts can view their own ID documents"
  on storage.objects for select
  using (
    bucket_id = 'host-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Hosts can replace their own ID documents"
  on storage.objects for update
  using (
    bucket_id = 'host-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
