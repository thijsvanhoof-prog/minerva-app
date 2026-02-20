-- RPC: team_ids van de ingelogde gebruiker (SECURITY DEFINER = ongeacht RLS op team_members).
-- Gebruikt o.a. in Taken → Teamtaken zodat alle aan jouw teams gekoppelde taken zichtbaar zijn.
-- Voer uit in Supabase SQL Editor.

create or replace function public.get_my_team_ids()
returns table(team_id bigint)
language sql
stable
security definer
set search_path = public
as $$
  select distinct tm.team_id
  from public.team_members tm
  where tm.profile_id = auth.uid()
  order by 1;
$$;

grant execute on function public.get_my_team_ids() to authenticated;
