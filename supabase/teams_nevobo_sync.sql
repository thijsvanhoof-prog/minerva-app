-- Koppeling teams-tabel aan Nevobo API (standen, programma's, uitslagen).
-- Voegt nevobo_code toe en een RPC om teamnamen uit de API in Supabase bij te werken.
-- Voer uit in Supabase SQL Editor.

-- Kolom om een team te koppelen aan een Nevobo-teamcode (HS1, DS1, etc.)
alter table public.teams
  add column if not exists nevobo_code text;

-- Unieke constraint zodat we per code maximaal één rij hebben (null mag meerdere keren).
create unique index if not exists teams_nevobo_code_key
  on public.teams (nevobo_code)
  where nevobo_code is not null;

comment on column public.teams.nevobo_code is
  'Nevobo-teamcode (HS1, DS1, …); wordt o.a. bijgewerkt bij laden standen/programma''s.';

-- RPC: teamnaam en nevobo_code bijwerken vanuit de app (na ophalen standen/wedstrijden uit Nevobo API).
-- p_team_id: als bekend (uit teams-tabel), dan wordt die rij geüpdatet.
-- p_nevobo_code: bijv. HS1, DS1.
-- p_team_name: weergavenaam uit de API, bijv. "Minerva HS1".
create or replace function public.sync_team_name_from_nevobo(
  p_team_id bigint default null,
  p_nevobo_code text default null,
  p_team_name text default null
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_team_name text := trim(p_team_name);
  v_nevobo_code text := upper(trim(p_nevobo_code));
begin
  if coalesce(v_team_name, '') = '' or coalesce(v_nevobo_code, '') = '' then
    return;
  end if;

  if p_team_id is not null then
    update public.teams
    set team_name = v_team_name, nevobo_code = v_nevobo_code
    where team_id = p_team_id;
    return;
  end if;

  -- Geen team_id: probeer eerst bestaande rijen op code en daarna op naam.
  -- Dit vermijdt ON CONFLICT op een constraint die niet in iedere bestaande
  -- productie-installatie aanwezig is.
  update public.teams
  set team_name = v_team_name, nevobo_code = v_nevobo_code
  where upper(trim(coalesce(nevobo_code, ''))) = v_nevobo_code;

  if found then
    return;
  end if;

  update public.teams
  set team_name = v_team_name, nevobo_code = v_nevobo_code
  where lower(trim(team_name)) = lower(v_team_name);

  if not found then
    insert into public.teams (team_name, nevobo_code)
    values (v_team_name, v_nevobo_code);
  end if;
end;
$$;

grant execute on function public.sync_team_name_from_nevobo(bigint, text, text) to authenticated;
