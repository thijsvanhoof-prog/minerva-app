# iOS – code signing en run-timeouts

## Aanbevolen: zo voorkom je "Stale file" en Pods_Runner-fouten

De "Stale file ... outside of the allowed root paths"-meldingen ontstaan als er al een `build/`-map bestaat (bijv. van een eerdere `flutter run`) en je daarna in Xcode bouwt. Xcode en Flutter gebruiken dan verschillende plekken voor build-output.

**Gebruik bij voorkeur de terminal om te bouwen en te runnen:**

```bash
cd /Users/bonk/Projecten/minerva_app
flutter run
# of met device-id: flutter run -d 00008150-001535CA3644401C
```

Als je **wel** vanuit Xcode wilt bouwen, doe dan **altijd** vóór het openen van Xcode:

```bash
cd /Users/bonk/Projecten/minerva_app
rm -rf build
```

Daarna pas: `open ios/Runner.xcworkspace` → **Product → Clean Build Folder** (⇧⌘K) → **Product → Run** (⌘R).

---

## "Stale file ... is located outside of the allowed root paths"

Xcode klaagt over build-artefacten in `build/ios/Debug-iphoneos/`. Die map ligt buiten wat Xcode als projectroot ziet, dus hij meldt "outside of the allowed root paths". **Oplossing:**

1. **Sluit Xcode volledig** (Cmd+Q). Belangrijk: doe dit vóór het verwijderen van `build/`.
2. Verwijder de build-map:

```bash
cd /Users/bonk/Projecten/minerva_app
rm -rf build
```

