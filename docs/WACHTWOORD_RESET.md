# Wachtwoord resetten

Korte beschrijving van de end-to-end flow: resetmail aanvragen → deep link → recovery-sessie → nieuw wachtwoord instellen.

## Configuratie

### `.env`

```env
SUPABASE_RESET_REDIRECT_URL=nl.minerva.clubapp://reset-password/
```

Deze waarde wordt gebruikt als `redirectTo` bij `resetPasswordForEmail` in `ForgotPasswordPage`.

### Supabase Dashboard

**Authentication → URL Configuration → Redirect URLs**

Voeg exact toe:

```
nl.minerva.clubapp://reset-password/
```

(trailing slash meenemen; moet overeenkomen met `.env`)

## Native deep-link registratie

Custom URL scheme: `nl.minerva.clubapp`  
Pad/host: `reset-password`

| Platform | Bestand |
|----------|---------|
| iOS | `ios/Runner/Info.plist` — `CFBundleURLTypes` / `CFBundleURLSchemes` |
| macOS | `macos/Runner/Info.plist` — `CFBundleURLTypes` / `CFBundleURLSchemes` |
| Android | `android/app/src/main/AndroidManifest.xml` — `VIEW` intent-filter op `MainActivity` (scheme + host) |

Na wijzigingen aan deze bestanden is een **volledige rebuild en reinstall** op het betreffende platform verplicht. Hot reload is niet genoeg.

## Dart-bestanden

| Bestand | Rol |
|---------|-----|
| `lib/ui/auth/forgot_password_page.dart` | Resetmail aanvragen via Supabase (`resetPasswordForEmail`) |
| `lib/ui/auth/auth_gate.dart` | Luistert op `AuthChangeEvent.passwordRecovery` en opent `ResetPasswordPage` |
| `lib/ui/auth/reset_password_page.dart` | Nieuw wachtwoord invoeren en opslaan (`updateUser`) |

## Teststappen

1. **App opnieuw installeren** na native deep-link wijzigingen (iOS, Android, macOS).
2. In de app: **Wachtwoord vergeten** → resetmail aanvragen voor een bestaand account.
3. **Nieuwe resetmail gebruiken** — oude mails bevatten vaak een verkeerde of verlopen redirect.
4. Resetlink openen op het **zelfde toestel** waar de app geïnstalleerd is (Safari, Mail, Chrome, etc.).
5. Verwacht gedrag:
   - App opent (of vraagt om te openen)
   - `ResetPasswordPage` verschijnt
   - Na opslaan: bevestiging en terug naar de app

**Snelle controle URL scheme:** typ handmatig `nl.minerva.clubapp://reset-password/` in de browser op het toestel. Werkt dat niet, dan is de scheme nog niet geregistreerd in de geïnstalleerde build.

## Troubleshooting

| Symptoom | Waarschijnlijke oorzaak |
|----------|-------------------------|
| Supabase-pagina: **requested path is invalid** | `redirectTo` niet meegegeven (`.env` leeg/ontbreekt), redirect URL niet in Supabase Dashboard, of **oude resetmail** zonder juiste redirect |
| Safari: **adres ongeldig** | Geen app die scheme afhandelt — **oude build** op toestel, app niet geïnstalleerd, of native config nog niet gedeployed |
| App opent, maar **geen reset-scherm** | Recovery-event of link-afhandeling controleren (`AuthGate`, Supabase sessie, `app_links` / deep-link delivery) |
| macOS werkt, iPhone niet | iOS-app apart opnieuw builden en installeren; macOS en iOS zijn aparte builds |
