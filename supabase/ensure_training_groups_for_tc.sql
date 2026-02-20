-- Zorg dat Volleystars en Recreanten (niet competitie) bestaan in teams (voor TC teambeheer).
-- TC, bestuur en admins kunnen deze RPC aanroepen; daarna verschijnen de groepen in de teamlijst.
-- Voer uit in Supabase SQL Editor. Vereist: teams met team_name (unique), evt. training_only.

create or replace function public.ensure_training_groups_for_tc()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- Toegang: global admin, bestuur of TC
  if exists (select 1 from pg_proc p join pg_namespace n on p.pronamespace = n.oid where n.nspname = 'public' and p.proname = 'is_global_admin') then
    if public.is_global_admin() then
      null;
    elsif exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'committee_members') then
      if not exists (select 1 from public.committee_members cm where lower(cm.committee_name) = 'bestuur' and cm.profile_id = auth.uid())
         and not exists (select 1 from public.committee_members cm where lower(cm.committee_name) in ('technische-commissie', 'tc') and cm.profile_id = auth.uid()) then
        raise exception 'Geen toegang';
      end if;
    else
      raise exception 'Geen toegang';
    end if;
  else
    raise exception 'Geen toegang';
  end if;

  -- Insert Volleystars en Recreanten (niet competitie) als ze nog niet bestaan
  insert into public.teams (team_name, training_only)
  values
    ('Volleystars', true),
    ('Recreanten (niet competitie)', true)
  on conflict (team_name) do update set training_only = true;

  -- Legacy naam harmoniseren als de nieuwe naam nog niet bestaat.
  if exists (select 1 from public.teams where lower(team_name) = 'recreanten trainingsgroep')
     and not exists (select 1 from public.teams where lower(team_name) = 'recreanten (niet competitie)') then
    update public.teams
    set team_name = 'Recreanten (niet competitie)'
    where lower(team_name) = 'recreanten trainingsgroep';
  end if;
exception
  when undefined_column then
    -- Kolom training_only bestaat niet (oud schema): alleen team_name
    insert into public.teams (team_name)
    values ('Volleystars'), ('Recreanten (niet competitie)')
    on conflict (team_name) do nothing;
end;
$$;

grant execute on function public.ensure_training_groups_for_tc() to authenticated;
