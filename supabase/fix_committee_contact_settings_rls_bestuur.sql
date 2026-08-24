-- Fix RLS voor public.committee_contact_settings
-- Probleem: policy accepteerde alleen committee_name = 'bestuur' (exact),
-- terwijl de app ook varianten als "Bestuur Minerva" en "Algemeen bestuur" als bestuur behandelt.
--
-- Uitvoeren in Supabase Dashboard → SQL Editor.
-- Idempotent: veilig om opnieuw te draaien.
--
-- Vereist:
--   - public.committee_contact_settings
--   - public.committee_members
--   - public.is_global_admin()
--   - public.is_bestuur()

-- 1) Verwijder bestaande beheer-policy (indien aanwezig)
drop policy if exists "committee_contact_settings_manage_bestuur"
  on public.committee_contact_settings;

-- 2) Nieuwe beheer-policy met uitgebreide bestuur-detectie
create policy "committee_contact_settings_manage_bestuur"
  on public.committee_contact_settings
  for all
  to authenticated
  using (
    coalesce(public.is_global_admin(), false)
    or coalesce(public.is_bestuur(), false)
    or exists (
      select 1
      from public.committee_members cm
      where cm.profile_id = auth.uid()
        and lower(trim(cm.committee_name)) like '%bestuur%'
    )
  )
  with check (
    coalesce(public.is_global_admin(), false)
    or coalesce(public.is_bestuur(), false)
    or exists (
      select 1
      from public.committee_members cm
      where cm.profile_id = auth.uid()
        and lower(trim(cm.committee_name)) like '%bestuur%'
    )
  );

-- 3) PostgREST schema reload
select pg_notify('pgrst', 'reload schema');
