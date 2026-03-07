-- RPC: team_ids van de ingelogde gebruiker (SECURITY DEFINER = ongeacht RLS op team_members).
-- Global admin: retourneert alle team_ids. Anders: alleen teams waar de gebruiker lid van is.
-- Voer uit in Supabase SQL Editor.

create or replace function public.get_my_team_ids()
returns table(team_id bigint)
language sql
stable
security definer
set search_path = public
as $$
  select distinct x.team_id
  from (
    select t.team_id from public.teams t where public.is_global_admin()
    union
    select tm.team_id from public.team_members tm
    where not coalesce(public.is_global_admin(), false) and tm.profile_id = auth.uid()
  ) x
  order by 1;
$$;

grant execute on function public.get_my_team_ids() to authenticated;
