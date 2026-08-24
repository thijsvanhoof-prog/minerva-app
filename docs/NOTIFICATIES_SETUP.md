# Pushnotificaties via Firebase (FCM)

De app gebruikt **Firebase Cloud Messaging (FCM)** voor push. Geen OneSignal meer.

## Wat er in de app zit

- **Firebase** (`firebase_core`, `firebase_messaging`) met centrale `NotificationService`
- **Supabase:** tokens in `push_tokens`, voorkeur in `notification_preferences`
- **Instellingenpagina:** toestemming vragen, schakelaar "Ontvang meldingen", Opslaan
- **Edge Function** `send-push-fcm` om te versturen

---

## Stap 0: Firebase-project en config

1. [Firebase Console](https://console.firebase.google.com/) → project aanmaken of kiezen.
2. **Project settings** → **General** → **Add app**:
   - **iOS:** Bundle ID invullen → **GoogleService-Info.plist** downloaden → in `ios/Runner/` zetten.
   - **Android:** package name invullen → **google-services.json** downloaden → in `android/app/` zetten.
3. **Project settings** → **Service accounts** → **Generate new private key** → JSON bewaren (nodig voor Edge Function).
4. **iOS – APNs:** **Project settings** → **Cloud Messaging** → **Apple app configuration**: .p8 key uploaden (Key ID, Team ID, Bundle ID). Zonder dit geen push op iOS.

---

## Stap 1: Apple – APNs .p8

1. [developer.apple.com](https://developer.apple.com) → **Keys** → nieuwe key met **Apple Push Notifications service (APNs)**.
2. .p8 downloaden, **Key ID** en **Team ID** noteren, **Bundle ID** uit Identifiers.

---

## Stap 2: Supabase – tabellen

Voer **`supabase/push_tokens_schema.sql`** uit in de SQL Editor (maakt `push_tokens` en `notification_preferences` + RLS).

---

## Stap 3: Xcode

**Runner**-target: **Push Notifications** + **Background Modes** (**Remote notifications** aan).

---

## Stap 4: Edge Function – versturen

1. **Secrets** (Edge Functions → Secrets):
   - `FIREBASE_PROJECT_ID` — Firebase project ID
   - `FIREBASE_SERVICE_ACCOUNT_JSON` — volledige inhoud van het service account JSON-bestand (als één string)
   - `SUPABASE_SERVICE_ROLE_KEY` — service role key (om tokens te lezen)

2. **Deploy:**
   ```bash
   supabase functions deploy send-push-fcm
   ```

3. **Aanroepen:** POST naar de function URL met body:
   - `{ "title": "Titel", "body": "Bericht", "broadcast": true }` — naar iedereen met meldingen aan
   - `{ "title": "...", "body": "...", "user_ids": ["uuid1", "uuid2"] }` — naar specifieke users

---

## Stap 5: In de app (device)

Profiel → Notificaties → Toestemming vragen → Toestaan → Ontvang meldingen aan → Opslaan.

---

## Controlelijst

| Stap | Actie |
|------|--------|
| [ ] | Firebase-project + iOS/Android apps + config bestanden in project |
| [ ] | APNs .p8 in Firebase Console (Cloud Messaging → Apple) |
| [ ] | `push_tokens_schema.sql` uitgevoerd in Supabase |
| [ ] | Push Notifications + Background Modes in Xcode |
| [ ] | Edge Function secrets + deploy `send-push-fcm` |
| [ ] | App op device: toestemming + Opslaan |

---

## Meer info

- [NOTIFICATIES_FIREBASE.md](NOTIFICATIES_FIREBASE.md) — uitgebreid FCM-stappenplan
- [Firebase Cloud Messaging](https://firebase.google.com/docs/cloud-messaging)
- [Flutter Firebase setup](https://firebase.google.com/docs/flutter/setup)
