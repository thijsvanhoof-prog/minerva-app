-- Lijst profile_ids die in minstens één commissie zitten (voor TC-tab: "zonder team én zonder commissie").
-- Alleen aanroepbaar door TC, bestuur of global admin.
-- Voer uit in Supabase SQL Editor.

create or replace function public.get_committee_member_profile_ids()
returns table(profile_id uuid)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if exists (select 1 from pg_proc p join pg_namespace n on p.pronamespace = n.oid where n.nspname = 'public' and p.proname = 'is_global_admin') then
    if public.is_global_admin() then
      return query select distinct cm.profile_id from public.committee_members cm;
      return;
    end if;
  end if;

  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'committee_members') then
    if exists (
      select 1 from public.committee_members cm
      where lower(cm.committee_name) = 'bestuur' and cm.profile_id = auth.uid()
    ) then
      return query select distinct cm.profile_id from public.committee_members cm;
      return;
    end if;
    if exists (
      select 1 from public.committee_members cm
      where lower(cm.committee_name) in ('technische-commissie', 'tc') and cm.profile_id = auth.uid()
    ) then
      return query select distinct cm.profile_id from public.committee_members cm;
      return;
    end if;
  end if;

  raise exception 'Geen toegang';
end;
$$;

grant execute on function public.get_committee_member_profile_ids() to authenticated;
