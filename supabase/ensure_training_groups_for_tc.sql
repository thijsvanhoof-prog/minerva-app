-- Zorg dat Volleystars en Recreanten (niet competitie) bestaan in teams (voor TC teambeheer).
-- TC, bestuur en admins kunnen deze RPC aanroepen; daarna verschijnen de groepen in de teamlijst.
-- Voer uit in Supabase SQL Editor. Vereist: teams met team_name (unique), evt. training_only.

create or replace function public.ensure_training_groups_for_tc()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_has_training_only boolean;
  v_has_season boolean;
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

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'teams'
      and column_name = 'training_only'
  ) into v_has_training_only;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'teams'
      and column_name = 'season'
  ) into v_has_season;

  -- Sommige schema's hebben season NOT NULL. Neem dan een bestaande season over.
  if v_has_season and not exists (select 1 from public.teams where season is not null) then
    raise exception 'Kolom season is verplicht, maar er is geen bestaande season-waarde in teams.';
  end if;

  if v_has_season and v_has_training_only then
    insert into public.teams (team_name, training_only, season)
    select 'Volleystars', true, s.season
    from (select season from public.teams where season is not null limit 1) s
    where not exists (select 1 from public.teams where lower(team_name) = 'volleystars');

    insert into public.teams (team_name, training_only, season)
    select 'Recreanten (niet competitie)', true, s.season
    from (select season from public.teams where season is not null limit 1) s
    where not exists (
      select 1 from public.teams where lower(team_name) = 'recreanten (niet competitie)'
    );
  elsif v_has_season then
    insert into public.teams (team_name, season)
    select 'Volleystars', s.season
    from (select season from public.teams where season is not null limit 1) s
    where not exists (select 1 from public.teams where lower(team_name) = 'volleystars');

    insert into public.teams (team_name, season)
    select 'Recreanten (niet competitie)', s.season
    from (select season from public.teams where season is not null limit 1) s
    where not exists (
      select 1 from public.teams where lower(team_name) = 'recreanten (niet competitie)'
    );
  elsif v_has_training_only then
    insert into public.teams (team_name, training_only)
    select 'Volleystars', true
    where not exists (select 1 from public.teams where lower(team_name) = 'volleystars');

    insert into public.teams (team_name, training_only)
    select 'Recreanten (niet competitie)', true
    where not exists (
      select 1 from public.teams where lower(team_name) = 'recreanten (niet competitie)'
    );
  else
    insert into public.teams (team_name)
    select 'Volleystars'
    where not exists (select 1 from public.teams where lower(team_name) = 'volleystars');

    insert into public.teams (team_name)
    select 'Recreanten (niet competitie)'
    where not exists (
      select 1 from public.teams where lower(team_name) = 'recreanten (niet competitie)'
    );
  end if;

  -- Als training_only bestaat, zorg dat beide groepen op true staan.
  if v_has_training_only then
    update public.teams
    set training_only = true
    where lower(team_name) in ('volleystars', 'recreanten (niet competitie)', 'recreanten trainingsgroep');
  end if;

  -- Legacy naam harmoniseren als de nieuwe naam nog niet bestaat.
  if exists (select 1 from public.teams where lower(team_name) = 'recreanten trainingsgroep')
     and not exists (select 1 from public.teams where lower(team_name) = 'recreanten (niet competitie)') then
    update public.teams
    set team_name = 'Recreanten (niet competitie)'
    where lower(team_name) = 'recreanten trainingsgroep';
  end if;
end;
$$;

grant execute on function public.ensure_training_groups_for_tc() to authenticated;
