#!/usr/bin/env bash
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/verify_ipa.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/          /'
  failures=$((failures + 1))
}

run() { bash "$SCRIPT" "$@" 2>&1; }

accepts() {
  local out
  if out="$(run "$2")"; then pass "$1"; else fail "$1" "$out"; fi
}

refuses() {
  local out
  if out="$(run "$2")"; then
    fail "$1 (was accepted)" "$out"
  elif [[ "$out" != *"$3"* ]]; then
    fail "$1 (refused for the wrong reason; wanted \"$3\")" "$out"
  else
    pass "$1"
  fi
}

ipa() {
  python3 - "$@" <<'PY'
import sys, zipfile
path = sys.argv[1]
omit = ""
bad_firebase = False
for arg in sys.argv[2:]:
    if arg == "--bad-firebase":
        bad_firebase = True
    else:
        omit = arg
entries = [
  "Payload/Runner.app/Info.plist",
  "Payload/Runner.app/GoogleService-Info.plist",
  "Payload/Runner.app/Runner",
  "Payload/Runner.app/Frameworks/App.framework/App",
  "Payload/Runner.app/Frameworks/Flutter.framework/Flutter",
  "Payload/Runner.app/Frameworks/doctor_subghz.framework/doctor_subghz",
  "Payload/Runner.app/Frameworks/qunleashed_hardnested.framework/qunleashed_hardnested",
]
good_plist = b"""<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>API_KEY</key><string>AIzaSyDummyStubKeyForLocalSideload00000</string>
<key>GOOGLE_APP_ID</key><string>1:000000000000:ios:0000000000000000000000</string>
</dict></plist>
"""
bad_plist = b"""<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>API_KEY</key><string>stub</string>
<key>GOOGLE_APP_ID</key><string>1:0:ios:0000</string>
</dict></plist>
"""
with zipfile.ZipFile(path, "w") as z:
    for entry in entries:
        if entry == omit:
            continue
        if entry.endswith("GoogleService-Info.plist"):
            z.writestr(entry, bad_plist if bad_firebase else good_plist)
        else:
            z.writestr(entry, b"body")
PY
}

echo "verify_ipa.sh"

d="$TMP/good"; mkdir -p "$d"
ipa "$d/doctormobile_0.13.0_ios_arm64.ipa"
accepts "a complete IPA passes" "$d"

d="$TMP/no-flutter"; mkdir -p "$d"
ipa "$d/doctormobile_0.13.0_ios_arm64.ipa" "Payload/Runner.app/Frameworks/Flutter.framework/Flutter"
refuses "an IPA missing Flutter.framework is refused" "$d" "missing Payload/Runner.app/Frameworks/Flutter.framework/Flutter"

d="$TMP/no-subghz"; mkdir -p "$d"
ipa "$d/doctormobile_0.13.0_ios_arm64.ipa" "Payload/Runner.app/Frameworks/doctor_subghz.framework/doctor_subghz"
refuses "an IPA missing doctor_subghz is refused" "$d" "missing Payload/Runner.app/Frameworks/doctor_subghz.framework/doctor_subghz"

d="$TMP/no-plist"; mkdir -p "$d"
ipa "$d/doctormobile_0.13.0_ios_arm64.ipa" "Payload/Runner.app/Info.plist"
refuses "an IPA missing Info.plist is refused" "$d" "missing Payload/Runner.app/Info.plist"

d="$TMP/bad-firebase"; mkdir -p "$d"
ipa "$d/doctormobile_0.13.0_ios_arm64.ipa" --bad-firebase
refuses "an IPA with API_KEY=stub is refused" "$d" "Firebase plist would crash at launch"

d="$TMP/no-firebase"; mkdir -p "$d"
ipa "$d/doctormobile_0.13.0_ios_arm64.ipa" "Payload/Runner.app/GoogleService-Info.plist"
refuses "an IPA missing GoogleService-Info.plist is refused" "$d" "missing Payload/Runner.app/GoogleService-Info.plist"

d="$TMP/unreadable"; mkdir -p "$d"
printf 'not a zip\n' > "$d/doctormobile_0.13.0_ios_arm64.ipa"
refuses "an unreadable IPA is refused" "$d" "failed its integrity check"

d="$TMP/empty"; mkdir -p "$d"
refuses "a directory with no IPA is refused" "$d" "No iOS IPAs found"

refuses "a missing directory is refused" "$TMP/does-not-exist" "No iOS IPAs found"

if (( failures )); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
