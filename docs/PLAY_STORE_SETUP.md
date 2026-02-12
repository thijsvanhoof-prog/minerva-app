# Google Play Store distributie

Stappen om de Minerva app te uploaden naar de Google Play Store.

## 1. Keystore aanmaken (eenmalig)

Als je nog geen upload-keystore hebt:

```bash
cd android
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Beantwoord de vragen en onthoud het wachtwoord. **Bewaar de keystore en het wachtwoord veilig** – zonder deze kun je geen updates meer uitbrengen.

## 2. key.properties aanmaken

```bash
cp android/key.properties.example android/key.properties
```

Bewerk `android/key.properties` en vul in:

```
storeFile=upload-keystore.jks
storePassword=JOUW_WACHTWOORD
keyAlias=upload
keyPassword=JOUW_WACHTWOORD
```

*(storeFile `upload-keystore.jks` = keystore in de `android/` map)*

**Belangrijk:** `key.properties` en `*.jks` staan in `.gitignore` – commit ze nooit.

## 3. App Bundle bouwen

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

## 4. Play Console

1. Ga naar [Play Console](https://play.google.com/console)
2. Selecteer je app (of maak een nieuwe aan)
3. **Release** → **Production** of **Open testing**
4. **Create new release** → upload `app-release.aab`
5. Vul release notes in en start de rollout

## 5. Versie bij updates

Bij elke nieuwe upload moet het **buildnummer** omhoog. Pas in `pubspec.yaml` aan:

```yaml
version: 3.0.0+3   # +3, +4, etc. bij elke Play Store upload
```

## Troubleshooting

- **"Keystore not found"** → Controleer dat `upload-keystore.jks` in de `android/` map staat
- **"storePassword is wrong"** → Controleer de wachtwoorden in `key.properties`
- **Play Store afwijst AAB** → Zorg dat je een **release** build uploadt (niet debug)
