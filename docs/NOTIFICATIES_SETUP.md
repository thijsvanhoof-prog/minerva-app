# Pushnotificaties via Apple en OneSignal

## Hoe het werkt

**Alle pushnotificaties op iOS gaan via Apple's systeem (APNs).** OneSignal is een tussenlaag: je app registreert zich bij OneSignal, OneSignal praat met Apple, en Apple levert de melding bij de gebruiker. De melding zelf komt dus altijd van Apple.

Als de gebruiker "Toestaan" tikt op de vraag "Minerva wil je meldingen sturen", dan heeft Minerva officieel toestemming om meldingen te versturen via Apple.

---

## Stap 1: Apple Developer – APNs-sleutel

1. Ga naar [developer.apple.com](https://developer.apple.com) → **Account** → **Certificates, Identifiers & Profiles**.
2. **Keys** → **+** (nieuwe sleutel).
3. **Key Name:** `Minerva APNs Push`.
4. Vink **Apple Push Notifications service (APNs)** aan.
5. **Continue** → **Register**.
6. Download de `.p8`-bestand (eenmalig). Bewaar **Key ID** en **Team ID**.
7. Noteer je **Bundle ID** (bijv. `nl.minerva.app`) uit **Identifiers** → **App IDs**.

---

## Stap 2: OneSignal – APNs verbinden

1. Ga naar [onesignal.com](https://onesignal.com) → **Dashboard** → je app.
2. **Settings** → **Platforms** → **Apple iOS (APNs)**.
3. Kies **p8 (aanbevolen)**:
   - **Key ID:** uit stap 1
   - **Team ID:** uit stap 1
   - **Bundle ID:** uit stap 1
   - **Upload .p8:** het gedownloade bestand
4. **Save** (of **Continue**).

Zonder deze stap levert OneSignal geen meldingen op iOS.

---

## Stap 3: Xcode – Push Notifications

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Selecteer het **Runner**-target.
3. **Signing & Capabilities** → **+ Capability**.
4. Voeg **Push Notifications** toe.
5. Voeg **Background Modes** toe.
6. Vink bij Background Modes **Remote notifications** aan.

(Optioneel: voor afbeeldingen en bevestigde levering is een **Notification Service Extension** nodig – zie [OneSignal iOS docs](https://documentation.onesignal.com/docs/ios-sdk-setup)).

---

## Stap 4: Toestemming in de app

De app vraagt al via `OneSignal.Notifications.requestPermission` om toestemming (zie `notification_settings_page.dart`). Gebruikers kunnen **Instellingen** → **Meldingen** → **Minerva** gebruiken om dit later aan of uit te zetten.

---

## Stap 5: Meldingen versturen (backend)

De app registreert gebruikers bij OneSignal. Het **versturen** van meldingen moet van de backend komen:

- **Bericht geplaatst** → trigger bij insert in `home_news` of vergelijkbare tabel
- **Training/wedstrijd gewijzigd** → trigger bij update in `sessions`
- **Stand bijgewerkt** → trigger bij update in standentabel

### Optie A: Supabase Edge Function

1. Maak een Edge Function, bijv. `supabase/functions/send-push-notification/index.ts`.
2. Deze functie roept de OneSignal REST API aan.
3. Gebruik Supabase **Database Webhooks** of **triggers** om bij wijzigingen deze functie aan te roepen.

### Optie B: Database trigger + pg_net

- Bij een trigger: riep `pg_net.http_post` aan naar een endpoint dat de OneSignal API aanroept.
- Of: gebruik een externe service (bijv. Vercel/Netlify) die op webhook reageert.

### OneSignal API-voorbeeld

```bash
curl -X POST https://api.onesignal.com/notifications \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic YOUR_ONESIGNAL_REST_API_KEY" \
  -d '{
    "app_id": "YOUR_ONESIGNAL_APP_ID",
    "include_player_ids": ["player-id"],
    "headings": {"nl": "Nieuwe training"},
    "contents": {"nl": "De training van maandag is verplaatst."},
    "filters": [{"field": "tag", "key": "notify_trainings", "value": "true"}]
  }'
```

Gebruik **tags** voor gerichte meldingen: `notify_news`, `notify_trainings`, `notify_standings`, `team_123`, etc.

---

## Testen

1. **Eenmalig:** APNs-credentials in OneSignal invullen (stap 2).
2. **App op device:** Build & run op fysiek apparaat (simulator heeft geen push).
3. **Toestemming:** Tik "Toestaan" als de app vraagt om meldingen.
4. **OneSignal Dashboard:** **Audience** → **Subscriptions** – status zou "Subscribed" moeten zijn.
5. **Testpush:** **Messages** → **New Push** → **Send to Test Users** of een segment.

---

## Controlelijst

| Stap | Actie |
|------|--------|
| [ ] | APNs .p8-sleutel in Apple Developer aangemaakt |
| [ ] | APNs ingesteld in OneSignal → Settings → Apple iOS |
| [ ] | Push Notifications + Background Modes in Xcode |
| [ ] | App op een echt device getest |
| [ ] | Meldingen in app-instellingen toegestaan |
| [ ] | Backend/Edge Function voor het versturen van meldingen |
| [ ] | Triggers bij bericht, training/wedstrijd, stand |

---

## Meer informatie

- [OneSignal iOS Setup](https://documentation.onesignal.com/docs/ios-sdk-setup)
- [OneSignal Create Notification API](https://documentation.onesignal.com/reference/create-notification)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
