#!/bin/bash
set -euo pipefail

echo "== Xcode Cloud: iOS pre-xcodebuild =="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_DIR/.." && pwd)"
ACTION="${CI_XCODEBUILD_ACTION:-unknown}"

cd "$REPO_ROOT"
echo "Xcode Cloud action: $ACTION"

if [ -d "$HOME/flutter/bin" ]; then
  export PATH="$HOME/flutter/bin:$PATH"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found on PATH. Installing stable Flutter SDK..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

if [ ! -f .env ]; then
  echo "Missing .env. Writing placeholders so $ACTION can compile."
  if [ "$ACTION" = "archive" ]; then
    echo "Archive builds require .env from ci_post_clone (Xcode Cloud Environment secrets)."
    exit 1
  fi
  cat > .env <<EOF
SUPABASE_URL=https://placeholder.supabase.co
SUPABASE_ANON_KEY=placeholder-anon-key
GUEST_EMAIL=guest@placeholder.local
GUEST_PASSWORD=placeholder
SUPABASE_RESET_REDIRECT_URL=nl.minerva.clubapp://reset-password/
SUPABASE_EMAIL_CHANGE_REDIRECT_URL=nl.minerva.clubapp://email-change/
EOF
fi

flutter --version
flutter precache --ios

echo "Regenerating Flutter iOS settings for this CI checkout..."
rm -f "$IOS_DIR/Flutter/Generated.xcconfig"
rm -f "$IOS_DIR/Flutter/flutter_export_environment.sh"
rm -rf "$IOS_DIR/.symlinks"
flutter pub get

if ! grep -Fq "FLUTTER_APPLICATION_PATH=$REPO_ROOT" "$IOS_DIR/Flutter/Generated.xcconfig"; then
  echo "Generated.xcconfig was not regenerated for the Xcode Cloud checkout:"
  grep -F "FLUTTER_APPLICATION_PATH=" "$IOS_DIR/Flutter/Generated.xcconfig" || true
  exit 1
fi

# Analyze uses the scheme's Debug configuration; Archive uses Release.
# --config-only writes the matching Generated.xcconfig / plugin registrant.
if [ "$ACTION" = "analyze" ]; then
  echo "Preparing Debug Flutter iOS settings for Analyze..."
  flutter build ios --debug --config-only
else
  echo "Preparing Release Flutter iOS settings..."
  flutter build ios --config-only
fi

cd "$IOS_DIR"
pod install

if ! grep -Fq "app_links" "$IOS_DIR/Podfile.lock"; then
  echo "Flutter plugin pods were not installed. Podfile.lock does not contain app_links."
  exit 1
fi

echo "iOS pre-xcodebuild done."
