-- Fix Storage policies voor bucket `news-images`: update/delete alleen voor nieuwsbeheerders.
-- Probleem: update/delete stonden open voor elke ingelogde gebruiker (alleen bucket_id-check).
--
-- Uitvoeren in Supabase Dashboard → SQL Editor (volledige run, niet gedeeltelijk).
-- Idempotent: veilig om opnieuw te draaien.
--
-- Laat ONGEMOEID:
--   - "news-images public read"
--   - "news-images authenticated upload"
--
-- Vereist: public.is_global_admin() en public.is_bestuur() (bijv. force_content_rls_bestuur.sql).

-- ---------------------------------------------------------------------------
-- 1) Verwijder ALLE bekende te ruime update/delete policies (EERST)
-- ---------------------------------------------------------------------------
drop policy if exists "news-images authenticated update" on storage.objects;
drop policy if exists "news-images authenticated delete" on storage.objects;
drop policy if exists "news-images authenticated delete own" on storage.objects;
drop policy if exists "news-images content managers update" on storage.objects;
drop policy if exists "news-images content managers delete" on storage.objects;

-- ---------------------------------------------------------------------------
-- 2) Helper voor nieuwsbeheer (zelfde logica als home_news_rls_fix.sql)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 3) Nieuwe restrictieve policies
-- ---------------------------------------------------------------------------
create policy "news-images content managers update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'news-images'
    and coalesce(public.can_manage_home_news(), false)
  )
  with check (
    bucket_id = 'news-images'
    and coalesce(public.can_manage_home_news(), false)
  );

create policy "news-images content managers delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'news-images'
    and coalesce(public.can_manage_home_news(), false)
  );

-- ---------------------------------------------------------------------------
-- 4) Controle: actieve policies voor news-images
-- ---------------------------------------------------------------------------
select
  policyname,
  cmd,
  qual::text as using_expr,
  with_check::text as with_check_expr
from pg_policies
where schemaname = 'storage'
  and tablename = 'objects'
  and (
    policyname ilike '%news-images%'
    or qual::text ilike '%news-images%'
    or with_check::text ilike '%news-images%'
  )
order by policyname, cmd;

select pg_notify('pgrst', 'reload schema');
