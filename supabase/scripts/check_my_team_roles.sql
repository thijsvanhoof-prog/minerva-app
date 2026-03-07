-- Controleer bij welke teams je staat en met welke rol.
-- Voer uit in Supabase → SQL Editor.
-- Let op: in de SQL Editor ben je vaak ingelogd als database-gebruiker (postgres), niet als app-gebruiker.
-- Dan is auth.uid() null en geeft deze query 0 rijen. Gebruik onderstaande diagnostiek om te zien wat er speelt.

-- 1) Wie is "nu" ingelogd? (null = je draait als postgres/database, niet als app-user)
SELECT auth.uid() AS current_user_id;

-- 2) Jouw team-koppelingen (alleen zichtbaar als auth.uid() niet null is)
SELECT tm.team_id, t.team_name, tm.role
FROM public.team_members tm
LEFT JOIN public.teams t ON t.team_id = tm.team_id
WHERE tm.profile_id = auth.uid()
ORDER BY t.team_name;

-- 3) Optioneel: totaal aantal koppelingen in de tabel (zodat je ziet of er überhaupt data is)
-- SELECT count(*) AS totaal_team_members FROM public.team_members;
