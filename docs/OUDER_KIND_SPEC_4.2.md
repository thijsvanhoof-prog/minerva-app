# Specificatie: Ouder–kind en navigatie (v4.2)

Dit document beschrijft hoe ouder/kind-koppelingen en de app-navigatie voor ouders moeten werken.

---

## 1. Koppelingen

- **Meerdere ouders per kind**: Een kind kan aan meerdere ouders gekoppeld zijn (meerdere rijen in `account_links` met dezelfde `child_id`).
- **Meerdere kinderen per ouder**: Een ouder kan meerdere kinderen hebben (meerdere rijen met dezelfde `parent_id`).
- **Koppelen volledig in de app, geen e-mail**: Het koppelen van twee accounts gebeurt volledig in de app (geen `request_child_link` / e-mail naar de andere partij). Voorstel: één account genereert een koppelcode of QR, het andere account scant/voert die in en bevestigt in de app. Beide partijen moeten in de app kunnen bevestigen.

*Technisch: De bestaande tabel `account_links (parent_id, child_id)` ondersteunt al meerdere ouders per kind en meerdere kinderen per ouder. Nodig: nieuwe RPC(s) voor “koppelcode genereren” en “koppelcode invoeren/bevestigen”, en aanpassing van de koppelpagina in de app.*

---

## 2. Ouder als speler/commissielid

- Ouders kunnen **gekoppeld zijn aan een eigen team** als zij zelf volleyballen.
- Ouders kunnen **toegevoegd worden aan een commissie** als zij zelf in die commissie zitten.

*Technisch: Geen wijziging nodig; team_members en committee_members blijven voor het eigen profiel. Alleen de UI moet ervoor zorgen dat “ouder-zaken” en “eigen team/commissie” naast elkaar bestaan.*

---

## 3. Profiel en navigatie voor ouders

- De ouder ziet **alleen het eigen profiel** (geen “als kind meekijken” in de rest van de app).
- Binnen **Profiel** komen **extra tabbladen** voor de zaken rondom elk kind, bijvoorbeeld:
  - **Mijn gegevens** (eigen profiel, commissies, eigen team, koppelingen beheren).
  - **Jan** (en evt. **Piet**, …): tab per kind met o.a. team(s) van dat kind, aanwezigheid, aanmeldingen voor dat kind, etc.

*Technisch: “View as child” (ouderKindNotifier.viewingAs) wordt niet meer gebruikt voor Home/Trainingen/Wedstrijden. Alleen in Profiel zijn er kind-tabs. Navigatie (shell) toont voor ouders dezelfde tabs als voor andere leden (Home, Teams, …), maar de inhoud van Teams/Wedstrijden/Agenda wordt aangepast (zie hieronder).*

---

## 4. Tab Teams (voor ouders)

- De ouder ziet:
  - Het **team waar het kind in speelt** (of meerdere teams van kinderen), **én**
  - Het **team waar de ouder zelf in speelt** (als die in een team zit).
- Weergave: **accordion** (of duidelijke secties), bijv.:
  - Sectie “Teams van [kind]” met de teams van dat kind.
  - Sectie “Mijn team(s)” met de teams van de ouder zelf.
- Hetzelfde principe voor **Wedstrijden**: accordion/secties voor wedstrijden van de kinderen en voor de wedstrijden van de ouder zelf.

*Technisch: TrainingenWedstrijdenTab (of equivalent) moet voor ouders zowel `linkedChildProfiles`-teams als eigen `memberships` tonen, gegroepeerd per “bron” (kind vs. zelf).*

---

## 5. Standen

- **Iedereen** kan ten allen tijde de standen, programma’s en uitslagen van **alle** teams bekijken.
- Geen beperking voor ouders (geen “alleen eigen team” of “alleen teams van kind”).

*Technisch: Controleren of Standen nu ergens gefilterd wordt op eigen team; zo ja, dat filter verwijderen of optie “alle teams” toevoegen.*

---

## 6. Aanmelden activiteiten (agenda-RSVP)

- Bij het **aanmelden voor een activiteit** krijgt de ouder de optie om te kiezen **voor wie** er wordt aangemeld:
  - **Zelf**
  - **Kind 1** (bijv. Jan)
  - **Kind 2** (bijv. Piet)
  - Meerdere opties tegelijk mogelijk (bijv. Zelf + Jan + Piet).
- De ouder kan dus **meerdere selecties** aanklikken (multi-select) en in één keer zichzelf en één of meer kinderen aanmelden.

*Technisch: Agenda/RSVP-flow uitbreiden met “Aanmelden voor: [ ] Zelf [ ] Jan [ ] Piet”. Backend moet meerdere aanmeldingen ondersteunen (per profile_id) of één aanmelding met meerdere “deelnemers” – afhankelijk van bestaande schema’s.*

---

## 7. Samenvatting wijzigingen

| Onderdeel | Huidige situatie | Gewenst |
|-----------|------------------|---------|
| Ouders per kind / kinderen per ouder | DB ondersteunt het al | Geen wijziging DB; UI moet meerdere koppelingen tonen en toestaan |
| Koppelen | Via e-mail (request_child_link / request_parent_link) | Volledig in de app (koppelcode of QR) |
| Navigatie ouder | “View as child” in hele app | Alleen eigen profiel; kind-zaken in Profiel-tabs |
| Teams/Wedstrijden ouder | Nu: view as child of eigen teams | Accordion: teams van kind(eren) + eigen teams |
| Standen | Controleren | Iedereen mag alle teams zien |
| Aanmelden activiteiten | Nu: één profiel (zelf of viewing-as) | Multi-select: Zelf + kind 1 + kind 2 + … |

---

## 8. Fase-indeling (voorstel)

1. **Fase A – Koppelen in de app**  
   Koppelcode/QR-flow (geen e-mail), behoud bestaande `account_links`.

2. **Fase B – Profiel met kind-tabs**  
   Ouder ziet alleen eigen profiel; binnen Profiel tabbladen “Mijn gegevens” en per kind een tab (team, aanwezigheid, aanmeldingen voor dat kind).

3. **Fase C – Teams/Wedstrijden accordion**  
   Voor ouders: secties “Teams van [kind]” en “Mijn teams”, idem voor wedstrijden.

4. **Fase D – Standen voor iedereen**  
   Ervoor zorgen dat standen/programma’s/uitslagen voor alle teams open staan.

5. **Fase E – Aanmelden activiteiten multi-select**  
   Ouder kan zichzelf en meerdere kinderen in één keer aanmelden.

---

*Documentversie: 1.0 – gebaseerd op verenigingstest en gewenste gedrag.*
