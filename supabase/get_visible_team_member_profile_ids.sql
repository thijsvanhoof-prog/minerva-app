-- RPC: teamleden ophalen voor "Niet gereageerd" bij trainingen/wedstrijden.
--
-- Waarom:
--   Gewone spelers mogen via RLS op team_members vaak niet alle teamleden lezen.
--   Daardoor kan de app wel aangemelde/afgemelde rijen tonen, maar niet altijd
--   de volledige lijst "Niet gereageerd".
--
-- Deze security-definer RPC geeft alleen profile_ids terug voor teams die de
-- ingelogde gebruiker zelf mag zien:
--   - global admin
--   - gebruiker is zelf lid van het team
--   - gebruiker mag teamleden beheren voor dat team
--   - gebruiker is ouder/verzorger van iemand in dat team
--
-- Run in Supabase SQL Editor.

create or replace function public.get_visible_team_member_profile_ids(p_team_ids bigint[])
returns table (
  team_id bigint,
  profile_id uuid
)
language sql
stable
security definer
set search_path = public
as $$
  select distinct
    tm.team_id,
    tm.profile_id
  from public.team_members tm
  where tm.team_id = any(p_team_ids)
    and (
      coalesce(public.is_global_admin(), false)
      or exists (
        select 1
        from public.team_members viewer
        where viewer.team_id = tm.team_id
          and viewer.profile_id = auth.uid()
      )
      or coalesce(public.can_manage_team_members(tm.team_id), false)
      or exists (
        select 1
        from public.team_members child_member
        where child_member.team_id = tm.team_id
          and coalesce(public.is_guardian_of(child_member.profile_id), false)
      )
    );
$$;

grant execute on function public.get_visible_team_member_profile_ids(bigint[]) to authenticated;

select pg_notify('pgrst', 'reload schema');
