-- Alles-in-één: zorg dat bestuur (en communicatie) nieuws en agenda kunnen beheren.
-- Voer dit uit in Supabase → SQL Editor. Daarna opnieuw inloggen of app herstarten.
-- Vereist: is_global_admin(), committee_members-tabel.

-- 1) is_bestuur() (nodig voor can_manage_*)
create or replace function public.is_bestuur()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.committee_members cm
    where cm.profile_id = auth.uid()
      and (
        lower(trim(cm.committee_name)) = 'bestuur'
        or lower(trim(cm.committee_name)) like '%bestuur%'
      )
  );
$$;
grant execute on function public.is_bestuur() to authenticated;

-- 2) Helpers: wie mag content beheren (admin, bestuur, communicatie)
create or replace function public.can_manage_home_news()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.is_global_admin(), false)
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

create or replace function public.can_manage_home_agenda()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.is_global_admin(), false)
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
grant execute on function public.can_manage_home_agenda() to authenticated;

-- 3) home_news: alle mogelijke write-policies droppen en opnieuw met can_manage_home_news()
drop policy if exists "home_news_insert_auth" on public.home_news;
drop policy if exists "home_news_update_auth" on public.home_news;
drop policy if exists "home_news_delete_auth" on public.home_news;
drop policy if exists "home_news_insert_admin" on public.home_news;
drop policy if exists "home_news_update_admin" on public.home_news;
drop policy if exists "home_news_delete_admin" on public.home_news;

create policy "home_news_insert_admin"
  on public.home_news for insert to authenticated
  with check (public.can_manage_home_news());
create policy "home_news_update_admin"
  on public.home_news for update to authenticated
  using (public.can_manage_home_news())
  with check (public.can_manage_home_news());
create policy "home_news_delete_admin"
  on public.home_news for delete to authenticated
  using (public.can_manage_home_news());

-- 4) home_agenda + home_agenda_rsvps + home_agenda_signup_options
drop policy if exists "home_agenda_admin_all" on public.home_agenda;
create policy "home_agenda_admin_all"
  on public.home_agenda for all to authenticated
  using (public.can_manage_home_agenda())
  with check (public.can_manage_home_agenda());

drop policy if exists "home_agenda_rsvps_admin_all" on public.home_agenda_rsvps;
create policy "home_agenda_rsvps_admin_all"
  on public.home_agenda_rsvps for all to authenticated
  using (public.can_manage_home_agenda())
  with check (public.can_manage_home_agenda());

drop policy if exists "home_agenda_signup_options_admin" on public.home_agenda_signup_options;
create policy "home_agenda_signup_options_admin"
  on public.home_agenda_signup_options for all to authenticated
  using (public.can_manage_home_agenda())
  with check (public.can_manage_home_agenda());
