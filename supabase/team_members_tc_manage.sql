-- Team members: TC-leden mogen alle teamleden zien + rol aanpassen.
-- Doel:
-- - Alle TC-leden (technische-commissie / tc) kunnen team_members lezen, toevoegen, wijzigen, verwijderen.
-- - Global admins behouden volledige toegang.
-- - Coaches/trainers behouden team-specifieke toegang.
--
-- Run in Supabase SQL Editor.

alter table if exists public.team_members enable row level security;

-- Helper: is current user TC-lid?
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

-- Helper: central manage check for team_members rows
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

-- Replace select policy so TC kan alle teamleden zien
drop policy if exists "team_members_select_own_or_manage" on public.team_members;
create policy "team_members_select_own_or_manage"
on public.team_members
for select
to authenticated
using (
  profile_id = auth.uid()
  or public.can_manage_team_members(team_id)
);

-- Manage policies for insert/update/delete
drop policy if exists "team_members_insert_manage" on public.team_members;
create policy "team_members_insert_manage"
on public.team_members
for insert
to authenticated
with check (public.can_manage_team_members(team_id));

drop policy if exists "team_members_update_manage" on public.team_members;
create policy "team_members_update_manage"
on public.team_members
for update
to authenticated
using (public.can_manage_team_members(team_id))
with check (public.can_manage_team_members(team_id));

drop policy if exists "team_members_delete_manage" on public.team_members;
create policy "team_members_delete_manage"
on public.team_members
for delete
to authenticated
using (public.can_manage_team_members(team_id));

