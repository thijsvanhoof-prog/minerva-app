-- Ensure every authenticated user can read ALL teams.
--
-- This is needed so the "Standen" tab can always show leaderboards for all teams,
-- even if a user is not linked to any team.
--
-- Run this in Supabase SQL Editor.

alter table if exists public.teams enable row level security;

-- RLS policies are OR'ed. This policy guarantees select access for all authenticated users.
drop policy if exists "teams_select_all_authenticated" on public.teams;
create policy "teams_select_all_authenticated"
on public.teams
for select
to authenticated
using (true);

