#!/bin/bash
set -euo pipefail

echo "== Xcode Cloud: iOS post-clone =="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_DIR/.." && pwd)"

cd "$REPO_ROOT"
echo "Repository root: $REPO_ROOT"

if [ -d "$HOME/flutter/bin" ]; then
  export PATH="$HOME/flutter/bin:$PATH"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found on PATH. Installing stable Flutter SDK..."
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

required_vars=(
  SUPABASE_URL
  SUPABASE_ANON_KEY
  GUEST_EMAIL
  GUEST_PASSWORD
)

for var in "${required_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "Missing required environment variable: $var"
    exit 1
  fi
done

cat > .env <<EOF
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
GUEST_EMAIL=${GUEST_EMAIL}
GUEST_PASSWORD=${GUEST_PASSWORD}
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

if ! grep -Fq "FLUTTER_APPLICATION_PATH=$REPO_ROOT" "$IOS_DIR/Flutter/Generated.xcconfig"; then
  echo "Generated.xcconfig was not regenerated for the Xcode Cloud checkout:"
  grep -F "FLUTTER_APPLICATION_PATH=" "$IOS_DIR/Flutter/Generated.xcconfig" || true
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
