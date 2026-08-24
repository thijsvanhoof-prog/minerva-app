# Auth redirect URLs (wachtwoord reset + e-mail wijzigen)

Korte beschrijving van deep-link flows terug naar de app via custom scheme `nl.minerva.clubapp`.

## Configuratie

### `.env`

```env
SUPABASE_RESET_REDIRECT_URL=nl.minerva.clubapp://reset-password/
SUPABASE_EMAIL_CHANGE_REDIRECT_URL=nl.minerva.clubapp://email-change/
```

| Variabele | Gebruikt door |
|-----------|----------------|
| `SUPABASE_RESET_REDIRECT_URL` | `resetPasswordForEmail` in `ForgotPasswordPage` |
| `SUPABASE_EMAIL_CHANGE_REDIRECT_URL` | `updateUser(..., emailRedirectTo: ...)` in `ProfielTab` |

### Supabase Dashboard

**Authentication → URL Configuration → Redirect URLs**

Voeg exact toe:

```
nl.minerva.clubapp://reset-password/
nl.minerva.clubapp://email-change/
```

(trailing slash meenemen; moet overeenkomen met `.env`)

## Native deep-link registratie

Custom URL scheme: `nl.minerva.clubapp`

| Flow | Host/pad |
|------|----------|
| Wachtwoord reset | `reset-password` |
| E-mail wijzigen bevestigen | `email-change` |

| Platform | Bestand |
|----------|---------|
| iOS | `ios/Runner/Info.plist` — `CFBundleURLTypes` / `CFBundleURLSchemes` |
| macOS | `macos/Runner/Info.plist` — `CFBundleURLTypes` / `CFBundleURLSchemes` |
| Android | `android/app/src/main/AndroidManifest.xml` — `VIEW` intent-filter per host op `MainActivity` |

Na wijzigingen aan native bestanden is een **volledige rebuild en reinstall** op het betreffende platform verplicht. Hot reload is niet genoeg.

## Dart-bestanden

| Bestand | Rol |
|---------|-----|
| `lib/ui/auth/auth_email_change_pending.dart` | Onthoudt pending e-mail tot bevestiging via deep link |
| `lib/ui/auth/auth_redirect_urls.dart` | Redirect-URL helpers + deep-link host `email-change` |
| `lib/ui/auth/forgot_password_page.dart` | Resetmail aanvragen via Supabase (`resetPasswordForEmail`) |
| `lib/profiel/profiel_tab.dart` | E-mail wijzigen (`updateUser` + `emailRedirectTo`) |
| `lib/ui/auth/auth_gate.dart` | `passwordRecovery` → reset-scherm; e-mail-change link → bevestigingsmelding |
| `lib/ui/auth/reset_password_page.dart` | Nieuw wachtwoord invoeren en opslaan (`updateUser`) |

## E-mail wijzigen — teststappen

1. App opnieuw installeren na native deep-link wijzigingen (Android vereist extra intent-filter).
2. Inloggen → **Profiel → E-mail wijzigen** → nieuw adres invullen.
3. Bevestigingsmail openen op hetzelfde toestel als de app.
4. Verwacht gedrag:
   - App opent via `nl.minerva.clubapp://email-change/...`
   - Melding: **E-mailadres is bevestigd.**
   - Profiel toont het nieuwe e-mailadres (via auth user)
   - **Geen** reset-wachtwoord-scherm

## Wachtwoord resetten — teststappen

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
