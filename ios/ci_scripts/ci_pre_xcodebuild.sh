#!/bin/bash
set -euo pipefail

echo "== Xcode Cloud: iOS pre-xcodebuild =="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_DIR/.." && pwd)"
if [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
  REPO_ROOT="$CI_PRIMARY_REPOSITORY_PATH"
  IOS_DIR="$REPO_ROOT/ios"
fi
ACTION="${CI_XCODEBUILD_ACTION:-unknown}"

cd "$REPO_ROOT"
echo "Xcode Cloud action: $ACTION"

if [ -d "$HOME/flutter/bin" ]; then
  export PATH="$HOME/flutter/bin:$PATH"
fi
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found on PATH. Installing stable Flutter SDK..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

if [ ! -f .env ]; then
  echo "Missing .env. Writing placeholders so $ACTION can compile."
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

GEN="$IOS_DIR/Flutter/Generated.xcconfig"
if [ ! -f "$GEN" ]; then
  echo "Generated.xcconfig was not created by flutter pub get."
  exit 1
fi

FLUTTER_ROOT_VALUE="$(grep -E '^FLUTTER_ROOT=' "$GEN" | cut -d= -f2- || true)"
if [ -z "$FLUTTER_ROOT_VALUE" ] || [ ! -f "$FLUTTER_ROOT_VALUE/packages/flutter_tools/bin/xcode_backend.sh" ]; then
  echo "Generated.xcconfig FLUTTER_ROOT is missing or invalid: ${FLUTTER_ROOT_VALUE:-unset}"
  cat "$GEN"
  exit 1
fi

# Best-effort: Analyze uses Debug, Archive uses Release. Do not fail the
# workflow if config-only cannot codesign in the CI environment.
if [ "$ACTION" = "analyze" ]; then
  echo "Preparing Debug Flutter iOS settings for Analyze..."
  flutter build ios --debug --config-only || echo "warning: flutter build ios --debug --config-only failed; continuing."
else
  echo "Preparing Release Flutter iOS settings..."
  flutter build ios --config-only || echo "warning: flutter build ios --config-only failed; continuing."
fi

cd "$IOS_DIR"
pod install

if ! grep -Fq "app_links" "$IOS_DIR/Podfile.lock"; then
  echo "Flutter plugin pods were not installed. Podfile.lock does not contain app_links."
  exit 1
fi

echo "iOS pre-xcodebuild done."
