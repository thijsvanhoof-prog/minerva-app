-- RPC: teamnamen (+ optioneel nevobo_code) ophalen voor een lijst team_ids (SECURITY DEFINER).
-- Handig als de profielpagina anders alleen "Team 1", "Team 2" ziet.
-- nevobo_code wordt o.a. gebruikt voor Standen/Wedstrijden-codes in de app.
-- Uitvoeren in Supabase SQL Editor.

-- Zorg dat kolom bestaat (zo niet, voer teams_nevobo_sync.sql uit voor volledige sync-setup).
alter table public.teams add column if not exists nevobo_code text;

-- Returntype wijzigen (extra kolom nevobo_code) kan niet met CREATE OR REPLACE; eerst droppen.
drop function if exists public.get_team_names_for_app(bigint[]);

create or replace function public.get_team_names_for_app(p_team_ids bigint[])
returns table(team_id bigint, team_name text, nevobo_code text)
language sql
stable
security definer
set search_path = public
as $$
  select t.team_id, t.team_name, t.nevobo_code
  from public.teams t
  where t.team_id = any(p_team_ids);
$$;

-- Vereiste: kolom nevobo_code op teams (uit teams_nevobo_sync.sql). Bestaat die nog niet,
-- voer dan eerst dat script uit. Anders: verwijder nevobo_code uit de select en returns hierboven.

-- Als je tabel teams een andere pk/naam heeft (bijv. id i.p.v. team_id), pas dan aan:
-- where t.id = any(p_team_ids) en return table(id bigint, team_name text, nevobo_code text).

grant execute on function public.get_team_names_for_app(bigint[]) to authenticated;
