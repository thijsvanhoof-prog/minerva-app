-- Voeg training_only toe aan teams.
-- Teams met training_only = true doen alleen mee met trainingen,
-- niet met standen of wedstrijden.
--
-- Voer uit in Supabase SQL Editor.

alter table public.teams
  add column if not exists training_only boolean not null default false;

comment on column public.teams.training_only is
  'True: team doet alleen mee met trainingen, niet met standen/wedstrijden.';
