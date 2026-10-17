#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APP_NAME="Runner"
FILE_NAME="doctormobile"
VERSION_NAME="${DOCTORMOBILE_VERSION_NAME:-}"
DIST_DIR="$ROOT_DIR/dist"
DERIVED_DIR="$ROOT_DIR/build/ios_ci"
BUILD_APP="$DERIVED_DIR/Build/Products/Release-iphoneos/$APP_NAME.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "The iOS IPA can only be built on macOS." >&2
  exit 1
fi

if [[ -z "$VERSION_NAME" ]]; then
  VERSION_NAME="$(sed -nE 's/^version:[[:space:]]*([0-9A-Za-z._-]+).*/\1/p' "$ROOT_DIR/pubspec.yaml" | head -n 1)"
  VERSION_NAME="${VERSION_NAME%%+*}"
fi

if [[ -z "$VERSION_NAME" ]]; then
  echo "App version not found. Set DOCTORMOBILE_VERSION_NAME or pubspec.yaml version." >&2
  exit 1
fi

FLUTTER_BIN="${FLUTTER_BIN:-}"
if [[ -z "$FLUTTER_BIN" ]]; then
  FLUTTER_BIN="$(command -v flutter || true)"
fi

if [[ -z "$FLUTTER_BIN" || ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter executable not found. Set FLUTTER_BIN=/path/to/flutter." >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required." >&2
  exit 1
fi

if ! command -v ditto >/dev/null 2>&1; then
  echo "ditto is required." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"

echo "Using Flutter: $FLUTTER_BIN"
echo "Configuring iOS release (unsigned)..."
FLUTTER_COMMAND=("$FLUTTER_BIN" build ios --release --config-only --no-codesign)
if [[ -n "${DOCTORMOBILE_FLUTTER_BUILD_ARGS:-}" ]]; then
  read -r -a FLUTTER_BUILD_ARGS <<< "$DOCTORMOBILE_FLUTTER_BUILD_ARGS"
  FLUTTER_COMMAND+=("${FLUTTER_BUILD_ARGS[@]}")
fi
(cd "$ROOT_DIR" && "${FLUTTER_COMMAND[@]}")

echo "Building iOS unsigned device slice..."
rm -rf "$DERIVED_DIR"
(cd "$ROOT_DIR" && xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build)

if [[ ! -d "$BUILD_APP" ]]; then
  echo "Expected app bundle not found: $BUILD_APP" >&2
  exit 1
fi
if [[ ! -f "$BUILD_APP/$APP_NAME" ]]; then
  echo "Expected app executable not found: $BUILD_APP/$APP_NAME" >&2
  exit 1
fi

"$ROOT_DIR/.github/scripts/check_ffi_exports.sh" "$BUILD_APP/$APP_NAME" "$BUILD_APP"

OUT_FILE="$DIST_DIR/${FILE_NAME}_${VERSION_NAME}_ios_arm64.ipa"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${FILE_NAME}-ipa.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/Payload"
ditto "$BUILD_APP" "$TMP_DIR/Payload/$APP_NAME.app"
xattr -cr "$TMP_DIR/Payload" 2>/dev/null || true

rm -f "$OUT_FILE"
(cd "$TMP_DIR" && ditto -c -k --sequesterRsrc --keepParent Payload "$OUT_FILE")

echo "Built iOS IPA:"
echo "$OUT_FILE"
