-- Lijst profielen voor commissie-beheer (Bestuur → Commissies → Lid toevoegen)
--
-- Zonder deze RPC kan bestuur alleen het eigen profiel zien bij "Lid toevoegen",
-- omdat de profiles-tabel vaak restrictieve RLS heeft (alleen eigen rij).
--
-- Vereisten: committee_members tabel met bestuur-leden.
-- Voer uit in Supabase SQL Editor.

create or replace function public.list_profiles_for_committee_management()
returns table (
  profile_id uuid,
  display_name text,
  email text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- Toegestaan: bestuur-leden of global admin (indien aanwezig)
  if exists (select 1 from pg_proc p join pg_namespace n on p.pronamespace = n.oid where n.nspname = 'public' and p.proname = 'is_global_admin') then
    if public.is_global_admin() then
      return query select * from _list_all_profiles();
      return;
    end if;
  end if;

  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'committee_members') then
    if exists (
      select 1 from public.committee_members cm
      where lower(cm.committee_name) = 'bestuur'
        and cm.profile_id = auth.uid()
    ) then
      return query select * from _list_all_profiles();
      return;
    end if;
  end if;

  raise exception 'Geen toegang';
end;
$$;

create or replace function public._list_all_profiles()
returns table (
  profile_id uuid,
  display_name text,
  email text
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    au.id as profile_id,
    coalesce(
      nullif(trim(to_jsonb(p)->>'display_name'), ''),
      nullif(trim(to_jsonb(p)->>'full_name'), ''),
      nullif(trim(to_jsonb(p)->>'name'), ''),
      nullif(trim(au.raw_user_meta_data->>'display_name'), ''),
      nullif(trim(au.email), ''),
      (left(au.id::text, 4) || '…' || right(au.id::text, 4))
    )::text as display_name,
    coalesce(au.email, '')::text as email
  from auth.users au
  left join public.profiles p on p.id = au.id
  order by lower(
    coalesce(
      nullif(trim(to_jsonb(p)->>'display_name'), ''),
      nullif(trim(au.raw_user_meta_data->>'display_name'), ''),
      nullif(trim(au.email), ''),
      au.id::text
    )
  );
$$;

grant execute on function public.list_profiles_for_committee_management() to authenticated;
