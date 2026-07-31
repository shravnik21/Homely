-- for error occured listing feature , new host user account not getting added in the host_public_info table 

-- Step 1

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

-- Step 2
insert into public.host_public_info (id, full_name)
select id, full_name from public.host_profiles
on conflict (id) do update set full_name = excluded.full_name;

-- Step 3
select prosrc from pg_proc where proname = 'handle_new_user';