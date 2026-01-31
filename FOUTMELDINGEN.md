# Foutmeldingen en gebruikersteksten (zichtbaar in de app)

Overzicht van alle fout-, waarschuwings- en succesteksten die een gebruiker kan zien.

---

## Inloggen / Registreren (`auth_page.dart`)

- **Email en wachtwoord komen niet overeen** — bij ongeldige inloggegevens (ivm "Invalid login credentials")
- **Onbekende fout: $e** — bij overige fouten bij inloggen of registreren
- **e.message** — overige `AuthException`-meldingen bij registreren (van Supabase)
- *Succes:* Ingelogd / Account aangemaakt.

---

## Home (`home_tab.dart`)

### Agenda-aanmelding
- **Log in om je aan te melden.** — als niet ingelogd
- **Aanmelding mislukt: $e**

### Nieuwsberichten
- **Opslaan mislukt: $e** — bij toevoegen, aanpassen of verwijderen van nieuws
- *Succes:* Nieuwsbericht toegevoegd. / aangepast. / verwijderd.

### Highlights (Uitgelicht)
- **Opslaan mislukt: $e** — bij bewerken van uitgelicht item
- **Let op: highlights tabel niet beschikbaar.**  
  Voer supabase/home_highlights_minimal.sql uit in Supabase → SQL Editor.  
  Details: $_highlightsError

### Agenda (activiteiten)
- **Opslaan mislukt: $e** — bij toevoegen, aanpassen of verwijderen van activiteit
- **Verwijderen mislukt: $e** — bij verwijderen activiteit
- *Succes:* Activiteit toegevoegd. / aangepast. / verwijderd.
- **Let op: agenda tabel/RSVP niet beschikbaar.**  
  Voeg Supabase tabellen `home_agenda` + `home_agenda_rsvps` toe.  
  Details: $_agendaError

### Detail / dialogen
- **Geen extra informatie.**

---

## Taken (`my_tasks_tab.dart`)

### Verenigingstaken
- **Verenigingstaken konden niet laden** — + raw error, knop "Opnieuw"
- **Kan aanmelding niet wijzigen: $e** — bij aan-/afmelden taak
- **Geen taken voor jouw teams gevonden.**
- **Taken konden niet laden** — + schema-tip of RLS-tip, knop "Opnieuw proberen"
  - *Schema-tip:* Je Supabase tabellen voor taken bestaan nog niet (of de API schema-cache is nog niet ververst).  
    Oplossing: 1) Run `supabase/club_tasks_schema.sql` … 2) Reload schema … 3) App opnieuw openen.
  - *RLS-tip:* Controleer je internetverbinding en permissies in Supabase (RLS).

### Overzicht (thuiswedstrijden)
- **Kon thuiswedstrijden niet laden** — + knop "Opnieuw"
- **Geen thuiswedstrijden gevonden**
- **Sommige teams konden we niet laden (bijv. verkeerde Nevobo-categorie / 404).**
- **Overzicht kon niet laden** — + error, knop "Opnieuw proberen"
- **Geen taken gevonden.**

### Koppelen / importeren
- **Geen teams gevonden.** — TC-koppeldialog
- **Lid gekoppeld aan team.** / **Koppelen mislukt: $e**
- **Gekoppeld. ($created aangemaakt)** — taken-koppelflow
- **Import klaar: $created taken toegevoegd, $skipped overgeslagen.** (+ optioneel: $missingTeamId teams konden we niet mappen)
- **Importeren mislukt: $e**

### Aanmaken taak
- **Geen rechten om taken aan te maken.**
- **Vul uur en minuten in.**
- **Uur moet tussen 0 en 23 zijn.**
- **Minuten moeten tussen 0 en 59 zijn.**

---

## Training toevoegen (`add_training_page.dart`)

- **Kies een team**
- **Eindtijd moet na starttijd liggen**
- **Fout bij opslaan: $e**
- **Vul uur en minuten in.**
- **Uur moet tussen 0 en 23 zijn.**
- **Minuten moeten tussen 0 en 59 zijn.**

---

## Trainingen (`trainings_tab.dart`)

- **Fout bij laden van trainingen: ${snapshot.error}** — + knop "Opnieuw laden"
- **Geen trainingen gevonden.**
- *Bevestiging:* Weet je zeker dat je $count training(en) wilt verwijderen?

---

## Wedstrijden (`nevobo_wedstrijden_tab.dart`)

- **Kon status niet opslaan: $e** — per wedstrijd of bulk
- **Kon Nevobo data niet laden.\n$e**
- **Geen teams gekoppeld voor leaderboards.**
- **Geen leaderboard gevonden.** — per team
- **Geen wedstrijden gevonden.** — per team
- *Succes:* Aanwezig / Afwezig voor X wedstrijd(en) opgeslagen. of "$label voor X wedstrijd(en) opgeslagen."

---

## Standen (`nevobo_standen_tab.dart`)

- **Kon standen niet laden.\n$e**
- **Geen teams gevonden voor standen.**
- **Geen stand gevonden.** — per team

---

## TC-tab (`tc_tab.dart`)

- **Geen teams gevonden.** — bij koppelen lid aan team
- **Lid gekoppeld aan team.** / **Koppelen mislukt: $e**
- **TC tab kon niet laden** — + error, tip over RLS
- **Geen leden zonder team gevonden.**

---

## Profiel (`profiel_tab.dart`)

- **Fout: $_error** — bij laden profiel, + knop "Opnieuw proberen"
- **Geen teams gevonden voor dit account.**
- **E-mail wijzigen:**  
  - **Vul een geldig e-mailadres in.** — bij ongeldig formaat  
  - **Dit is al je huidige e-mailadres.** — bij geen wijziging  
  - *Succes:* E-mail wijziging gestart. Check je mail om te bevestigen.  
  - **e.message** — bij AuthException (Supabase)  
  - **Kon e-mail niet wijzigen. Probeer het later opnieuw.** — bij overige fout
- **Account verwijderen:**  
  - *Succes:* Account verwijderd. (daarna uitloggen)  
  - **e.message** — bij AuthException  
  - **Account verwijderen mislukt. Zorg dat de Edge Function delete_my_account in Supabase is gedeployed en probeer het later opnieuw.** — bij overige fout

---

## Notificaties (`notification_settings_page.dart`)

- *Succes:* Notificatievoorkeuren opgeslagen
- **Opslaan mislukt: $e** — bij fout bij opslaan tags
- **Push notificaties worden op dit platform niet ondersteund.** — web/desktop

---

## Info (`info_tab.dart`)

- **Geen commissies gevonden.**
- **Later koppelen we dit aan een mail-knop: ${item.email}** — bij contact-clicken

---

## Opstarten (`main.dart`)

- **Fout bij opstarten app** — + `$error` (bij ontbrekende .env, Supabase-init, etc.)

---

## Overige

- **$e** / **$error** — op diverse plekken tonen we de ruwe exception; de exacte tekst hangt af van Supabase, RLS, netwerk, etc.
