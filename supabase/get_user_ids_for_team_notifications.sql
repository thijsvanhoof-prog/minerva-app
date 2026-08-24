-- RPC: user_ids die een push voor dit team moeten krijgen (spelers, trainers/coaches, ouders van spelers).
-- Gebruikt door Edge Function send-push-fcm voor team-specifieke meldingen.
-- Voer uit in Supabase SQL Editor.

create or replace function public.get_user_ids_for_team_notifications(p_team_id bigint)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  -- Leden van het team (speler, trainer, coach, etc.)
  select tm.profile_id
  from public.team_members tm
  where tm.team_id = p_team_id
  union
  -- Ouders/verzorgers van leden van het team
  select al.parent_id
  from public.account_links al
  where al.child_id in (
    select tm2.profile_id
    from public.team_members tm2
    where tm2.team_id = p_team_id
  );
$$;

comment on function public.get_user_ids_for_team_notifications(bigint) is
  'Returns user_ids (auth.uid) that should receive push for this team: members + parents of members.';

grant execute on function public.get_user_ids_for_team_notifications(bigint) to service_role;
grant execute on function public.get_user_ids_for_team_notifications(bigint) to authenticated;


-- Variant op nevobo_code (bijv. JC1, HS1) voor wedstrijden.
create or replace function public.get_user_ids_for_team_notifications_by_nevobo_code(p_nevobo_code text)
returns setof uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_team_id bigint;
begin
  select t.team_id into v_team_id
  from public.teams t
  where t.nevobo_code is not null
    and trim(upper(t.nevobo_code)) = trim(upper(p_nevobo_code))
  limit 1;
  if v_team_id is null then
    return;
  end if;
  return query
  select * from public.get_user_ids_for_team_notifications(v_team_id);
end;
$$;

comment on function public.get_user_ids_for_team_notifications_by_nevobo_code(text) is
  'Returns user_ids for push for the team matching this Nevobo code (e.g. JC1).';

grant execute on function public.get_user_ids_for_team_notifications_by_nevobo_code(text) to service_role;
grant execute on function public.get_user_ids_for_team_notifications_by_nevobo_code(text) to authenticated;
