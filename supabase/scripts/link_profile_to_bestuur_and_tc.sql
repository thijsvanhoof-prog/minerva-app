-- Koppel een profiel aan Bestuur en Technische Commissie (TC).
-- Voer uit in Supabase → SQL Editor (als bestuur/admin ingelogd, of met service role).
-- Profile_id: df99c456-726b-4cf6-84c6-2c60414d1e2b

insert into public.committee_members (profile_id, committee_name)
values
  ('df99c456-726b-4cf6-84c6-2c60414d1e2b'::uuid, 'bestuur'),
  ('df99c456-726b-4cf6-84c6-2c60414d1e2b'::uuid, 'technische-commissie');
