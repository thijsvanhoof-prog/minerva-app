-- Global admin: toegang tot alle trainingen (sessions) en aanwezigheid (attendance).
-- Bewaart ook ouder/verzorger-toegang: is_guardian_of() (guardian_attendance_policies.sql) moet bestaan.
-- Voer uit na sessions_rls.sql en bij voorkeur na guardian_attendance_policies.sql.

-- Sessions: admin mag alles zien; anders eigen teams of teams van gekoppeld kind (ouder).
drop policy if exists "sessions_select_own_teams" on public.sessions;
create policy "sessions_select_own_teams"
on public.sessions
for select
to authenticated
using (
  public.is_global_admin()
  or exists (
    select 1
    from public.team_members tm
    where tm.team_id = public.sessions.team_id
      and (
        tm.profile_id = auth.uid()
        or public.is_guardian_of(tm.profile_id)
      )
  )
);

drop policy if exists "sessions_write_manage_teams" on public.sessions;
create policy "sessions_write_manage_teams"
on public.sessions
for all
to authenticated
using (
  public.is_global_admin()
  or exists (
    select 1
    from public.team_members tm
    where tm.profile_id = auth.uid()
      and tm.team_id = public.sessions.team_id
      and lower(coalesce(tm.role, '')) in ('trainer','coach')
  )
)
with check (
  public.is_global_admin()
  or exists (
    select 1
    from public.team_members tm
    where tm.profile_id = auth.uid()
      and tm.team_id = public.sessions.team_id
      and lower(coalesce(tm.role, '')) in ('trainer','coach')
  )
);

-- Attendance: admin mag alles zien; anders eigen teams of teams van gekoppeld kind (ouder).
drop policy if exists "attendance_select_own_teams" on public.attendance;
create policy "attendance_select_own_teams"
on public.attendance
for select
to authenticated
using (
  public.is_global_admin()
  or exists (
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
