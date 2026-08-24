-- Ouder/verzorger: agenda-RSVP aanmelden voor zichzelf én voor gekoppelde kinderen (Fase E).
--
-- Vereiste: account_links + is_guardian_of (guardian_attendance_policies.sql).
-- Breidt home_agenda_rsvps RLS uit zodat een ouder:
-- - RSVP-rijen van gekoppelde kinderen mag zien (select)
-- - RSVP mag aanmaken voor een gekoppeld kind (insert)
-- - RSVP mag verwijderen voor een gekoppeld kind (delete)
--
-- Run in Supabase SQL Editor na home_agenda_schema.sql en guardian_attendance_policies.sql.

-- Select: eigen rijen + rijen van kinderen waarvan ik ouder ben
drop policy if exists "home_agenda_rsvps_select_guardian" on public.home_agenda_rsvps;
create policy "home_agenda_rsvps_select_guardian"
on public.home_agenda_rsvps
for select
to authenticated
using (public.is_guardian_of(profile_id));

-- Insert: mag ook voor een gekoppeld kind aanmelden
drop policy if exists "home_agenda_rsvps_insert_guardian" on public.home_agenda_rsvps;
create policy "home_agenda_rsvps_insert_guardian"
on public.home_agenda_rsvps
for insert
to authenticated
with check (public.is_guardian_of(profile_id));

-- Delete: mag ook aanmelding van een gekoppeld kind intrekken
drop policy if exists "home_agenda_rsvps_delete_guardian" on public.home_agenda_rsvps;
create policy "home_agenda_rsvps_delete_guardian"
on public.home_agenda_rsvps
for delete
to authenticated
using (public.is_guardian_of(profile_id));
