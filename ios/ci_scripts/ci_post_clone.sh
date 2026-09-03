#!/bin/bash
set -euo pipefail

echo "== Xcode Cloud: iOS post-clone =="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_DIR/.." && pwd)"
if [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
  REPO_ROOT="$CI_PRIMARY_REPOSITORY_PATH"
  IOS_DIR="$REPO_ROOT/ios"
fi
ACTION="${CI_XCODEBUILD_ACTION:-unknown}"

cd "$REPO_ROOT"
echo "Repository root: $REPO_ROOT"
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

env_value() {
  printenv "$1" 2>/dev/null || true
}

# .env is a Flutter asset; Archive/Analyze must compile even when workflow
# secrets are not set (typical for PR checks). Real keys stay required at runtime.
SUPABASE_URL="${SUPABASE_URL:-$(env_value SUPABASE_URL)}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-$(env_value SUPABASE_ANON_KEY)}"
GUEST_EMAIL="${GUEST_EMAIL:-$(env_value GUEST_EMAIL)}"
GUEST_PASSWORD="${GUEST_PASSWORD:-$(env_value GUEST_PASSWORD)}"

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ] || [ -z "${GUEST_EMAIL:-}" ] || [ -z "${GUEST_PASSWORD:-}" ]; then
  echo "Warning: one or more Supabase env vars are unset. Writing placeholder .env so $ACTION can compile."
fi

cat > .env <<EOF
SUPABASE_URL=${SUPABASE_URL:-https://placeholder.supabase.co}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-placeholder-anon-key}
GUEST_EMAIL=${GUEST_EMAIL:-guest@placeholder.local}
GUEST_PASSWORD=${GUEST_PASSWORD:-placeholder}
SUPABASE_RESET_REDIRECT_URL=${SUPABASE_RESET_REDIRECT_URL:-nl.minerva.clubapp://reset-password/}
SUPABASE_EMAIL_CHANGE_REDIRECT_URL=${SUPABASE_EMAIL_CHANGE_REDIRECT_URL:-nl.minerva.clubapp://email-change/}
EOF

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

echo "Generated.xcconfig:"
cat "$GEN"

FLUTTER_ROOT_VALUE="$(grep -E '^FLUTTER_ROOT=' "$GEN" | cut -d= -f2- || true)"
if [ -z "$FLUTTER_ROOT_VALUE" ] || [ ! -f "$FLUTTER_ROOT_VALUE/packages/flutter_tools/bin/xcode_backend.sh" ]; then
  echo "Generated.xcconfig FLUTTER_ROOT is missing or invalid: ${FLUTTER_ROOT_VALUE:-unset}"
  exit 1
fi

cd "$IOS_DIR"
pod --version
pod install

if ! grep -Fq "app_links" "$IOS_DIR/Podfile.lock"; then
  echo "Flutter plugin pods were not installed. Podfile.lock does not contain app_links."
  exit 1
fi

echo "iOS post-clone done."
