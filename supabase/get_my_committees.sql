-- RPC: commissies van de ingelogde gebruiker (SECURITY DEFINER = ongeacht RLS op committee_members).
-- Gebruikt in profiel en bootstrap zodat commissies altijd zichtbaar zijn.
-- Voer uit in Supabase SQL Editor.

create or replace function public.get_my_committees()
returns table(committee_name text)
language sql
stable
security definer
set search_path = public
as $$
  select distinct cm.committee_name::text
  from public.committee_members cm
  where cm.profile_id = auth.uid()
  order by 1;
$$;

grant execute on function public.get_my_committees() to authenticated;
