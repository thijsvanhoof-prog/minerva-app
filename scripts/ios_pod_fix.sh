#!/bin/sh
# Gebruik dit script wanneer pod install faalt met "could not find compatible versions"
# voor OneSignal (bijv. na versiewissel in pubspec.yaml).
set -e
cd "$(dirname "$0")/.."
echo "flutter pub get..."
flutter pub get
echo "Verwijderen Podfile.lock en opnieuw pod install..."
cd ios
rm -f Podfile.lock
pod install --repo-update
cd ..
echo "Klaar. Run flutter build ios om te bouwen."
