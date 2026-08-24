-- Profielrollen voor account-segmentatie in TC-lijst.
-- Doel:
-- - Als profiel in team_members zit => member (supporter gaat dan weg).
-- - Als profiel ouder/verzorger is (parent_id in account_links) => ouder
-- - Anders (uit team gezet, geen ouder) => null → staat weer in TC-lijst "zonder team/commissie".
-- - Alleen expliciet door TC "Supporter (geen team)" => supporter (blijft uit het lijstje).
-- Ouder en supporter worden in TC "zonder team/commissie" uitgefilterd in app.
--
-- Run in Supabase SQL Editor.

alter table if exists public.profiles
  add column if not exists account_role text;

alter table if exists public.profiles
  drop constraint if exists profiles_account_role_check;

alter table if exists public.profiles
  add constraint profiles_account_role_check
  check (account_role is null or account_role in ('supporter', 'member', 'ouder'));

create or replace function public.refresh_profile_account_role(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  has_team boolean;
  has_parent_link boolean := false;
  has_account_links_table boolean;
  next_role text;
begin
  if p_profile_id is null then
    return;
  end if;

  select exists(
    select 1 from public.team_members tm where tm.profile_id = p_profile_id
  ) into has_team;

  select to_regclass('public.account_links') is not null into has_account_links_table;

  if has_account_links_table then
    execute $q$
      select exists(
        select 1 from public.account_links l where l.parent_id = $1
      )
    $q$
    into has_parent_link
    using p_profile_id;
  end if;

  if has_parent_link then
    next_role := 'ouder';
  elsif has_team then
    next_role := 'member';
  else
    -- Geen team, geen ouder: null → komt weer in TC-lijst "zonder team/commissie".
    -- Supporter wordt alleen gezet als TC expliciet "Supporter (geen team)" kiest.
    next_role := null;
  end if;

  update public.profiles
  set account_role = next_role
  where id = p_profile_id;
end;
$$;

grant execute on function public.refresh_profile_account_role(uuid) to authenticated;

-- Expliciet iemand de rol supporter geven (alleen TC/bestuur/admin). Gebruikt wanneer TC "Supporter (geen team)" aanvinkt.
create or replace function public.set_profile_account_role_supporter(p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if p_profile_id is null then
    return;
  end if;
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if exists (select 1 from pg_proc p join pg_namespace n on p.pronamespace = n.oid where n.nspname = 'public' and p.proname = 'is_global_admin') then
    if public.is_global_admin() then
      update public.profiles set account_role = 'supporter' where id = p_profile_id;
      return;
    end if;
  end if;
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'committee_members') then
    if exists (select 1 from public.committee_members cm where lower(cm.committee_name) = 'bestuur' and cm.profile_id = auth.uid()) then
      update public.profiles set account_role = 'supporter' where id = p_profile_id;
      return;
    end if;
    if exists (select 1 from public.committee_members cm where lower(cm.committee_name) in ('technische-commissie', 'tc') and cm.profile_id = auth.uid()) then
      update public.profiles set account_role = 'supporter' where id = p_profile_id;
      return;
    end if;
  end if;

  raise exception 'Geen toegang';
end;
$$;

grant execute on function public.set_profile_account_role_supporter(uuid) to authenticated;

create or replace function public.trg_sync_profile_role_from_team_members()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op in ('INSERT', 'UPDATE') then
    perform public.refresh_profile_account_role(new.profile_id);
  end if;
  if tg_op in ('DELETE', 'UPDATE') then
    perform public.refresh_profile_account_role(old.profile_id);
  end if;
  return null;
end;
$$;

drop trigger if exists sync_profile_role_from_team_members on public.team_members;
create trigger sync_profile_role_from_team_members
after insert or update or delete on public.team_members
for each row execute function public.trg_sync_profile_role_from_team_members();

do $$
begin
  if to_regclass('public.account_links') is not null then
    execute $q$
      create or replace function public.trg_sync_profile_role_from_account_links()
      returns trigger
      language plpgsql
      security definer
      set search_path = public
      as $f$
      begin
        if tg_op in ('INSERT', 'UPDATE') then
          perform public.refresh_profile_account_role(new.parent_id);
        end if;
        if tg_op in ('DELETE', 'UPDATE') then
          perform public.refresh_profile_account_role(old.parent_id);
        end if;
        return null;
      end;
      $f$;
    $q$;

    execute 'drop trigger if exists sync_profile_role_from_account_links on public.account_links';
    execute 'create trigger sync_profile_role_from_account_links after insert or update or delete on public.account_links for each row execute function public.trg_sync_profile_role_from_account_links()';
  end if;
end $$;

-- Backfill current profiles.
do $$
declare
  r record;
begin
  for r in select id from public.profiles loop
    perform public.refresh_profile_account_role(r.id);
  end loop;
end $$;
