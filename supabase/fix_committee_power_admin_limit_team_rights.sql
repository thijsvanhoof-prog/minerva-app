-- Limiteer committee power admin: geen automatisch teambeheer op alle teams.
--
-- Context:
--   fix_committee_power_admin_thijs.sql gaf power admin per ongeluk brede team-RLS
--   (teams_manage_committee_power_admin, is_tc_member(), ensure_training_groups_for_tc).
--
-- Dit script herstelt teamrechten naar TC/global admin/coach-regels.
-- Commissierechten, accountbeheer en Contact blijven ongemoeid.
--
-- Vereist: public.is_committee_power_admin() (fix_committee_power_admin_thijs.sql).
-- Run in Supabase SQL Editor (idempotent).

-- ---------------------------------------------------------------------------
-- 1) Verwijder brede teams-policy voor committee power admin
-- ---------------------------------------------------------------------------
drop policy if exists "teams_manage_committee_power_admin" on public.teams;

-- ---------------------------------------------------------------------------
-- 2) is_tc_member(): alleen echte TC-leden (committee_members), geen power admin
-- ---------------------------------------------------------------------------
create or replace function public.is_tc_member()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.committee_members cm
    where cm.profile_id = auth.uid()
      and lower(cm.committee_name) in ('technische-commissie', 'tc')
  );
$$;

grant execute on function public.is_tc_member() to authenticated;

-- ---------------------------------------------------------------------------
-- 3) can_manage_team_members(): geen power admin via is_tc_member()
--    (global admin, echte TC, coach/trainer per team)
-- ---------------------------------------------------------------------------
create or replace function public.can_manage_team_members(p_team_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.is_global_admin(), false) is true
    or public.is_tc_member()
    or coalesce(public.is_coach_or_trainer_for_team(p_team_id), false) is true;
$$;

grant execute on function public.can_manage_team_members(bigint) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) ensure_training_groups_for_tc(): geen power admin
-- ---------------------------------------------------------------------------
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

  if coalesce(public.is_global_admin(), false) then
    null;
  elsif exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'committee_members') then
    if not exists (
      select 1 from public.committee_members cm
      where lower(cm.committee_name) = 'bestuur' and cm.profile_id = auth.uid()
    ) and not exists (
      select 1 from public.committee_members cm
      where lower(cm.committee_name) in ('technische-commissie', 'tc') and cm.profile_id = auth.uid()
    ) then
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

  if v_has_training_only then
    update public.teams
    set training_only = true
    where lower(team_name) in ('volleystars', 'recreanten (niet competitie)', 'recreanten trainingsgroep');
  end if;

  if exists (select 1 from public.teams where lower(team_name) = 'recreanten trainingsgroep')
     and not exists (select 1 from public.teams where lower(team_name) = 'recreanten (niet competitie)') then
    update public.teams
    set team_name = 'Recreanten (niet competitie)'
    where lower(team_name) = 'recreanten trainingsgroep';
  end if;
end;
$$;

grant execute on function public.ensure_training_groups_for_tc() to authenticated;

-- ---------------------------------------------------------------------------
-- Bewust NIET gewijzigd (commissie/account, geen Contact/alle teams):
-- - is_committee_power_admin()
-- - can_manage_home_news/agenda, can_view_agenda_rsvps, can_manage_highlights
-- - can_manage_club_tasks, can_manage_match_links, is_bestuur_or_admin
-- - admin_list_profiles / admin_delete_user / admin_set_profile_display_name
-- - list_profiles_for_committee_management / get_profiles_for_tc
-- - get_my_team_ids(), get_my_committees(), get_committee_members_with_names()
-- ---------------------------------------------------------------------------

select pg_notify('pgrst', 'reload schema');
