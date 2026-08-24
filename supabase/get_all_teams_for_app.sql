-- RPC: alle teams ophalen voor Standen/TC (SECURITY DEFINER = ongeacht RLS op teams).
-- p_include_training_only: true = alle teams (o.a. voor TC), false = alleen teams die niet alleen trainen (o.a. voor Standen).
-- Vereist: teams met team_id, team_name. Voor p_include_training_only = false: kolom training_only (zie teams_training_only.sql).
-- Uitvoeren in Supabase SQL Editor.

create or replace function public.get_all_teams_for_app(p_include_training_only boolean default true)
returns table(team_id bigint, team_name text)
language sql
stable
security definer
set search_path = public
as $$
  select t.team_id, t.team_name
  from public.teams t
  where p_include_training_only or coalesce(t.training_only, false) = false;
$$;

-- Als je tabel teams een andere pk heeft (bijv. id), pas dan team_id en return type aan.

grant execute on function public.get_all_teams_for_app(boolean) to authenticated;