3. *(Optioneel)* Leeg Xcode DerivedData voor dit project, zodat Xcode geen oude file-lijst meer heeft:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
```

4. Zorg dat Pods goed staan: `flutter pub get`, daarna `cd ios && pod install && cd ..`
5. Open **alleen** de workspace: `open ios/Runner.xcworkspace`
6. In Xcode: **Product → Clean Build Folder** (⇧⌘K), daarna **Product → Run** (⌘R).

**Let op:** Na een Xcode-build bestaat `build/` weer. Als je daarna `flutter run` doet en later opnieuw in Xcode bouwt, kun je de meldingen opnieuw krijgen. Doe in dat geval opnieuw: Xcode sluiten → `rm -rf build` → workspace openen → Clean → Run. Of bouw consequent vanuit de terminal met `flutter run` als je geen Xcode nodig hebt.

---

## "Update to recommended settings" (Runner / Pods)

Xcode toont soms een geel icoon bij het project: **Runner** of **Pods** → "Update to recommended settings". Je kunt op die melding klikken en de aanbevolen wijzigingen accepteren (o.a. build system, Swift version). Dat is optioneel maar veilig en houdt het project in lijn met de nieuwste Xcode-aanbevelingen.

---

## Waarschuwingen in plugin-code (firebase_core, image_picker_ios)

Xcode kan waarschuwingen tonen in **geïnstalleerde packages** (bijv. `firebase_core`: `deepLinkURLScheme` is deprecated; `image_picker_ios`: nil return). Die code staat in de pub cache (niet in jouw project). Je kunt ze negeren, of later proberen te verhelpen door packages te updaten (`flutter pub upgrade`). Ze blokkeren de build niet.

---

## "Framework 'Pods_Runner' not found"

Xcode kan de CocoaPods-dependencies niet vinden. **Oplossing:**

1. Sluit Xcode.
2. In de terminal, vanuit de projectroot:

```bash
cd /Users/bonk/Projecten/minerva_app
flutter pub get
cd ios && pod install && cd ..
```

3. Open **altijd** de workspace (niet het project): `open ios/Runner.xcworkspace`
4. In Xcode: **Product → Clean Build Folder** (⇧⌘K), daarna **Product → Run** (⌘R).

Als `pod install` faalt, probeer eerst: `flutter clean`, dan `flutter pub get`, dan opnieuw `cd ios && pod install`.

---

## "Timed out waiting for CONFIGURATION_BUILD_DIR to update"

Als `flutter run` stopt met:

```text
Error starting debug session in Xcode: Timed out waiting for CONFIGURATION_BUILD_DIR to update.
Could not run build/ios/iphoneos/Runner.app on <device>.
```

**Snelste oplossing:** bouw en run vanaf Xcode:

1. `open ios/Runner.xcworkspace` (niet het `.xcodeproj` bestand).
2. Kies bovenaan je fysieke iPhone als run destination.
3. Druk op **Product → Run** (of ⌘R).
4. Wacht tot de app op het toestel staat en draait.

Daarna kan `flutter run` vaak weer. Zo niet: sluit Xcode, doe een schone build (`flutter clean` → `flutter pub get` → eventueel `cd ios && pod install`), en probeer opnieuw.

---

## "objective_c ... was not found in .../build/native_assets/ios/"

Bij `flutter run` of Xcode-build:

```text
The native assets specification at .../NativeAssetsManifest.json references objective_c, which was not found in .../build/native_assets/ios/.
```

**Oorzaak:** `path_provider_foundation` 2.6.0 gebruikt `objective_c` 9.x met “native assets”; de iOS-build vindt dat asset soms niet op de verwachte plek.

**Oplossing in dit project:** In `pubspec.yaml` staat een `dependency_overrides` die `path_provider_foundation` op 2.5.1 zet (plugin-based, geen objective_c native assets). Na wijziging:

```bash
flutter pub get
rm -rf build
flutter run
```

Als je de override later wilt verwijderen, haal dan het blok `dependency_overrides:` met `path_provider_foundation: 2.5.1` uit `pubspec.yaml` en werk Flutter/packages bij (nieuwere versies lossen dit mogelijk op).

---

## Firebase: "Firebase has not been correctly initialized"

Als je bij opstarten ziet: `Firebase init failed (push uit): [core/not-initialized] Firebase has not been correctly initialized`, dan vindt de iOS Firebase SDK het configbestand niet.

**Oorzaak:** `GoogleService-Info.plist` moet in de app-bundle zitten. Het bestand staat in `ios/Runner/`, maar moet ook in het Xcode-project zijn toegevoegd (Copy Bundle Resources).

**Controle:** In dit project is `GoogleService-Info.plist` in `project.pbxproj` opgenomen. Als je het bestand later opnieuw toevoegt (bijv. na een git clone), voeg het in Xcode toe: Runner target → Build Phases → Copy Bundle Resources → + → `GoogleService-Info.plist`.

---

## objective_c.framework / code signature

Als je deze fout ziet bij `flutter run` op een fysiek toestel:

```text
Failed to verify code signature of .../Runner.app/Frameworks/objective_c.framework : 0xe8008014 (The executable contains an invalid signature.)
```

dan weigert iOS de app te installeren omdat een embedded framework (vaak van een Dart native_asset) niet geldig is ondertekend.

## Stappen om te proberen

1. **Schone build**
   - In terminal: `cd /Users/bonk/Projecten/minerva_app`
   - `flutter clean`
   - `rm -rf ios/Pods ios/Podfile.lock ios/.symlinks ios/Flutter/Flutter.podspec`
   - `flutter pub get`
   - `cd ios && pod install && cd ..`

2. **Xcode DerivedData legen**
   - Sluit Xcode.
   - In terminal: `rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*`
   - Of: Xcode → Settings → Locations → Derived Data → pijltje → map verwijderen voor dit project.

3. **Opnieuw bouwen en vanaf Xcode op device zetten**
   - `flutter build ios` (geen `--no-codesign`).
   - Open `ios/Runner.xcworkspace` in Xcode.
   - Kies je development team bij Runner target → Signing & Capabilities.
   - Selecteer je fysieke device en druk op Run (▶). Laat Xcode de app installeren en starten.
   - Als dat lukt, kan `flutter run -d <device-id>` daarna weer werken.

4. **USB in plaats van wireless**
   - Verbind het toestel met de kabel. Wireless debugging kan signing/installatie soms beïnvloeden.

5. **Flutter/Xcode versies**
   - Houd Flutter (`flutter upgrade`) en Xcode up-to-date; nieuwere versies hebben soms betere ondersteuning voor het ondertekenen van embedded frameworks.

De `objective_c` dependency komt als transitive dependency (o.a. native tooling) in het project; het bijbehorende framework moet door Xcode met dezelfde identity als de app worden ondertekend. Stappen 1–3 lossen dat in veel gevallen op.
