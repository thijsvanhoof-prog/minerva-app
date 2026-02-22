-- Eenmalige cleanup: verwijder alle rijen die verwijzen naar een account dat niet meer bestaat.
-- Gebruik dit als er "Onbekend" in commissies/teams/aanwezigheid blijft staan na een verwijderd account.
--
-- Voer uit in Supabase SQL Editor (eenmalig of wanneer je weesrijen wilt opruimen).

do $$
begin
  -- Commissies: verwijder lidmaatschappen waar het account niet meer bestaat
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'committee_members') then
    delete from public.committee_members cm
    where not exists (select 1 from auth.users u where u.id = cm.profile_id);
  end if;

  -- Teamleden
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'team_members') then
    delete from public.team_members tm
    where not exists (select 1 from auth.users u where u.id = tm.profile_id);
  end if;

  -- Aanwezigheid
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'attendance') then
    delete from public.attendance a
    where not exists (select 1 from auth.users u where u.id = a.person_id);
  end if;

  -- Account-link requests (een van de partijen bestaat niet meer)
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'account_link_requests') then
    delete from public.account_link_requests alr
    where not exists (select 1 from auth.users u where u.id = alr.requested_by)
       or not exists (select 1 from auth.users u where u.id = alr.recipient_id)
       or not exists (select 1 from auth.users u where u.id = alr.parent_id)
       or not exists (select 1 from auth.users u where u.id = alr.child_id);
  end if;

  -- Account links
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'account_links') then
    delete from public.account_links al
    where not exists (select 1 from auth.users u where u.id = al.parent_id)
       or not exists (select 1 from auth.users u where u.id = al.child_id);
  end if;

  -- Account link codes
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'account_link_codes') then
    delete from public.account_link_codes alc
    where not exists (select 1 from auth.users u where u.id = alc.profile_id);
  end if;

  -- Push-tokens en notificatievoorkeuren (zouden normaal al weg zijn door CASCADE)
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'push_tokens') then
    delete from public.push_tokens pt
    where not exists (select 1 from auth.users u where u.id = pt.user_id);
  end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'notification_preferences') then
    delete from public.notification_preferences np
    where not exists (select 1 from auth.users u where u.id = np.user_id);
  end if;

  -- Agenda-RSVPs
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'home_agenda_rsvps') then
    delete from public.home_agenda_rsvps har
    where not exists (select 1 from auth.users u where u.id = har.profile_id);
  end if;

  -- Wedstrijdbeschikbaarheid
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'match_availability') then
    delete from public.match_availability ma
    where not exists (select 1 from auth.users u where u.id = ma.profile_id);
  end if;

  -- Aanmeldingen verenigingstaken
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'club_task_signups') then
    delete from public.club_task_signups cts
    where not exists (select 1 from auth.users u where u.id = cts.profile_id);
  end if;
end
$$;
