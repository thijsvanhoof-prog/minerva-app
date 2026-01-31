# Supabase-schema’s

Voer de SQL uit in **Supabase Dashboard → SQL Editor**.

## Home highlights (als de app meldt dat je ze moet toevoegen)

1. Open **Supabase Dashboard** → jouw project → **SQL Editor**.
2. Maak een nieuw query.
3. Kopieer de inhoud van `home_highlights_minimal.sql` en plak die in de editor.
4. Klik **Run**.

De melding in de app verdwijnt na een verversing. Je kunt daarna highlights toevoegen via de + knop op de homepagina.

**"column home_highlights.icon does not exist"?** Je hebt waarschijnlijk een oudere tabel zonder `icon`. Voer `home_highlights_minimal.sql` **opnieuw** uit; het script voegt de ontbrekende kolom toe.

Voor **rolgebaseerde toegang** (alleen bestuur/communicatie beheren): gebruik later `home_highlights_schema.sql` (vereist `is_global_admin` en `committee_members`).

## Agenda + RSVP (activiteiten en aanmelden)

De agenda en aanmeldingen staan in Supabase. Tabellen: `home_agenda`, `home_agenda_rsvps`.

**Setup:**

1. Open **Supabase Dashboard** → jouw project → **SQL Editor**.
2. Maak een nieuw query.
3. Kopieer de inhoud van `home_agenda_schema.sql` en plak die in de editor.
4. Klik **Run**.

Daarna kun je in de app activiteiten toevoegen (bestuur/communicatie), bewerken, verwijderen en aanmelden/afmelden.

De tabel `home_agenda` bevat o.a.: **titel**, **beschrijving** (alleen zichtbaar bij Lees meer), **start_datetime**, **end_datetime**, **location**, **can_rsvp**.

**Let op:** `home_agenda_schema.sql` gebruikt `is_global_admin()`. Als die functie nog niet bestaat, krijg je fouten bij de admin-policies. Zorg dat je eerst een globale admin-functie (en evt. `committee_members`) hebt, of pas het schema aan zodat alleen RLS voor select/insert/delete op RSVPs actief is.

## Nieuwsberichten (titel + beschrijving)

Bestuur en communicatie kunnen nieuwsberichten toevoegen via de + knop. De tabel `home_news` heeft **title** en **description**.

**Setup:**

1. Open **Supabase Dashboard** → jouw project → **SQL Editor**.
2. Maak een nieuw query.
3. Kopieer de inhoud van `home_news_minimal.sql` en plak die in de editor.
4. Klik **Run**.

Daarna kun je in de app nieuwsberichten toevoegen. Zonder deze tabel wordt mock-nieuws getoond.

**"column home_news.description does not exist"?** Je hebt waarschijnlijk een oudere tabel zonder `description`. Voer `home_news_minimal.sql` **opnieuw** uit; het script voegt de ontbrekende kolom toe.

## Match availability (Sport → Wedstrijden: Speler / Trainer/coach / Speel niet / Afmelden)

De Sport-tab gebruikt de tabel `match_availability` om per wedstrijd je status op te slaan: **Speler** (speel mee), **Trainer/coach** (aanwezig als trainer/coach), **Speel niet** of **Afmelden**. Zonder deze tabel krijg je **"Could not find the table 'public.match_availability'"** bij het drukken op de knoppen.

**Setup:**

1. Open **Supabase Dashboard** → jouw project → **SQL Editor**.
2. Maak een nieuw query.
3. Kopieer de inhoud van `match_availability_minimal.sql` en plak die in de editor.
4. Klik **Run**.

Daarna werken Speler, Trainer/coach, Speel niet en Afmelden in Sport → Wedstrijden. Er is onderscheid tussen spelers en trainer/coach bij de weergave („Aangemeld (speler)“ vs „Trainer/coach“). Elke gebruiker beheert alleen zijn eigen status.

**Bestaande tabel zonder coach?** Voer `match_availability_minimal.sql` **opnieuw** uit; het script breidt de `status`-constraint uit met `coach`.

**"Kon status niet opslaan" / `match_availability_status_check` (PostgrestException 23514)?** De constraint laat dan geen `coach` toe. Voer **`match_availability_fix_status_constraint.sql`** uit in de SQL Editor. Daarna zou Aanwezig/Afwezig weer moeten werken.

Voor **admin-override** (globale beheer van alle availability): gebruik `match_availability_schema.sql` (vereist `is_global_admin`).
