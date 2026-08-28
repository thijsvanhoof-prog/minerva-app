-- Commissie power admin: alle commissierechten zonder global admin / Contact / alle teams.
--
-- Doel voor thijs@vvminerva.nl:
-- - Uit global_admins
-- - In committee_power_admins (NIET in committee_members)
-- - Alle commissie-RLS/helpers, maar geen teamzicht als global admin
--
-- Run in Supabase Dashboard → SQL Editor (idempotent).

-- ---------------------------------------------------------------------------
-- 1) Tabel committee_power_admins
-- ---------------------------------------------------------------------------
create table if not exists public.committee_power_admins (
  id uuid not null primary key references auth.users(id) on delete cascade
);

alter table public.committee_power_admins enable row level security;

drop policy if exists "committee_power_admins_select_own"
  on public.committee_power_admins;
create policy "committee_power_admins_select_own"
  on public.committee_power_admins
  for select
  to authenticated
  using (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- 2) Helper: is_committee_power_admin()
-- ---------------------------------------------------------------------------
create or replace function public.is_committee_power_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.committee_power_admins cpa
    where cpa.id = auth.uid()
  );
$$;

grant execute on function public.is_committee_power_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- 3) thijs@vvminerva.nl: power admin, geen global admin
-- ---------------------------------------------------------------------------
insert into public.committee_power_admins (id)
select au.id
from auth.users au
where lower(trim(au.email)) = lower('thijs@vvminerva.nl')
on conflict (id) do nothing;

delete from public.global_admins ga
where ga.id in (
  select au.id
  from auth.users au
  where lower(trim(au.email)) = lower('thijs@vvminerva.nl')
);

-- ---------------------------------------------------------------------------
-- 4) Commissie-beheer helpers (bestuur/admin checks)
-- ---------------------------------------------------------------------------
create or replace function public.is_bestuur_or_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.is_global_admin(), false) is true
    or coalesce(public.is_committee_power_admin(), false) is true
    or exists (
      select 1
      from public.committee_members cm
      where cm.profile_id = auth.uid()
        and (
          lower(trim(cm.committee_name)) = 'bestuur'
          or lower(trim(cm.committee_name)) like '%bestuur%'
        )
    );
$$;

grant execute on function public.is_bestuur_or_admin() to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Content / agenda helpers
-- ---------------------------------------------------------------------------
create or replace function public.can_manage_home_news()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.is_global_admin(), false)
  or coalesce(public.is_committee_power_admin(), false)
  or coalesce(public.is_bestuur(), false)
  or exists (
    select 1
    from public.committee_members cm
    where cm.profile_id = auth.uid()
      and (
        lower(trim(cm.committee_name)) = 'cc'
        or lower(trim(cm.committee_name)) like '%communicatie%'
      )
  );
$$;

grant execute on function public.can_manage_home_news() to authenticated;

create or replace function public.can_manage_home_agenda()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.is_global_admin(), false)
  or coalesce(public.is_committee_power_admin(), false)
  or coalesce(public.is_bestuur(), false)
  or exists (
    select 1
    from public.committee_members cm
    where cm.profile_id = auth.uid()
      and (
        lower(trim(cm.committee_name)) = 'cc'
        or lower(trim(cm.committee_name)) like '%communicatie%'
        or lower(trim(cm.committee_name)) = 'jeugd'
        or lower(trim(cm.committee_name)) like '%jeugd%'
        or lower(trim(cm.committee_name)) = 'ev'
        or lower(trim(cm.committee_name)) like '%evenement%'
      )
  );
$$;

grant execute on function public.can_manage_home_agenda() to authenticated;

create or replace function public.can_view_agenda_rsvps()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.is_global_admin(), false)
  or coalesce(public.is_committee_power_admin(), false)
  or coalesce(public.is_bestuur(), false)
  or exists (
    select 1
    from public.committee_members cm
    where cm.profile_id = auth.uid()
      and (
        lower(trim(cm.committee_name)) = 'cc'
        or lower(trim(cm.committee_name)) like '%communicatie%'
        or lower(trim(cm.committee_name)) = 'jeugd'
        or lower(trim(cm.committee_name)) like '%jeugd%'
        or lower(trim(cm.committee_name)) = 'ev'
        or lower(trim(cm.committee_name)) like '%evenement%'
      )
  );
$$;

grant execute on function public.can_view_agenda_rsvps() to authenticated;

create or replace function public.can_manage_highlights()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.is_global_admin(), false)
  or coalesce(public.is_committee_power_admin(), false)
  or exists (
    select 1
    from public.committee_members cm
    where cm.profile_id = auth.uid()
      and lower(coalesce(cm.committee_name, '')) like '%bestuur%'
  )
  or public.is_communicatie();
$$;

grant execute on function public.can_manage_highlights() to authenticated;

-- ---------------------------------------------------------------------------
-- 6) Wedstrijden / taken helpers
-- ---------------------------------------------------------------------------
create or replace function public.can_manage_match_links()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_global_admin()
    or public.is_committee_power_admin()
    or public.is_bestuur()
    or public.is_wedstrijdzaken();
$$;

grant execute on function public.can_manage_match_links() to authenticated;

create or replace function public.can_manage_club_tasks()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.is_global_admin(), false)
  or coalesce(public.is_committee_power_admin(), false)
  or coalesce(public.is_bestuur(), false)
  or coalesce(public.is_wedstrijdzaken(), false);
$$;

grant execute on function public.can_manage_club_tasks() to authenticated;

