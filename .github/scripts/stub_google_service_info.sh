#!/usr/bin/env bash
set -Eeuo pipefail

TARGET="${1:-}"
if [[ -z "$TARGET" || "$TARGET" == -* ]]; then
  echo "Usage: $0 <path>" >&2
  exit 2
fi

api_key_ok() {
  python3 - "$1" <<'PY'
import plistlib, sys
try:
    plist = plistlib.loads(open(sys.argv[1], "rb").read())
except Exception:
    sys.exit(1)
key = plist.get("API_KEY") or ""
sys.exit(0 if isinstance(key, str) and len(key) == 39 and key.startswith("A") else 1)
PY
}

if [[ -s "$TARGET" ]] && api_key_ok "$TARGET"; then
  echo "$TARGET already has a format-valid API_KEY, leaving it alone."
  exit 0
fi

mkdir -p "$(dirname "$TARGET")"
cat > "$TARGET" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>API_KEY</key>
	<string>AIzaSyDummyStubKeyForLocalSideload00000</string>
	<key>GCM_SENDER_ID</key>
	<string>000000000000</string>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>BUNDLE_ID</key>
	<string>com.doctormobile.app</string>
	<key>PROJECT_ID</key>
	<string>doctormobile-local</string>
	<key>STORAGE_BUCKET</key>
	<string>doctormobile-local.appspot.com</string>
	<key>IS_ADS_ENABLED</key>
	<false/>
	<key>IS_ANALYTICS_ENABLED</key>
	<false/>
	<key>IS_APPINVITE_ENABLED</key>
	<false/>
	<key>IS_GCM_ENABLED</key>
	<false/>
	<key>IS_SIGNIN_ENABLED</key>
	<false/>
	<key>GOOGLE_APP_ID</key>
	<string>1:000000000000:ios:0000000000000000000000</string>
</dict>
</plist>
PLIST

echo "Wrote a launch-safe placeholder $TARGET."
