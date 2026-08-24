-- Sync public.profiles.email wanneer auth.users.email verandert.
-- Nodig voor o.a. Contact-tab, ouder/kind-koppelingen en profiel-lijsten.
-- Run in Supabase Dashboard -> SQL Editor.

create or replace function public.sync_profile_email_from_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  has_email boolean;
begin
  if old.email is not distinct from new.email then
    return new;
  end if;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'email'
  ) into has_email;

  if has_email then
    update public.profiles
       set email = new.email
     where id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_email_updated on auth.users;

create trigger on_auth_user_email_updated
after update of email on auth.users
for each row
when (old.email is distinct from new.email)
execute procedure public.sync_profile_email_from_auth_user();

-- Backfill bestaande verschillen.
do $$
declare
  has_email boolean;
begin
  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'email'
  ) into has_email;

  if has_email then
    update public.profiles p
       set email = au.email
      from auth.users au
     where p.id = au.id
       and p.email is distinct from au.email;
  end if;
end;
$$;

select pg_notify('pgrst', 'reload schema');
