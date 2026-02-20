# Pushnotificaties: opnieuw opbouwen

**De app gebruikt nu Firebase (FCM).** OneSignal is volledig verwijderd. Zie [NOTIFICATIES_SETUP.md](NOTIFICATIES_SETUP.md) en [NOTIFICATIES_FIREBASE.md](NOTIFICATIES_FIREBASE.md).

Dit document beschrijft voor referentie de twee routes die er waren: **OneSignal** (niet meer in gebruik) en **Firebase (FCM)** (huidige keuze).

---

## Optie 1: Minimale OneSignal-rebuild (aanbevolen)

We houden OneSignal, maar doen alleen het noodzakelijke. Geen dashboard-sync via de Edge Function (die gaf API key-problemen). Tags worden alleen via de **SDK** in de app gezet; het OneSignal-dashboard toont dan mogelijk niet dezelfde tags, maar **versturen** werkt wel als je filtert op die tags of naar "Subscribed Users" stuurt.

### Wat blijft

| Onderdeel | Doel |
|-----------|------|
| **App:** `NotificationService` + OneSignal SDK | Initialisatie, toestemming, login/logout, tags (notify_news, notify_agenda) |
| **App:** Notificatie-instellingenpagina | Toestemming vragen, schakelaar "Ontvang meldingen", Opslaan (zet tags via SDK) |
| **Supabase:** Edge Function `send-push-notification` | Versturen van pushes (met filters of naar alle Subscribed) |
| **.env** | `ONESIGNAL_APP_ID` |

### Wat we weglaten / niet meer gebruiken

| Onderdeel | Reden |
|-----------|--------|
| **App → Edge Function `update-onesignal-user-tags`** | Gaf "Invalid API key"; tags zetten we alleen via SDK |
| **Afhankelijkheid van dashboard User Tags** | Nice-to-have; voor ontvangen van push zijn SDK-tags voldoende |

### Stappen om push werkend te krijgen (schone lei)

1. **OneSignal**
   - Nieuwe app aanmaken (optioneel, voor echte schone lei) of bestaande gebruiken.
   - **Settings → Keys & IDs:** noteer **App ID** en **REST API Key** (App API Key, niet legacy).

2. **Apple (APNs)**
   - In Apple Developer: .p8 key voor APNs aanmaken (Key ID, Team ID, Bundle ID noteren).
   - In OneSignal: **Settings → Platforms → Apple iOS** → .p8 invullen + uploaden.

3. **Project**
   - **.env:** `ONESIGNAL_APP_ID=<jouw App ID>`.
   - **Xcode (Runner):** Push Notifications + Background Modes (Remote notifications) aan.

4. **Supabase (voor versturen)**
   - **Edge Functions → Secrets:** `ONESIGNAL_APP_ID`, `ONESIGNAL_REST_API_KEY`.
   - Deploy:  
     `supabase functions deploy send-push-notification`

5. **App op een echt device**
   - Profiel → Notificaties → Toestemming vragen → Toestaan → Ontvang meldingen aan → Opslaan.

6. **Testpush**
   - **OneSignal → Messages → Push → New Push:**  
     Target "Subscribed Users" of filter op tag `notify_news` = `true`.

Als je dan een melding ontvangt, werkt de minimale keten. Daarna kunnen database webhooks of andere triggers de Edge Function aanroepen om automatisch te pushen.

---

## Optie 2: Overstappen naar Firebase (FCM)

Volledig stappenplan staat in **[NOTIFICATIES_FIREBASE.md](NOTIFICATIES_FIREBASE.md)**. Kort:

- **App:** `firebase_core` + `firebase_messaging`; device token in Supabase (`push_tokens`).
- **Supabase:** Tabel `push_tokens` (zie `supabase/push_tokens_schema.sql`), Edge Function om via FCM v1 te versturen.
- **APNs:** .p8 in Firebase Console koppelen (iOS).

**Voordelen:** Gratis, geen OneSignal. **Nadelen:** Meer eigen bouwwerk (tokens, Edge Function).

---

## Aanbeveling

Eerst **Optie 1** doorlopen: minimale OneSignal, geen update-onesignal-user-tags, duidelijke stappen. Als push dan werkt, heb je een werkende basis. FCM (Optie 2) alleen overwegen als je OneSignal om andere redenen wilt vervangen.
