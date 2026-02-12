# minerva_app

A new Flutter project.

## App‑icon genereren

Het app‑icoon (bron: `assets/branding/app_icon.png`) wordt gegenereerd met `flutter_launcher_icons`. Na wijziging van dat bestand:

```bash
flutter pub get
dart run flutter_launcher_icons
```

Hiermee worden Android (mipmap-*), iOS (AppIcon.appiconset) en web‑icons bijgewerkt.

## Release (build voor publicatie)

### Versie verhogen
Pas in `pubspec.yaml` `version` aan, bijv. `1.0.1+2` (semver + buildnummer).

### Android
1. **Signing (eenmalig):** Kopieer `android/key.properties.example` naar `android/key.properties`, vul storeFile/storePassword/keyAlias/keyPassword in. Maak eventueel een keystore met `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`. Voeg `android/key.properties` en `*.jks` toe aan `.gitignore`.
2. **App Bundle (Play Store):**
   ```bash
   cd minerva_app
   flutter build appbundle
   ```
   Output: `build/app/outputs/bundle/release/app-release.aab` → uploaden in Play Console.
3. **APK (handmatig installeren):**
   ```bash
   flutter build apk --release
   ```
   Output: `build/app/outputs/flutter-apk/app-release.apk`.

### iOS
1. Open `ios/Runner.xcworkspace` in Xcode.
2. Kies een fysiek device of “Any iOS Device” (niet simulator).
3. **Product → Archive.**
4. Na het archiven: **Distribute App** → App Store Connect / Ad Hoc / Enterprise, volg de wizard.
5. **Push notifications:** `Runner.entitlements` staat op `production` voor App Store distributie. Voor development builds met push: tijdelijk op `development` zetten.

### Web (optioneel)
```bash
flutter build web
```
Output in `build/web/` — deploy naar je host.

## Ouder-kind account (Supabase)

### Waar koppel je in de app?

**Profiel → “Ouder-kind account” → “Kind koppelen”.**  
Daar vul je het e-mailadres van het kind in en stuur je een koppelingsverzoek. De backend verwerkt dat via de RPC hieronder.

### Backend-RPC’s

- **`get_my_linked_child_profiles`** (geen parameters)  
  Retourneert een array van objecten met `profile_id` (uuid) en `display_name` (string).  
  Dit zijn de kind-profielen die aan de ingelogde ouder gekoppeld zijn.  
  Zonder deze RPC blijft de lijst “Bekijk als kind” leeg.

- **`request_child_link`** (parameter: `child_email` string)  
  Koppelingsverzoek door de ouder: zoek het profiel bij dit e-mailadres en koppel dat kind aan de ingelogde ouder (bv. in een tabel `parent_child`).  
  Zonder deze RPC verschijnt na “Koppelingsverzoek sturen” een melding om contact op te nemen met de vereniging.

- **`create_linked_child_account`** (parameters: `child_name`, `child_email`, `child_password` strings)  
  Wordt aangeroepen na registratie als de gebruiker "Ouderaccount aanmaken" heeft aangevinkt. De ingelogde gebruiker is de ouder.  
  De RPC moet (met service role / admin auth): (1) een nieuw auth-account aanmaken voor het kind; (2) het **ouder**-profiel bijwerken met **`display_name` = `"${child_name} (ouder)"`** (zo heet de ouder in de app); (3) een profiel voor het kind (bijv. `display_name` = child_name); (4) de koppeling ouder–kind vastleggen.  
  Zonder deze RPC krijgt de gebruiker de melding om het kind later via Profiel → Kind koppelen te koppelen.

### Account verwijderen (Edge Function)

- **`delete_my_account`** — Edge Function (geen RPC).  
  De app roept `functions.invoke('delete_my_account')` aan. De functie leest de JWT van de ingelogde gebruiker en roept met de service role `auth.admin.deleteUser(userId)` aan.  
  **Secret:** zet in Supabase (Edge Function secrets) `SERVICE_ROLE_KEY` (service_role key).  
  **Deploy:** `supabase functions deploy delete_my_account` (vanuit de projectmap waar `supabase/` staat). Zonder deze gedeployde Edge Function verschijnt na “Account verwijderen” de melding dat de Edge Function ontbreekt.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
