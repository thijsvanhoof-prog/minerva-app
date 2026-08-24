-- Fix Supabase Database Linter: RLS inschakelen op public-tabellen
-- Uitvoeren in Supabase Dashboard → SQL Editor.
-- Zie: https://supabase.com/docs/guides/database/database-linter

-- 1) Tabellen die al policies hebben maar RLS stond uit: alleen RLS aanzetten
alter table if exists public.global_roles enable row level security;
alter table if exists public.profiles enable row level security;

-- 2) team_members: RLS + policy (bestand team_members_rls.sql)
alter table if exists public.team_members enable row level security;
drop policy if exists "team_members_select_own_or_manage" on public.team_members;
create policy "team_members_select_own_or_manage"
  on public.team_members for select to authenticated
  using (
    profile_id = auth.uid()
    or coalesce(public.is_global_admin(), false) is true
    or exists (
      select 1 from public.team_members me
      where me.profile_id = auth.uid()
        and me.team_id = public.team_members.team_id
        and lower(coalesce(me.role, '')) in ('trainer','coach')
    )
  );

-- 3) Overige public-tabellen: RLS aan + minimale policy (authenticated mag lezen)
--    Zo blijft de app werken; schrijf-rechten eventueel later verfijnen.

alter table if exists public.committees enable row level security;
drop policy if exists "committees_select_authenticated" on public.committees;
create policy "committees_select_authenticated"
  on public.committees for select to authenticated using (true);

alter table if exists public.permissions enable row level security;
drop policy if exists "permissions_select_authenticated" on public.permissions;
create policy "permissions_select_authenticated"
  on public.permissions for select to authenticated using (true);

alter table if exists public.home_news_backup enable row level security;
drop policy if exists "home_news_backup_select_authenticated" on public.home_news_backup;
create policy "home_news_backup_select_authenticated"
  on public.home_news_backup for select to authenticated using (true);

alter table if exists public.committee_members enable row level security;
drop policy if exists "committee_members_select_authenticated" on public.committee_members;
drop policy if exists "committee_members_all_authenticated" on public.committee_members;
-- App (bestuur) leest en schrijft direct op committee_members
create policy "committee_members_all_authenticated"
  on public.committee_members for all to authenticated using (true) with check (true);

alter table if exists public.referee_tasks enable row level security;
drop policy if exists "referee_tasks_select_authenticated" on public.referee_tasks;
create policy "referee_tasks_select_authenticated"
  on public.referee_tasks for select to authenticated using (true);

alter table if exists public.parent_child_links enable row level security;
drop policy if exists "parent_child_links_select_authenticated" on public.parent_child_links;
create policy "parent_child_links_select_authenticated"
  on public.parent_child_links for select to authenticated using (true);

alter table if exists public.club_matches enable row level security;
drop policy if exists "club_matches_select_authenticated" on public.club_matches;
create policy "club_matches_select_authenticated"
  on public.club_matches for select to authenticated using (true);

alter table if exists public.club_match_rsvps enable row level security;
drop policy if exists "club_match_rsvps_select_authenticated" on public.club_match_rsvps;
create policy "club_match_rsvps_select_authenticated"
  on public.club_match_rsvps for select to authenticated using (true);

alter table if exists public.profile_link_codes enable row level security;
drop policy if exists "profile_link_codes_select_authenticated" on public.profile_link_codes;
create policy "profile_link_codes_select_authenticated"
  on public.profile_link_codes for select to authenticated using (true);
