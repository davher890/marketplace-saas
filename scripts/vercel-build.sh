#!/usr/bin/env bash
# Builds the Flutter web app for Vercel.
# Vercel's build image has no Flutter SDK, so a pinned version is installed on
# the fly (cached between builds when possible).
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.8}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_DIR="${FLUTTER_HOME:-$ROOT_DIR/.flutter-sdk}"

if command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
else
  if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
    echo "Installing Flutter $FLUTTER_VERSION..."
    git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  fi
  FLUTTER_BIN="$FLUTTER_DIR/bin/flutter"
fi

# The app talks to the API for everything; the Supabase URL and publishable
# key are only for uploading product images (product_image_repository.dart).
: "${SUPABASE_URL:?SUPABASE_URL must be set}"
: "${SUPABASE_PUBLISHABLE_KEY:?SUPABASE_PUBLISHABLE_KEY must be set}"

cd "$ROOT_DIR/app"
"$FLUTTER_BIN" config --no-analytics >/dev/null
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
  --dart-define=API_BASE_URL="${API_BASE_URL:-}"
