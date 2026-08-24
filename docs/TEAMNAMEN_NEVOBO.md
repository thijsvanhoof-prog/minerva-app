# Teamnamen en Nevobo-teamcodes

De app gebruikt **teamnamen** uit de tabel `public.teams` om o.a. op het tabblad **Wedstrijden** een Nevobo-teamcode (zoals HS1, DS1) af te leiden. Als de naam niet herkend wordt, zie je "Team 1", "Team 2" en de melding dat er geen Nevobo-code kon worden afgeleid.

## Wat moet er in `teams` staan?

- **Kolom** (vaak `team_name` of `name`): een herkenbare naam of code.
- **Waarden** die werken: **"Heren 1"**, **"HS1"**, **"Dames 1"**, **"DS1"**, **"Jongens B 1"**, **"JB1"**, **"Meiden B 1"**, **"MB1"**, en vergelijkbare varianten (met of zonder spatie/nummer).
- **Waarden die niet werken:** alleen "Team 1", "Team 2" – daaruit leidt de app geen Nevobo-code af.

## Controleren en aanpassen

1. In Supabase **Table Editor** → **teams**: bekijk de kolom die de naam/code bevat (bijv. `team_name`).
2. Zet daar herkenbare namen neer, bijv.:
   - `Heren 1` of `HS1`
   - `Dames 1` of `DS1`
   - `Jongens B 1` of `JB1`
   - `Meiden B 1` of `MB1`
3. Zorg dat **team_members.team_id** naar de juiste rij in **teams** verwijst (zelfde id als in `teams.team_id` of `teams.id`).

Na het aanpassen: in de app **Opnieuw laden** op het tabblad Wedstrijden, of opnieuw inloggen zodat de gekoppelde teams met de nieuwe namen worden geladen.

## Tabblad Standen

Op het tabblad **Standen** laadt de app **alle** teams uit de tabel `teams` (gefilterd op seizoen). Er is geen filter op de ingelogde gebruiker: iedereen ziet dezelfde lijst teams, programma’s, uitslagen en standen.
