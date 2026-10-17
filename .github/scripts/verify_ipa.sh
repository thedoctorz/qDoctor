#!/usr/bin/env bash
set -Eeuo pipefail

dir="${1:-dist}"
failures=0

fault() {
  echo "::error::$1" >&2
  failures=$((failures + 1))
}

required_entries=(
  "Payload/Runner.app/Info.plist"
  "Payload/Runner.app/GoogleService-Info.plist"
  "Payload/Runner.app/Runner"
  "Payload/Runner.app/Frameworks/App.framework/App"
  "Payload/Runner.app/Frameworks/Flutter.framework/Flutter"
  "Payload/Runner.app/Frameworks/doctor_subghz.framework/doctor_subghz"
  "Payload/Runner.app/Frameworks/qunleashed_hardnested.framework/qunleashed_hardnested"
)

shopt -s nullglob
ipas=("$dir"/*_ios_*.ipa)
if (( ${#ipas[@]} == 0 )); then
  echo "::error::No iOS IPAs found in $dir." >&2
  exit 1
fi

for ipa in "${ipas[@]}"; do
  name="$(basename "$ipa")"
  before=$failures

  if ! err="$(unzip -tqq "$ipa" 2>&1)"; then
    fault "$name failed its integrity check: ${err:-no detail}"
    continue
  fi

  if ! listing="$(unzip -Z1 "$ipa" 2>&1)"; then
    fault "$name could not be listed: ${listing:-no detail}"
    continue
  fi

  case "$name" in
    *_ios_*.ipa) ;;
    *)
      fault "$name does not match the DoctorMobile iOS artifact name."
      continue
      ;;
  esac

  for entry in "${required_entries[@]}"; do
    grep -qxF -- "$entry" <<<"$listing" \
      || fault "$name is missing $entry."
  done

  if grep -qxF -- "Payload/Runner.app/GoogleService-Info.plist" <<<"$listing"; then
    if ! err="$(python3 - "$ipa" <<'PY'
import plistlib, sys, zipfile
path = sys.argv[1]
name = "Payload/Runner.app/GoogleService-Info.plist"
with zipfile.ZipFile(path) as z:
    raw = z.read(name)
try:
    plist = plistlib.loads(raw)
except Exception as exc:
    print(f"unreadable GoogleService-Info.plist: {exc}")
    sys.exit(1)
key = plist.get("API_KEY") or ""
if not isinstance(key, str) or len(key) != 39 or not key.startswith("A"):
    print(
        "GoogleService-Info.plist API_KEY is not 39 characters starting with A "
        f"(got {key!r}). Native FirebaseInstallations aborts at launch."
    )
    sys.exit(1)
sys.exit(0)
PY
    )"; then
      fault "$name Firebase plist would crash at launch: ${err:-no detail}"
    fi
  fi

  if (( failures == before )); then
    echo "  ok  $name"
  fi
done

if (( failures )); then
  echo "::error::$failures problem(s) found; refusing to publish." >&2
  exit 1
fi
echo "Verified ${#ipas[@]} iOS artifact(s)."
