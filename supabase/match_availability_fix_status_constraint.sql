-- Fix: "violates check constraint match_availability_status_check"
-- Voer dit uit in Supabase SQL Editor als je "Kon status niet opslaan" krijgt
-- met PostgrestException / match_availability_status_check bij Sport → Wedstrijden.
--
-- De app stuurt 'playing' (speler) en 'coach' (trainer/coach). De constraint
-- moet beide toestaan.

alter table public.match_availability
  drop constraint if exists match_availability_status_check;

alter table public.match_availability
  add constraint match_availability_status_check
  check (status in ('playing', 'not_playing', 'coach'));
