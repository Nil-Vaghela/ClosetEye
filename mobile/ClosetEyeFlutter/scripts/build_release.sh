#!/usr/bin/env bash
# Store builds. Usage:
#   SERVER_URL=https://api.yourdomain.com ./scripts/build_release.sh ios|android|both
# SERVER_URL is compiled in; release builds ignore the in-app server switcher.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SERVER_URL:?Set SERVER_URL to the production API origin, e.g. https://api.drape.app}"
case "$SERVER_URL" in https://*) ;; *) echo "SERVER_URL must be https" >&2; exit 1;; esac
curl -fsS "$SERVER_URL/health" >/dev/null || { echo "API at $SERVER_URL is not healthy" >&2; exit 1; }

TARGET="${1:-both}"
DEFINES=(--dart-define=SERVER_URL="$SERVER_URL")

flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test

if [[ "$TARGET" == "android" || "$TARGET" == "both" ]]; then
  flutter build appbundle --release "${DEFINES[@]}"
  echo "Android: build/app/outputs/bundle/release/app-release.aab  (upload to Play Console)"
fi
if [[ "$TARGET" == "ios" || "$TARGET" == "both" ]]; then
  flutter build ipa --release "${DEFINES[@]}"
  echo "iOS: build/ios/ipa/*.ipa  (upload with Transporter or: xcrun altool / Xcode Organizer)"
fi
