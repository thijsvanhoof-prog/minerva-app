-- Lijst profielen voor TC-tab (Teambeheer: leden zonder team, lid toevoegen aan team).
-- Zonder deze RPC ziet TC alleen het eigen profiel door RLS op profiles.
-- Toegang: technische commissie, bestuur of global admin.
-- Voer uit in Supabase SQL Editor. Vereist: committee_list_profiles_rpc.sql (voor _list_all_profiles).
-- Bij wijziging return type: eerst droppen (PostgreSQL staat geen ander return type toe bij CREATE OR REPLACE).

drop function if exists public.get_profiles_for_tc();

create or replace function public.get_profiles_for_tc()
returns table (
  profile_id uuid,
  display_name text,
  email text,
  account_role text
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

  -- Global admin
  if exists (select 1 from pg_proc p join pg_namespace n on p.pronamespace = n.oid where n.nspname = 'public' and p.proname = 'is_global_admin') then
    if public.is_global_admin() then
      return query select * from public._list_all_profiles();
      return;
    end if;
  end if;

  -- Bestuur
  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'committee_members') then
    if exists (
      select 1 from public.committee_members cm
      where lower(cm.committee_name) = 'bestuur' and cm.profile_id = auth.uid()
    ) then
      return query select * from public._list_all_profiles();
      return;
    end if;
    -- Technische commissie
    if exists (
      select 1 from public.committee_members cm
      where (lower(cm.committee_name) in ('technische-commissie', 'tc')) and cm.profile_id = auth.uid()
    ) then
      return query select * from public._list_all_profiles();
      return;
    end if;
  end if;

  raise exception 'Geen toegang';
end;
$$;

grant execute on function public.get_profiles_for_tc() to authenticated;
