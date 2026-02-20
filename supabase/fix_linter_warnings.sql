-- Fix Supabase Database Linter-waarschuwingen
-- Uitvoeren in Supabase Dashboard → SQL Editor.
-- Zie: https://supabase.com/docs/guides/database/database-linter

-- =============================================================================
-- 1) Function search_path (lint 0011_function_search_path_mutable)
-- =============================================================================

-- set_updated_at: triggerfunctie zonder args
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on p.pronamespace = n.oid where n.nspname = 'public' and p.proname = 'set_updated_at') then
    execute 'alter function public.set_updated_at() set search_path = public';
  end if;
end $$;

-- handle_new_user (als die bestaat; anders handle_new_user_profile)
do $$
declare r record;
begin
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public' and p.proname in ('handle_new_user', 'handle_new_user_profile')
  loop
    execute format('alter function public.%I(%s) set search_path = public, auth', r.proname, r.args);
  end loop;
end $$;

-- is_team_member, has_team_role (signature onbekend; per naam aanpassen)
do $$
declare r record;
begin
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public' and p.proname in ('is_team_member', 'has_team_role')
  loop
    execute format('alter function public.%I(%s) set search_path = public', r.proname, r.args);
  end loop;
end $$;

-- =============================================================================
-- 2) RLS policy always true (lint 0024_permissive_rls_policy)
-- =============================================================================

-- committee_members: alleen global admin of bestuur mag schrijven
drop policy if exists "committee_members_all_authenticated" on public.committee_members;
create policy "committee_members_manage_bestuur"
  on public.committee_members for all to authenticated
  using (
    coalesce(public.is_global_admin(), false) is true
    or exists (
      select 1 from public.committee_members cm
      where cm.profile_id = auth.uid() and lower(coalesce(cm.committee_name, '')) = 'bestuur'
    )
  )
  with check (
    coalesce(public.is_global_admin(), false) is true
    or exists (
      select 1 from public.committee_members cm
      where cm.profile_id = auth.uid() and lower(coalesce(cm.committee_name, '')) = 'bestuur'
    )
  );

-- Leesrechten voor alle authenticated (anders ziet niemand de lijst)
drop policy if exists "committee_members_select_authenticated" on public.committee_members;
create policy "committee_members_select_authenticated"
  on public.committee_members for select to authenticated using (true);

-- home_highlights: permissive *_auth policies vervangen door rollen
drop policy if exists "home_highlights_insert_auth" on public.home_highlights;
drop policy if exists "home_highlights_update_auth" on public.home_highlights;
drop policy if exists "home_highlights_delete_auth" on public.home_highlights;

create or replace function public.is_communicatie()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.committee_members cm
    where cm.profile_id = auth.uid() and lower(coalesce(cm.committee_name, '')) like '%communicatie%'
  );
$$;

create or replace function public.can_manage_highlights()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.is_global_admin(), false)
    or exists (
      select 1 from public.committee_members cm
      where cm.profile_id = auth.uid() and lower(coalesce(cm.committee_name, '')) like '%bestuur%'
    )
    or public.is_communicatie();
$$;

drop policy if exists "home_highlights_insert_roles" on public.home_highlights;
drop policy if exists "home_highlights_update_roles" on public.home_highlights;
drop policy if exists "home_highlights_delete_roles" on public.home_highlights;
create policy "home_highlights_insert_roles"
  on public.home_highlights for insert to authenticated with check (public.can_manage_highlights());
create policy "home_highlights_update_roles"
  on public.home_highlights for update to authenticated
  using (public.can_manage_highlights()) with check (public.can_manage_highlights());
create policy "home_highlights_delete_roles"
  on public.home_highlights for delete to authenticated using (public.can_manage_highlights());

-- home_news: alleen global admin mag schrijven
drop policy if exists "home_news_insert_auth" on public.home_news;
drop policy if exists "home_news_update_auth" on public.home_news;
drop policy if exists "home_news_delete_auth" on public.home_news;

create policy "home_news_insert_admin"
  on public.home_news for insert to authenticated with check (coalesce(public.is_global_admin(), false));
create policy "home_news_update_admin"
  on public.home_news for update to authenticated
  using (coalesce(public.is_global_admin(), false)) with check (coalesce(public.is_global_admin(), false));
create policy "home_news_delete_admin"
  on public.home_news for delete to authenticated using (coalesce(public.is_global_admin(), false));

-- match_cancellations: permissive "manage" vervangen door bestuur-only
drop policy if exists "match_cancellations_manage" on public.match_cancellations;
drop policy if exists "match_cancellations_manage_bestuur" on public.match_cancellations;

create policy "match_cancellations_manage_bestuur"
  on public.match_cancellations for all to authenticated
  using (
    public.is_global_admin()
    or exists (
      select 1 from public.committee_members cm
      where lower(coalesce(cm.committee_name, '')) = 'bestuur' and cm.profile_id = auth.uid()
    )
  )
  with check (
    public.is_global_admin()
    or exists (
      select 1 from public.committee_members cm
      where lower(coalesce(cm.committee_name, '')) = 'bestuur' and cm.profile_id = auth.uid()
    )
  );

-- =============================================================================
-- 3) Leaked password protection (lint auth_leaked_password_protection)
-- =============================================================================
-- Dit stel je in via het Supabase-dashboard, niet via SQL:
-- Authentication → Settings → Password Protection → Enable "Leaked password protection"
-- (gebruikt HaveIBeenPwned om gelekt wachtwoorden te weigeren)
