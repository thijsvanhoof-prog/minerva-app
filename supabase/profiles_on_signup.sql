-- Create/refresh a profile row when a new auth user is created.
--
-- Run this in Supabase SQL Editor.
--
-- This reads the username from auth.users.raw_user_meta_data.display_name (set during sign-up),
-- and inserts/updates public.profiles. It is defensive about optional columns (email).

create or replace function public.handle_new_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  dn text;
  has_email boolean;
begin
  dn := nullif(trim(new.raw_user_meta_data->>'display_name'), '');
  if dn is null then
    dn := split_part(coalesce(new.email, ''), '@', 1);
  end if;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'email'
  ) into has_email;

  if has_email then
    execute
      'insert into public.profiles (id, display_name, email)
       values ($1, $2, $3)
       on conflict (id) do update
       set display_name = excluded.display_name,
           email = excluded.email'
      using new.id, dn, new.email;
  else
    execute
      'insert into public.profiles (id, display_name)
       values ($1, $2)
       on conflict (id) do update
       set display_name = excluded.display_name'
      using new.id, dn;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute procedure public.handle_new_user_profile();

