-- Cascade cleanup bij accountverwijdering: verwijder gebruiker overal (commissies,
-- teams, aanwezigheid, agenda-RSVPs, taken, account-koppelingen, push, profiel, auth).
--
-- Gebruikt door: admin_delete_user(target_user_id) en delete_my_account().
-- Voer uit in Supabase SQL Editor (bij voorkeur vóór admin_delete_user_rpc en delete_my_account_rpc).

create or replace function public._cascade_delete_user_data(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if p_user_id is null then
    return;
  end if;

  -- Commissies: lidmaatschap verwijderen
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'committee_members') then
    delete from public.committee_members where profile_id = p_user_id;
  end if;

  -- Teamleden
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'team_members') then
    delete from public.team_members where profile_id = p_user_id;
  end if;

  -- Aanwezigheid (trainings/sessies)
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'attendance') then
    delete from public.attendance where person_id = p_user_id;
  end if;

  -- Account-koppelingen (ouder/kind): eerst requests, dan links, dan codes
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'account_link_requests') then
    delete from public.account_link_requests
    where requested_by = p_user_id or recipient_id = p_user_id or parent_id = p_user_id or child_id = p_user_id;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'account_links') then
    delete from public.account_links where parent_id = p_user_id or child_id = p_user_id;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'account_link_codes') then
    delete from public.account_link_codes where profile_id = p_user_id;
  end if;

  -- Push-tokens en notificatievoorkeuren
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'push_tokens') then
    delete from public.push_tokens where user_id = p_user_id;
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'notification_preferences') then
    delete from public.notification_preferences where user_id = p_user_id;
  end if;

  -- Agenda-aanmeldingen (RSVPs)
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'home_agenda_rsvps') then
    delete from public.home_agenda_rsvps where profile_id = p_user_id;
  end if;

  -- Wedstrijdbeschikbaarheid (match_availability)
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'match_availability') then
    delete from public.match_availability where profile_id = p_user_id;
  end if;

  -- Aanmeldingen verenigingstaken
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'club_task_signups') then
    delete from public.club_task_signups where profile_id = p_user_id;
  end if;

  -- Profiel
  delete from public.profiles where id = p_user_id;

  -- Auth-gebruiker (hierna bestaan geen FKs meer naar deze user)
  delete from auth.users where id = p_user_id;
end;
$$;

-- Alleen aanroepbaar vanuit andere SECURITY DEFINER functies of Edge Functions met service_role
revoke all on function public._cascade_delete_user_data(uuid) from public;
grant execute on function public._cascade_delete_user_data(uuid) to authenticated;
grant execute on function public._cascade_delete_user_data(uuid) to service_role;

comment on function public._cascade_delete_user_data(uuid) is
  'Internal: verwijdert alle data van een gebruiker (commissies, teams, aanwezigheid, RSVPs, taken, account-koppelingen, push, profiel, auth). Alleen aanroepen vanuit admin_delete_user of delete_my_account.';
