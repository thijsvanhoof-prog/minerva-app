-- Lock down trainings (sessions) + attendance so users only see their own teams.
--
-- Run this in Supabase SQL Editor.
--
-- Assumptions:
-- - public.sessions has columns: session_id (pk), team_id (int), session_type (text)
-- - public.team_members has columns: team_id (int), profile_id (uuid), role (text)
-- - public.attendance has columns: session_id (int), person_id (uuid), status (text)

-- Sessions: enable RLS
alter table if exists public.sessions enable row level security;

drop policy if exists "sessions_select_own_teams" on public.sessions;
create policy "sessions_select_own_teams"
on public.sessions
for select
to authenticated
using (
  exists (
    select 1
    from public.team_members tm
    where tm.profile_id = auth.uid()
      and tm.team_id = public.sessions.team_id
  )
);

drop policy if exists "sessions_write_manage_teams" on public.sessions;
create policy "sessions_write_manage_teams"
on public.sessions
for all
to authenticated
using (
  exists (
    select 1
    from public.team_members tm
    where tm.profile_id = auth.uid()
      and tm.team_id = public.sessions.team_id
      and lower(coalesce(tm.role, '')) in ('trainer','coach')
  )
)
with check (
  exists (
    select 1
    from public.team_members tm
    where tm.profile_id = auth.uid()
      and tm.team_id = public.sessions.team_id
      and lower(coalesce(tm.role, '')) in ('trainer','coach')
  )
);

-- Attendance: enable RLS
alter table if exists public.attendance enable row level security;

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
      and tm.profile_id = auth.uid()
  )
);

drop policy if exists "attendance_upsert_self" on public.attendance;
create policy "attendance_upsert_self"
on public.attendance
for insert
to authenticated
with check (
  public.attendance.person_id = auth.uid()
  and exists (
    select 1
    from public.sessions s
    join public.team_members tm on tm.team_id = s.team_id
    where s.session_id = public.attendance.session_id
      and tm.profile_id = auth.uid()
  )
);

drop policy if exists "attendance_update_self" on public.attendance;
create policy "attendance_update_self"
on public.attendance
for update
to authenticated
using (public.attendance.person_id = auth.uid())
with check (public.attendance.person_id = auth.uid());

drop policy if exists "attendance_delete_self" on public.attendance;
create policy "attendance_delete_self"
on public.attendance
for delete
to authenticated
using (public.attendance.person_id = auth.uid());

