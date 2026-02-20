-- TC (Technische Commissie) mag teams toevoegen en beheren.
-- Voer uit in Supabase SQL Editor.
--
-- Vereist: committee_members tabel met technische-commissie leden.

drop policy if exists "teams_manage_admins" on public.teams;

-- Global admins kunnen alles.
create policy "teams_manage_admins"
on public.teams
for all
to authenticated
using (coalesce(public.is_global_admin(), false) is true)
with check (coalesce(public.is_global_admin(), false) is true);

-- TC-leden mogen ook teams beheren (insert, update, delete).
create policy "teams_manage_tc"
on public.teams
for all
to authenticated
using (
  exists (
    select 1 from public.committee_members cm
    where lower(cm.committee_name) in ('technische-commissie', 'tc')
      and cm.profile_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.committee_members cm
    where lower(cm.committee_name) in ('technische-commissie', 'tc')
      and cm.profile_id = auth.uid()
  )
);
