-- Voeg jezelf als speler toe aan een team (voor testen van de Spelers-tab).
-- Stap 1: bekijk de lijst teams en noteer een team_id (getal).
-- Stap 2: vervang hieronder 123 door dat team_id en voer de INSERT uit.

-- 1) Lijst van alle teams (kies een team_id)
SELECT team_id, team_name FROM public.teams ORDER BY team_name;

-- 2) Voeg jezelf als speler toe (vervang 123 door een echt team_id uit de lijst hierboven)
-- INSERT INTO public.team_members (profile_id, team_id, role)
-- VALUES ('df99c456-726b-4cf6-84c6-2c60414d1e2b'::uuid, 123, 'player')
-- ON CONFLICT DO NOTHING;
