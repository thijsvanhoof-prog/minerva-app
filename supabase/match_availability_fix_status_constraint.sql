-- Fix: "violates check constraint match_availability_status_check"
-- Voer dit uit in Supabase SQL Editor als je "Kon status niet opslaan" krijgt
-- met PostgrestException / match_availability_status_check bij Sport → Wedstrijden.
--
-- De app stuurt 'playing' (speler), 'not_playing', 'coach' (trainer/coach)
-- en 'afgemeld'. De constraint moet alle vier toestaan.

alter table public.match_availability
  drop constraint if exists match_availability_status_check;

alter table public.match_availability
  add constraint match_availability_status_check
  check (status in ('playing', 'not_playing', 'coach', 'afgemeld'));
