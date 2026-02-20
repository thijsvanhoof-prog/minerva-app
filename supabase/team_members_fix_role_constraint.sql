-- Fix: "violates check constraint team_members_role_check"
-- Voer dit uit in Supabase SQL Editor als je "Bijwerken mislukt" krijgt
-- met PostgrestException / team_members_role_check bij Commissie → TC.
--
-- De app stuurt 'player', 'trainer', 'trainingslid' en 'supporter'. De constraint
-- moet al deze rollen toestaan.

alter table public.team_members
  drop constraint if exists team_members_role_check;

alter table public.team_members
  add constraint team_members_role_check
  check (role is null or role in ('player', 'speler', 'trainer', 'coach', 'trainingslid', 'supporter'));
