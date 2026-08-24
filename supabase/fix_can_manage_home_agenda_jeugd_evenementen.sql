-- RLS-fix: Jeugd- en Evenementencommissie mogen agenda-items beheren (CRUD).
--
-- Context:
--   De Flutter-app toont agenda-beheerknoppen voor jeugd/evenementen via
--   canManageAgenda. Supabase handhaaft writes via can_manage_home_agenda().
--   Tot dusver: global admin, bestuur, communicatie/cc.
--
-- Deze migratie:
--   1) Breidt can_manage_home_agenda() uit met jeugd- en evenementen-leden.
--   2) Raakt bestaande policies NIET aan (home_agenda_admin_all etc. roepen
--      can_manage_home_agenda() al aan).
--   3) Raakt can_view_agenda_rsvps(), can_manage_home_news() en
--      can_manage_highlights() NIET aan.
--
-- Vereist: is_global_admin(), is_bestuur(), committee_members.
-- Run in Supabase → SQL Editor.

create or replace function public.can_manage_home_agenda()
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

grant execute on function public.can_manage_home_agenda() to authenticated;

-- Optioneel: verifieer als ingelogde jeugd-/evenementen-testuser
-- select public.can_manage_home_agenda();

select pg_notify('pgrst', 'reload schema');
