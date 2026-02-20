# Nevobo API’s – standen en resultaten

De app gebruikt alleen **publieke** endpoints van `https://api.nevobo.nl` (geen auth).

## Standen

| Doel | Endpoint | Gebruik |
|------|----------|--------|
| Poule van een team | `GET /competitie/pouleindelingen?team={teamPath}` | Bepalen in welke poule een team zit. `teamPath` = bijv. `/competitie/teams/ckm0v2o/heren/1`. |
| Standen in een poule | `GET /competitie/pouleindelingen?poule={poulePath}` | Standen (posities, punten, gespeeld) voor die poule. |
| Teamnaam uit IRI | `GET https://api.nevobo.nl{teamPath}` | Als een stand een team-URL geeft, wordt die opgehaald voor de weergavenaam. |

Code: `NevoboApi.fetchStandingsForTeam()` in `lib/ui/trainingen_wedstrijden/nevobo_api.dart`.

---

## Wedstrijden / resultaten

| Doel | Endpoint | Gebruik |
|------|----------|--------|
| ICS-kalender (programma) | `GET https://api.nevobo.nl/export/team/{clubId}/{category}/{number}/wedstrijden.ics` | Lijst wedstrijden (datum, tijd, tegenstander). Geen uitslagen. |
| Wedstrijden + uitslagen (JSON) | `GET /competitie/wedstrijden?team={teamPath}` | Officiële competitie-API: wedstrijden met o.a. `eindstand`, `volledigeUitslag`, `status`. |

Code:
- `fetchMatchesForTeam()` – gebruikt de ICS-export (probeert meerdere categorieën).
- `fetchMatchesForTeamViaCompetitionApi()` – gebruikt het wedstrijden-JSON-endpoint.

---

## Waar de teamlijst vandaan komt (Standen-tab)

De **lijst teams** (welke teams je op Standen ziet) komt **niet** van de Nevobo API, maar uit **Supabase**:

- Tabel: `public.teams` (kolommen o.a. `team_id`, `team_name`, `nevobo_code`, `training_only`).
- De app haalt die lijst op via:
  1. RPC **`get_all_teams_for_app()`** (aanbevolen; SECURITY DEFINER, dus ongeacht RLS), of
  2. Directe `SELECT` op `teams` (kan 0 rijen geven door RLS).

Als je maar 4 teams ziet, geeft de directe SELECT waarschijnlijk 0 rijen. Voer dan het script **`supabase/get_all_teams_for_app.sql`** uit; daarna gebruikt de app de RPC en zouden alle teams zichtbaar moeten zijn.

Per team worden daarna **standen** en **wedstrijden** opgehaald via de Nevobo-endpoints hierboven.
