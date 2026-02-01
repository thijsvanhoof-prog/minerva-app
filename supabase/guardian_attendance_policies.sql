-- Ouder/verzorger: aanwezigheid beheren voor gekoppeld account
--
-- This extends RLS policies so a parent (account_links.parent_id) may:
-- - see sessions for teams where the linked child is a member
-- - upsert/delete attendance rows for the linked child (attendance.person_id)
-- - upsert/delete match_availability rows for the linked child (match_availability.profile_id)
--
-- Prerequisites:
-- - Option B linking schema installed (account_links table exists)
-- - sessions_rls.sql (or equivalent) already run to enable RLS on sessions/attendance
--
-- Run this in Supabase SQL Editor.

-- Helper: guardian relation
create or replace function public.is_guardian_of(target_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.account_links l
    where l.parent_id = auth.uid()
      and l.child_id = target_profile_id
  );
$$;

grant execute on function public.is_guardian_of(uuid) to authenticated;

-- Sessions: allow selecting sessions for teams where YOU are a member OR your linked child is a member.
drop policy if exists "sessions_select_own_teams" on public.sessions;
create policy "sessions_select_own_teams"
on public.sessions
for select
to authenticated
using (
  exists (
    select 1
    from public.team_members tm
    where tm.team_id = public.sessions.team_id
      and (
        tm.profile_id = auth.uid()
        or public.is_guardian_of(tm.profile_id)
      )
  )
);

-- Attendance: broaden select to the same rule (viewer must be in the team OR guardian of someone in the team).
drop policy if exists "attendance_select_own_teams" on public.attendance;
create policy "attendance_select_own_teams"
on public.attendance
for select
to authenticated
using (
  exists (
    select 1
    from public.sessions s
    join public.team_members tm on tm.team_id = s.team_id
    where s.session_id = public.attendance.session_id
      and (
        tm.profile_id = auth.uid()
        or public.is_guardian_of(tm.profile_id)
      )
  )
);

-- Attendance insert: allow self OR guardian writing for linked child, but only when that person is a member of that session's team.
drop policy if exists "attendance_upsert_self" on public.attendance;
create policy "attendance_upsert_self"
on public.attendance
for insert
to authenticated
with check (
  (
    public.attendance.person_id = auth.uid()
    or public.is_guardian_of(public.attendance.person_id)
  )
  and exists (
    select 1
    from public.sessions s
    join public.team_members tm on tm.team_id = s.team_id
    where s.session_id = public.attendance.session_id
      and tm.profile_id = public.attendance.person_id
  )
);

-- Attendance update/delete: allow self OR guardian on that person_id.
drop policy if exists "attendance_update_self" on public.attendance;
create policy "attendance_update_self"
on public.attendance
for update
to authenticated
using (
  public.attendance.person_id = auth.uid()
  or public.is_guardian_of(public.attendance.person_id)
)
with check (
  public.attendance.person_id = auth.uid()
  or public.is_guardian_of(public.attendance.person_id)
);

drop policy if exists "attendance_delete_self" on public.attendance;
create policy "attendance_delete_self"
on public.attendance
for delete
to authenticated
using (
  public.attendance.person_id = auth.uid()
  or public.is_guardian_of(public.attendance.person_id)
);

-- Match availability: allow guardian to write for linked child.
drop policy if exists "match_availability_insert_own" on public.match_availability;
create policy "match_availability_insert_own"
on public.match_availability for insert to authenticated
with check (
  profile_id = auth.uid()
  or public.is_guardian_of(profile_id)
);

drop policy if exists "match_availability_update_own" on public.match_availability;
create policy "match_availability_update_own"
on public.match_availability for update to authenticated
using (
  profile_id = auth.uid()
  or public.is_guardian_of(profile_id)
)
with check (
  profile_id = auth.uid()
  or public.is_guardian_of(profile_id)
);

drop policy if exists "match_availability_delete_own" on public.match_availability;
create policy "match_availability_delete_own"
on public.match_availability for delete to authenticated
using (
  profile_id = auth.uid()
  or public.is_guardian_of(profile_id)
);

