-- Aanmeldopties per agenda-activiteit
--
-- Voeg dit toe na home_agenda_schema.sql.
-- Hiermee kun je per activiteit meerdere aanmeldopties hebben met eigen titel
-- (bijv. "Lunch deelnemen") en beperken tot bepaalde teams of commissies.
--
-- Run in Supabase SQL editor.

-- Eerst: optionele kolommen op home_agenda voor simpele use case (één optie met custom label + restrictie)
alter table public.home_agenda add column if not exists rsvp_label text null;
alter table public.home_agenda add column if not exists rsvp_allowed_team_ids bigint[] null;
alter table public.home_agenda add column if not exists rsvp_allowed_committee_keys text[] null;

-- Tabel voor meerdere aanmeldopties per agenda-item
create table if not exists public.home_agenda_signup_options (
  option_id bigserial primary key,
  agenda_id bigint not null references public.home_agenda(agenda_id) on delete cascade,
  label text not null,
  sort_order int not null default 0,
  allowed_team_ids bigint[] null,
  allowed_committee_keys text[] null,
  created_at timestamptz not null default now()
);

create index if not exists idx_home_agenda_signup_options_agenda_id
  on public.home_agenda_signup_options(agenda_id);

comment on column public.home_agenda_signup_options.label is 'Titel van de optie, bijv. "Lunch deelnemen" of "Vervoer"';
comment on column public.home_agenda_signup_options.allowed_team_ids is 'Alleen deze teams kunnen aanmelden. Null = iedereen met can_rsvp.';
comment on column public.home_agenda_signup_options.allowed_committee_keys is 'Alleen deze commissies kunnen aanmelden. Null = iedereen. Keys: bestuur, technische-commissie, communicatie, wedstrijdzaken, etc.';

-- Verwijder oude unique constraint (agenda_id, profile_id) zodat meerdere opties per agenda mogelijk zijn
alter table public.home_agenda_rsvps drop constraint if exists home_agenda_rsvps_agenda_id_profile_id_key;

-- Uitbreiden van home_agenda_rsvps voor meerdere opties
-- option_id null = legacy (oude can_rsvp zonder opties)
alter table public.home_agenda_rsvps
  add column if not exists option_id bigint null
  references public.home_agenda_signup_options(option_id) on delete cascade;

-- Unique: één aanmelding per gebruiker per optie (of legacy per agenda)
drop index if exists idx_home_agenda_rsvps_agenda_profile_option;
create unique index idx_home_agenda_rsvps_agenda_profile_option
  on public.home_agenda_rsvps(agenda_id, profile_id, coalesce(option_id, 0));

-- RLS voor signup options (iedereen mag lezen)
alter table public.home_agenda_signup_options enable row level security;

drop policy if exists "home_agenda_signup_options_select" on public.home_agenda_signup_options;
create policy "home_agenda_signup_options_select"
on public.home_agenda_signup_options for select to authenticated using (true);

drop policy if exists "home_agenda_signup_options_admin" on public.home_agenda_signup_options;
create policy "home_agenda_signup_options_admin"
on public.home_agenda_signup_options for all to authenticated
using (public.is_global_admin())
with check (public.is_global_admin());
