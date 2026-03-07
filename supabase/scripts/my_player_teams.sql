-- Teams waarbij jij als speler (role = 'player') bent toegevoegd.
-- profile_id = df99c456-726b-4cf6-84c6-2c60414d1e2b

SELECT tm.team_id, t.team_name, tm.role
FROM public.team_members tm
LEFT JOIN public.teams t ON t.team_id = tm.team_id
WHERE tm.profile_id = 'df99c456-726b-4cf6-84c6-2c60414d1e2b'::uuid
  AND lower(trim(coalesce(tm.role, ''))) = 'player'
ORDER BY t.team_name;

-- Optioneel: verwijder dubbele koppeling (als je 2x dezelfde team_id ziet, houdt één rij over)
-- DELETE FROM public.team_members a
-- USING public.team_members b
-- WHERE a.profile_id = b.profile_id AND a.team_id = b.team_id AND a.role = b.role
--   AND a.profile_id = 'df99c456-726b-4cf6-84c6-2c60414d1e2b'::uuid
--   AND a.ctid < b.ctid;
