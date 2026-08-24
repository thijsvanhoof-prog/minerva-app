-- RLS-fix: home_agenda (en RSVPs, signup options) mag door global admin, Bestuur en Communicatie.
-- Voer uit in Supabase → SQL Editor. Vereist: is_global_admin(), is_bestuur(), committee_members.

-- Helper: mag agenda beheren (zelfde rechten als nieuws: admin, bestuur, communicatie).
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
        lower(trim(cm.committee_name)) = 'cc'
        or lower(trim(cm.committee_name)) like '%communicatie%'
      )
  );
$$;

grant execute on function public.can_manage_home_agenda() to authenticated;

-- home_agenda: beheer door admin, bestuur of communicatie
drop policy if exists "home_agenda_admin_all" on public.home_agenda;
create policy "home_agenda_admin_all"
on public.home_agenda
for all
to authenticated
using (public.can_manage_home_agenda())
with check (public.can_manage_home_agenda());

-- home_agenda_rsvps: idem (o.a. voor beheer/export aanmeldingen)
drop policy if exists "home_agenda_rsvps_admin_all" on public.home_agenda_rsvps;
create policy "home_agenda_rsvps_admin_all"
on public.home_agenda_rsvps
for all
to authenticated
using (public.can_manage_home_agenda())
with check (public.can_manage_home_agenda());

-- home_agenda_signup_options: idem (aanmeldopties per activiteit)
drop policy if exists "home_agenda_signup_options_admin" on public.home_agenda_signup_options;
create policy "home_agenda_signup_options_admin"
on public.home_agenda_signup_options
for all
to authenticated
using (public.can_manage_home_agenda())
with check (public.can_manage_home_agenda());
