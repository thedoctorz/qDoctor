#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ensure_launch_safe_plist() {
  local path="$1"
  if python3 - "$path" <<'PY'
import plistlib, sys
try:
    plist = plistlib.loads(open(sys.argv[1], "rb").read())
except Exception:
    sys.exit(1)
key = plist.get("API_KEY") or ""
sys.exit(0 if isinstance(key, str) and len(key) == 39 and key.startswith("A") else 1)
PY
  then
    return 0
  fi
  echo "::warning::$path is not launch-safe (API_KEY must be 39 chars starting with A). Writing the sideload stub so the IPA does not die at launch."
  "$HERE/stub_google_service_info.sh" "$path"
}

case "${1:-}" in
  dart)
    if [ -n "${FIREBASE_OPTIONS_DART_BASE64:-}" ]; then
      "$HERE/restore_firebase_config.sh" dart
    else
      echo "::warning::FIREBASE_OPTIONS_DART_BASE64 is not set; this build has no push configuration."
      "$HERE/stub_firebase_config.sh"
    fi
    ;;
  android)
    if [ -n "${ANDROID_GOOGLE_SERVICES_JSON_BASE64:-}" ]; then
      "$HERE/restore_firebase_config.sh" android
    else
      echo "::warning::ANDROID_GOOGLE_SERVICES_JSON_BASE64 is not set; skipping google-services.json."
    fi
    ;;
  ios)
    if [ -n "${IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64:-}" ]; then
      "$HERE/restore_firebase_config.sh" ios
      ensure_launch_safe_plist ios/Runner/GoogleService-Info.plist
    else
      echo "::warning::IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64 is not set; this build has no iOS push configuration."
      "$HERE/stub_google_service_info.sh" ios/Runner/GoogleService-Info.plist
    fi
    ;;
  macos)
    if [ -n "${MACOS_GOOGLE_SERVICE_INFO_PLIST_BASE64:-}" ]; then
      "$HERE/restore_firebase_config.sh" macos
      ensure_launch_safe_plist macos/Runner/GoogleService-Info.plist
    else
      echo "::warning::MACOS_GOOGLE_SERVICE_INFO_PLIST_BASE64 is not set; this build has no macOS push configuration."
      "$HERE/stub_google_service_info.sh" macos/Runner/GoogleService-Info.plist
    fi
    ;;
  *)
    echo "Usage: $0 dart|android|ios|macos" >&2
    exit 2
    ;;
esac
