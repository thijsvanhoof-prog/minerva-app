-- Uitbreiding agenda-aanmeldingen: custom titel + beperking tot teams/commissies
--
-- Voer uit na home_agenda_schema.sql.
-- Hiermee kun je o.a. "Lunch deelnemen" als knoptitel gebruiken en aanmelden
-- beperken tot bepaalde teams of commissies. Iedereen ziet de activiteit,
-- maar alleen de geselecteerde teams/commissies zien de aanmeldknop.
--
-- Run in Supabase SQL editor.

alter table public.home_agenda add column if not exists rsvp_label text null;
alter table public.home_agenda add column if not exists rsvp_allowed_team_ids bigint[] null;
alter table public.home_agenda add column if not exists rsvp_allowed_committee_keys text[] null;
