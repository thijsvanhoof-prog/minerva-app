-- Wedstrijd-annuleringen (Bestuur → Wedstrijden)
--
-- Zonder deze tabel krijg je "Could not find the table 'public.match_cancellations'"
-- bij het annuleren van een wedstrijd in Commissie → Bestuur → Wedstrijden.
-- De annulering is alleen zichtbaar in de app, niet gekoppeld aan Nevobo.
--
-- match_key formaat: "nevobo_match:<TEAMCODE>:<START_UTC_ISO>"
--
-- Voer uit in Supabase Dashboard → SQL Editor → Run.

create table if not exists public.match_cancellations (
  match_key text primary key,
  team_code text null,
  starts_at timestamptz null,
  summary text null,
  location text null,

  is_cancelled boolean not null default true,
  reason text null,

  updated_by uuid null references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists idx_match_cancellations_team_code
  on public.match_cancellations(team_code);
create index if not exists idx_match_cancellations_starts_at
  on public.match_cancellations(starts_at);

do $$
begin
  if exists (select 1 from pg_proc where proname = 'set_updated_at') then
    drop trigger if exists trg_match_cancellations_updated_at on public.match_cancellations;
    create trigger trg_match_cancellations_updated_at
    before update on public.match_cancellations
    for each row
    execute function public.set_updated_at();
  end if;
end $$;

alter table public.match_cancellations enable row level security;

drop policy if exists "match_cancellations_select_auth" on public.match_cancellations;
create policy "match_cancellations_select_auth"
on public.match_cancellations for select to authenticated
using (true);

-- Beheer: ingelogde gebruikers (app toont knop alleen aan bestuur)
drop policy if exists "match_cancellations_manage" on public.match_cancellations;
create policy "match_cancellations_manage"
on public.match_cancellations for all to authenticated
using (true)
with check (true);
