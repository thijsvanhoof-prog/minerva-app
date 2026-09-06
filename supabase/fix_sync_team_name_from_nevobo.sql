-- Herstel de Nevobo-teamsynchronisatie voor bestaande Supabase-projecten.
-- Veilig om opnieuw uit te voeren.

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

revoke all on function public.sync_team_name_from_nevobo(bigint, text, text)
  from public, anon;
grant execute on function public.sync_team_name_from_nevobo(bigint, text, text)
  to authenticated;
