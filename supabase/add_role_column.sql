-- ============================================================
-- Adds a `role` column ('guest' | 'host') to profiles, and
-- updates the signup trigger to store it from user metadata.
-- Run this AFTER setup.sql in the Supabase SQL Editor.
-- ============================================================

alter table public.profiles
  add column if not exists role text not null default 'guest';

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
  return new;
end;
$$ language plpgsql security definer;

-- Trigger itself is unchanged (still on_auth_user_created), the
-- function it points to is just replaced above.
