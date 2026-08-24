-- RLS-fix: home_news mag door global admin, Communicatie en Bestuur.
-- Voer uit in Supabase → SQL Editor. Vereist: is_global_admin(), is_bestuur(), committee_members.

-- Helper: mag nieuws beheren (global admin, bestuur of commissie Communicatie/CC).
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

grant execute on function public.can_manage_home_news() to authenticated;

-- Vervang admin-only policies door admin + communicatie.
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
