# Pushnotificaties met Firebase (FCM)

Stappenplan om OneSignal te vervangen door Firebase Cloud Messaging. FCM is gratis (onbeperkt); je beheert tokens zelf in Supabase.

---

## Overzicht

| Onderdeel | Wat je doet |
|-----------|-------------|
| **Firebase** | Project aanmaken, iOS/Android apps toevoegen, APNs koppelen (iOS), service account key voor backend |
| **Flutter** | `firebase_core` + `firebase_messaging`, config bestanden toevoegen |
| **Supabase** | Tabel `push_tokens` (opslag FCM-tokens), RLS, Edge Function om te versturen |
| **App** | Token ophalen → naar Supabase sturen bij inloggen; token verwijderen bij uitloggen; notificatiepagina aanpassen |

---

## Stap 1: Firebase-project

1. Ga naar [Firebase Console](https://console.firebase.google.com/) → **Add project** (of kies bestaand).
2. **Project settings** (tandwiel) → **General**:
   - **Add app** → **iOS**: vul Bundle ID in (bijv. `nl.minerva.app`), download **GoogleService-Info.plist**.
   - **Add app** → **Android**: vul package name in, download **google-services.json**.
3. **Project settings** → **Service accounts** → **Generate new private key** → bewaar het JSON-bestand (nodig voor de Edge Function om te versturen).
4. **iOS – APNs:**  
   **Project settings** → **Cloud Messaging** → **Apple app configuration**: upload je .p8 key (Key ID, Team ID, Bundle ID). Zonder dit werkt push op iOS niet.

---

## Stap 2: Flutter – Firebase toevoegen

```bash
# In projectroot
flutter pub add firebase_core firebase_messaging
```

- **iOS:** Zet `GoogleService-Info.plist` in `ios/Runner/` (Xcode: rechterklik Runner → Add Files).
- **Android:** Zet `google-services.json` in `android/app/`.

Firebase initialiseren in `main.dart` (vóór `runApp`):

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// In main():
WidgetsFlutterBinding.ensureInitialized();
await Firebase.initializeApp();
// Optioneel: background handler voor meldingen wanneer app gesloten is
FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
```

APNs token (iOS) doorgeven aan FCM:

```dart
final messaging = FirebaseMessaging.instance;
await messaging.requestPermission(); // iOS toestemming
final token = await messaging.getToken();
// token naar Supabase sturen (zie stap 4)
```

Zie [Firebase Flutter docs](https://firebase.google.com/docs/flutter/setup) voor de exacte setup per platform.

---

## Stap 3: Supabase – tabel voor tokens

Voer uit in **SQL Editor**:

```sql
create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('ios', 'android')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, token)
);

create index if not exists idx_push_tokens_user_id on public.push_tokens(user_id);

alter table public.push_tokens enable row level security;

-- Gebruiker mag alleen eigen tokens zien/beheren
create policy "push_tokens_select_own"
  on public.push_tokens for select to authenticated using (auth.uid() = user_id);
create policy "push_tokens_insert_own"
  on public.push_tokens for insert to authenticated with check (auth.uid() = user_id);
create policy "push_tokens_delete_own"
  on public.push_tokens for delete to authenticated using (auth.uid() = user_id);

-- Service role / Edge Function moet alle tokens kunnen lezen (bijv. via service_role key)
-- Voor Edge Function: gebruik service_role of een SECURITY DEFINER RPC die tokens teruggeeft.
```

Als de Edge Function met de **anon** key werkt, heb je een RPC nodig die tokens ophaalt voor het versturen (bijv. `get_push_tokens_for_broadcast()` die alleen door een geauthenticeerde admin wordt aangeroepen, of de function gebruikt de **service_role** key).

---

## Stap 4: App – token naar Supabase sturen

Na inloggen (en na `requestPermission()`):

1. `FirebaseMessaging.instance.getToken()` aanroepen.
2. Token + platform (`ios` / `android`) in `push_tokens` zetten (upsert: zelfde user_id + token → update `updated_at`, anders insert).
3. Bij uitloggen: rijen met `user_id = auth.uid()` uit `push_tokens` verwijderen.

Voorkeur opslaan (zoals “Ontvang meldingen aan/uit”) kan in een bestaande tabel (bijv. `profiles`) of een kleine tabel `notification_preferences`; de Edge Function filtert dan op gebruikers die meldingen willen.

---

## Stap 5: Edge Function – push versturen via FCM

FCM **v1 API** vereist een **OAuth2 access token** (uit service account). In Deno kun je:

- De **service account JSON** als secret zetten (bijv. `FIREBASE_SERVICE_ACCOUNT_JSON`).
- In de function: JWT maken, exchange voor access token, daarna `POST https://fcm.googleapis.com/v1/projects/<project_id>/messages:send` met `Authorization: Bearer <token>`.

**Secrets:**  
`FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT_JSON` (hele JSON-string).

**Body van de function:**  
Bijv. `{ "user_ids": ["uuid1", "uuid2"] }` of “broadcast naar iedereen met voorkeur aan”. Function haalt bijbehorende tokens uit `push_tokens`, roept FCM aan per token (of gebruikt FCM “multicast” tot 500 per request).

Een voorbeeldimplementatie van zo’n Edge Function kun je in een volgend stap toevoegen (aparte file in `supabase/functions/send-push-fcm/`).

---

## Stap 6: OneSignal (afgerond)

OneSignal is in deze app verwijderd; de app gebruikt alleen FCM. De oude Edge Functions `send-push-notification` en `update-onesignal-user-tags` kun je eventueel verwijderen.

- ~~In `pubspec.yaml`: `onesignal_flutter` verwijderen.~~
- In `main.dart`: OneSignal-init weghalen.
- `NotificationService` herschrijven naar FCM (getToken, requestPermission, token naar Supabase, logout = tokens verwijderen).
- Notificatie-instellingenpagina: alleen toestemming + voorkeur “meldingen aan/uit”; opslaan = voorkeur in DB, token blijft in `push_tokens`.
- Edge Functions: `send-push-notification` (OneSignal) en `update-onesignal-user-tags` niet meer gebruiken; eventueel verwijderen.

---

## Samenvatting

| Stap | Actie |
|------|--------|
| 1 | Firebase-project, iOS/Android apps, APNs (.p8), service account key |
| 2 | Flutter: firebase_core, firebase_messaging, config bestanden, Firebase.initializeApp |
| 3 | Supabase: tabel `push_tokens` + RLS |
| 4 | App: token ophalen en in `push_tokens` zetten; bij logout tokens verwijderen |
| 5 | Edge Function: FCM v1 aanroepen met tokens uit `push_tokens` |
| 6 | OneSignal verwijderd; app gebruikt FCM |

De concrete code (NotificationService, main.dart, send-push-fcm) is in de app toegevoegd.
