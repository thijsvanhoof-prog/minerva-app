-- Voeg 'afgemeld' toe aan match_availability status constraint.
-- Bij afmelden wordt nu een rij met status 'afgemeld' opgeslagen i.p.v. verwijderen,
-- zodat de rode Afmelden-knop correct wordt getoond.

alter table public.match_availability
  drop constraint if exists match_availability_status_check;

alter table public.match_availability
  add constraint match_availability_status_check
  check (status in ('playing', 'not_playing', 'coach', 'afgemeld'));
