-- Restrict team membership visibility.
--
-- Run this in Supabase SQL Editor.
--
-- Goal:
-- - Normal users can only see their own team memberships.
-- - Coaches/trainers can also see members for teams they manage.
-- - Global admins can see all rows (via public.is_global_admin()).

alter table if exists public.team_members enable row level security;

drop policy if exists "team_members_select_own_or_manage" on public.team_members;
create policy "team_members_select_own_or_manage"
on public.team_members
for select
to authenticated
using (
  profile_id = auth.uid()
  or coalesce(public.is_global_admin(), false) is true
  or exists (
    select 1
    from public.team_members me
    where me.profile_id = auth.uid()
      and me.team_id = public.team_members.team_id
      and lower(coalesce(me.role, '')) in ('trainer','coach')
  )
);

