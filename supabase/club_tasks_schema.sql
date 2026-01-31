-- Club tasks (verenigingstaken) schema for Minerva app
--
-- Tables:
-- - club_tasks: the task itself
-- - club_task_team_assignments: which teams the task is assigned to
-- - club_task_signups: which users signed up for a task
--
-- NOTE: Run this in Supabase SQL editor.

create table if not exists public.club_tasks (
  task_id bigserial primary key,
  title text not null,
  type text not null default 'taak',
  required boolean not null default false,
  starts_at timestamptz null,
  ends_at timestamptz null,
  location text null,
  notes text null,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_club_tasks_starts_at on public.club_tasks(starts_at);

create table if not exists public.club_task_team_assignments (
  assignment_id bigserial primary key,
  task_id bigint not null references public.club_tasks(task_id) on delete cascade,
  team_id bigint not null,
  assigned_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(task_id, team_id)
);

create index if not exists idx_club_task_team_assignments_task_id
  on public.club_task_team_assignments(task_id);
create index if not exists idx_club_task_team_assignments_team_id
  on public.club_task_team_assignments(team_id);

create table if not exists public.club_task_signups (
  signup_id bigserial primary key,
  task_id bigint not null references public.club_tasks(task_id) on delete cascade,
  profile_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(task_id, profile_id)
);

create index if not exists idx_club_task_signups_task_id
  on public.club_task_signups(task_id);
create index if not exists idx_club_task_signups_profile_id
  on public.club_task_signups(profile_id);

-- ----------------------------
-- RLS (basic)
-- ----------------------------
alter table public.club_tasks enable row level security;
alter table public.club_task_team_assignments enable row level security;
alter table public.club_task_signups enable row level security;

-- Read access (authenticated)
drop policy if exists "club_tasks_select_auth" on public.club_tasks;
create policy "club_tasks_select_auth"
on public.club_tasks
for select
to authenticated
using (true);

drop policy if exists "club_task_team_assignments_select_auth" on public.club_task_team_assignments;
create policy "club_task_team_assignments_select_auth"
on public.club_task_team_assignments
for select
to authenticated
using (true);

drop policy if exists "club_task_signups_select_auth" on public.club_task_signups;
create policy "club_task_signups_select_auth"
on public.club_task_signups
for select
to authenticated
using (true);

-- Signups: users manage their own signup rows
drop policy if exists "club_task_signups_insert_own" on public.club_task_signups;
create policy "club_task_signups_insert_own"
on public.club_task_signups
for insert
to authenticated
with check (profile_id = auth.uid());

drop policy if exists "club_task_signups_delete_own" on public.club_task_signups;
create policy "club_task_signups_delete_own"
on public.club_task_signups
for delete
to authenticated
using (profile_id = auth.uid());

-- ----------------------------
-- Admin rights (global admins)
-- ----------------------------
-- This assumes you already have a function `public.is_global_admin()` (used by the app).
-- Global admins can create/update/delete tasks, manage assignments, and manage signups.

drop policy if exists "club_tasks_admin_all" on public.club_tasks;
create policy "club_tasks_admin_all"
on public.club_tasks
for all
to authenticated
using (public.is_global_admin())
with check (public.is_global_admin());

drop policy if exists "club_task_team_assignments_admin_all" on public.club_task_team_assignments;
create policy "club_task_team_assignments_admin_all"
on public.club_task_team_assignments
for all
to authenticated
using (public.is_global_admin())
with check (public.is_global_admin());

drop policy if exists "club_task_signups_admin_all" on public.club_task_signups;
create policy "club_task_signups_admin_all"
on public.club_task_signups
for all
to authenticated
using (public.is_global_admin())
with check (public.is_global_admin());

