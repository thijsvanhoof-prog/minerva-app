-- RLS-fix: Jeugd en Evenementen mogen aanmeldingen op agenda-items kunnen zien
-- (naast admin, bestuur en communicatie die dat via can_manage_home_agenda() al mogen).
--
-- Context:
--   Tot dusver gebruikte de SELECT-policy op home_agenda_rsvps alleen
--   "profile_id = auth.uid()" (eigen rijen) + can_manage_home_agenda() (admin/
--   bestuur/communicatie). Jeugd- en Evenementen-leden zagen daardoor 0
--   aanmeldingen voor activiteiten waar ze zelf niet aangemeld waren.
--
-- Deze migratie:
--   1) Voegt helper can_view_agenda_rsvps() toe (admin, bestuur, communicatie,
--      jeugd, evenementen) — matched via LIKE zodat "Jeugd commissie",
--      "Evenementen-commissie", "Bestuur Minerva" etc. ook tellen.
--   2) Voegt een aparte SELECT-policy toe op home_agenda_rsvps die die functie
--      gebruikt.
--   3) Raakt de write-policy (can_manage_home_agenda) expres NIET aan: alleen
--      kijken, niet aanpassen of exporteren — dat blijft bij admin/bestuur/cc.
--
-- Vereist: is_global_admin(), is_bestuur(), committee_members.
-- Run in Supabase → SQL Editor. Daarna niet opnieuw inloggen nodig.

create or replace function public.can_view_agenda_rsvps()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.is_global_admin(), false)
  or coalesce(public.is_bestuur(), false)
  or exists (
    select 1
    from public.committee_members cm
    where cm.profile_id = auth.uid()
      and (
        -- Communicatie
        lower(trim(cm.committee_name)) = 'cc'
        or lower(trim(cm.committee_name)) like '%communicatie%'
        -- Jeugd (vangt "Jeugd", "Jeugdcommissie", "Jeugd commissie", "Jeugd-commissie")
        or lower(trim(cm.committee_name)) = 'jeugd'
        or lower(trim(cm.committee_name)) like '%jeugd%'
        -- Evenementen (vangt "Evenementen", "Evenementen-commissie", "EV")
        or lower(trim(cm.committee_name)) = 'ev'
        or lower(trim(cm.committee_name)) like '%evenement%'
      )
  );
$$;

grant execute on function public.can_view_agenda_rsvps() to authenticated;

-- Aparte SELECT-policy voor bekijken van RSVP-rijen door commissieleden.
drop policy if exists "home_agenda_rsvps_select_committees"
  on public.home_agenda_rsvps;
create policy "home_agenda_rsvps_select_committees"
on public.home_agenda_rsvps
for select
to authenticated
using (public.can_view_agenda_rsvps());

-- Zelf-check (optioneel — run los om te verifiëren voor een specifieke user)
-- select public.can_view_agenda_rsvps();
