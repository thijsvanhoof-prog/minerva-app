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
flutter pub get

cd "$IOS_DIR"
pod --version
pod install

echo "iOS post-clone done."
