#!/usr/bin/env bash
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/restore_or_stub_firebase.sh"
STUB="$HERE/stub_google_service_info.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/          /'
  failures=$((failures + 1))
}

echo "stub_google_service_info.sh"

refute() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$label was accepted"; else pass "$label rejected"; fi
}

refute "a missing path" bash "$STUB"
refute "a flag in the path slot" bash "$STUB" --help

target="$TMP/out/GoogleService-Info.plist"
out="$(bash "$STUB" "$target")" || fail "a normal stub write exited non-zero" "$out"
if [[ -s "$target" ]] && grep -q 'GOOGLE_APP_ID' "$target"; then
  pass "writes a placeholder plist"
else
  fail "did not write a placeholder plist" "$out"
fi

key="$(python3 -c 'import plistlib,sys; print(plistlib.loads(open(sys.argv[1],"rb").read()).get("API_KEY",""))' "$target")"
if [[ ${#key} -eq 39 && "$key" == A* ]]; then
  pass "stub API_KEY is 39 characters starting with A"
else
  fail "stub API_KEY is not launch-safe" "$key"
fi

out="$(bash "$STUB" "$target")" || fail "a second stub write exited non-zero" "$out"
[[ "$out" == *"leaving it alone"* ]] \
  && pass "leaves a format-valid plist alone" \
  || fail "did not leave a valid plist alone" "$out"

printf 'keep-me\n' > "$target"
out="$(bash "$STUB" "$target")" || fail "replacing an invalid plist exited non-zero" "$out"
key="$(python3 -c 'import plistlib,sys; print(plistlib.loads(open(sys.argv[1],"rb").read()).get("API_KEY",""))' "$target")"
if [[ ${#key} -eq 39 && "$key" == A* ]]; then
  pass "overwrites an invalid existing plist"
else
  fail "did not replace an invalid plist" "$out"
fi

echo "restore_or_stub_firebase.sh"

root="$TMP/tree"
mkdir -p "$root/macos/Runner" "$root/ios/Runner" "$root/android/app"

run_in_tree() {
  ( cd "$root" && env -u MACOS_GOOGLE_SERVICE_INFO_PLIST_BASE64 \
      -u IOS_GOOGLE_SERVICE_INFO_PLIST_BASE64 \
      -u ANDROID_GOOGLE_SERVICES_JSON_BASE64 \
      -u FIREBASE_OPTIONS_DART_BASE64 \
      "$@" )
}

refute "an unknown platform" bash "$SCRIPT" windows
check_exit2() {
  set +e
  bash "$SCRIPT" >/dev/null 2>&1
  local st=$?
  set -e
  [[ "$st" -eq 2 ]]
}
if check_exit2; then pass "no platform exits 2"; else fail "no platform did not exit 2"; fi

run_in_tree bash "$SCRIPT" macos
if [[ -s "$root/macos/Runner/GoogleService-Info.plist" ]] \
    && grep -q 'GOOGLE_APP_ID' "$root/macos/Runner/GoogleService-Info.plist"; then
  pass "macos without a secret writes a stub plist"
else
  fail "macos without a secret wrote no stub plist"
fi

run_in_tree bash "$SCRIPT" ios
if [[ -s "$root/ios/Runner/GoogleService-Info.plist" ]]; then
  key="$(python3 -c 'import plistlib,sys; print(plistlib.loads(open(sys.argv[1],"rb").read()).get("API_KEY",""))' "$root/ios/Runner/GoogleService-Info.plist")"
  if [[ ${#key} -eq 39 && "$key" == A* ]]; then
    pass "ios without a secret writes a launch-safe stub plist"
  else
    fail "ios without a secret wrote an unsafe API_KEY" "$key"
  fi
else
  fail "ios without a secret wrote no stub plist"
fi

run_in_tree bash "$SCRIPT" android
if [[ -e "$root/android/app/google-services.json" ]]; then
  fail "android without a secret should skip google-services.json"
else
  pass "android without a secret skips google-services.json"
fi

valid_plist='<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>API_KEY</key><string>AIzaSyDummyStubKeyForLocalSideload00000</string>
<key>GOOGLE_APP_ID</key><string>1:000000000000:ios:0000000000000000000000</string>
<key>BUNDLE_ID</key><string>com.doctormobile.app</string>
</dict></plist>'
encoded="$(printf '%s' "$valid_plist" | base64 | tr -d '\n')"
rm -f "$root/macos/Runner/GoogleService-Info.plist"
( cd "$root" && env MACOS_GOOGLE_SERVICE_INFO_PLIST_BASE64="$encoded" \
    bash "$SCRIPT" macos )
got="$(cat "$root/macos/Runner/GoogleService-Info.plist")"
[[ "$got" == "$valid_plist" ]] \
  && pass "macos with a valid secret restores the decoded plist" \
  || fail "macos with a valid secret wrote the wrong bytes" "$got"

bad_plist='<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>API_KEY</key><string>stub</string>
<key>GOOGLE_APP_ID</key><string>1:0:ios:0000</string>
</dict></plist>'
encoded="$(printf '%s' "$bad_plist" | base64 | tr -d '\n')"
( cd "$root" && env MACOS_GOOGLE_SERVICE_INFO_PLIST_BASE64="$encoded" \
    bash "$SCRIPT" macos )
key="$(python3 -c 'import plistlib,sys; print(plistlib.loads(open(sys.argv[1],"rb").read()).get("API_KEY",""))' "$root/macos/Runner/GoogleService-Info.plist")"
if [[ ${#key} -eq 39 && "$key" == A* ]]; then
  pass "macos with an unsafe secret is replaced by the sideload stub"
else
  fail "macos with an unsafe secret kept a crashing API_KEY" "$key"
fi

if (( failures )); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