-- ---------------------------------------------------------------------------
-- 7) TC / teams helpers — committee power admin krijgt GEEN automatisch teambeheer.
--     Zie fix_committee_power_admin_limit_team_rights.sql indien eerder per ongeluk
--     teams_manage_committee_power_admin / is_tc_member(power admin) gedraaid is.
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

-- Geen teams_manage_committee_power_admin policy (power admin ≠ alle teams beheren).
drop policy if exists "teams_manage_committee_power_admin" on public.teams;

-- match_cancellations: bestuur + power admin
drop policy if exists "match_cancellations_manage_bestuur" on public.match_cancellations;
create policy "match_cancellations_manage_bestuur"
on public.match_cancellations
for all
to authenticated
using (
  public.is_global_admin()
  or public.is_committee_power_admin()
  or exists (
    select 1
    from public.committee_members cm
    where lower(cm.committee_name) = 'bestuur'
      and cm.profile_id = auth.uid()
  )
)
with check (
  public.is_global_admin()
  or public.is_committee_power_admin()
  or exists (
    select 1
    from public.committee_members cm
    where lower(cm.committee_name) = 'bestuur'
      and cm.profile_id = auth.uid()
  )
);

-- club_tasks: wedstrijdzaken/bestuur/power admin (niet alleen global admin)
drop policy if exists "club_tasks_admin_all" on public.club_tasks;
create policy "club_tasks_admin_all"
on public.club_tasks
for all
to authenticated
using (public.can_manage_club_tasks())
with check (public.can_manage_club_tasks());

drop policy if exists "club_task_team_assignments_admin_all" on public.club_task_team_assignments;
create policy "club_task_team_assignments_admin_all"
on public.club_task_team_assignments
for all
to authenticated
using (public.can_manage_club_tasks())
with check (public.can_manage_club_tasks());

drop policy if exists "club_task_signups_admin_all" on public.club_task_signups;
create policy "club_task_signups_admin_all"
on public.club_task_signups
for all
to authenticated
using (public.can_manage_club_tasks())
with check (public.can_manage_club_tasks());

-- committee_contact_settings: commissie-contact beheer
drop policy if exists "committee_contact_settings_manage_bestuur"
  on public.committee_contact_settings;
create policy "committee_contact_settings_manage_bestuur"
  on public.committee_contact_settings
  for all
  to authenticated
  using (
    coalesce(public.is_global_admin(), false)
    or coalesce(public.is_committee_power_admin(), false)
    or coalesce(public.is_bestuur(), false)
    or exists (
      select 1
      from public.committee_members cm
      where cm.profile_id = auth.uid()
        and lower(trim(cm.committee_name)) like '%bestuur%'
    )
  )
  with check (
    coalesce(public.is_global_admin(), false)
    or coalesce(public.is_committee_power_admin(), false)
    or coalesce(public.is_bestuur(), false)
    or exists (
      select 1
      from public.committee_members cm
      where cm.profile_id = auth.uid()
        and lower(trim(cm.committee_name)) like '%bestuur%'
    )
  );

-- ---------------------------------------------------------------------------
-- 8) RPC's voor profiellijsten (canViewAllAccounts)
-- ---------------------------------------------------------------------------
create or replace function public.list_profiles_for_committee_management()
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

  if coalesce(public.is_global_admin(), false)
     or coalesce(public.is_committee_power_admin(), false) then
    return query select * from public._list_all_profiles();
    return;
  end if;

  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'committee_members') then
    if exists (
      select 1 from public.committee_members cm
      where lower(cm.committee_name) = 'bestuur'
        and cm.profile_id = auth.uid()
    ) then
      return query select * from public._list_all_profiles();
      return;
    end if;
  end if;

  raise exception 'Geen toegang';
end;
$$;

grant execute on function public.list_profiles_for_committee_management() to authenticated;

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

  if coalesce(public.is_global_admin(), false)
     or coalesce(public.is_committee_power_admin(), false) then
    return query select * from public._list_all_profiles();
    return;
  end if;

  if exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'committee_members') then
    if exists (
      select 1 from public.committee_members cm
      where lower(cm.committee_name) = 'bestuur' and cm.profile_id = auth.uid()
    ) then
      return query select * from public._list_all_profiles();
      return;
    end if;
    if exists (
      select 1 from public.committee_members cm
      where lower(cm.committee_name) in ('technische-commissie', 'tc') and cm.profile_id = auth.uid()
    ) then
      return query select * from public._list_all_profiles();
      return;
    end if;
  end if;

  raise exception 'Geen toegang';
end;
$$;

grant execute on function public.get_profiles_for_tc() to authenticated;

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

  if coalesce(public.is_global_admin(), false)
     or coalesce(public.is_committee_power_admin(), false) then
    return query select distinct cm.profile_id from public.committee_members cm;
    return;
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

-- ensure_training_groups_for_tc: global admin, bestuur of echte TC (geen power admin)
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
    if not exists (select 1 from public.committee_members cm where lower(cm.committee_name) = 'bestuur' and cm.profile_id = auth.uid())
       and not exists (select 1 from public.committee_members cm where lower(cm.committee_name) in ('technische-commissie', 'tc') and cm.profile_id = auth.uid()) then
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
-- NIET aangepast (bewust):
-- - get_my_team_ids() / get_my_committees() / get_committee_members_with_names()
--   → geen committee power admin (geen alle teams, geen Contact-lijst)
-- ---------------------------------------------------------------------------

select pg_notify('pgrst', 'reload schema');
