#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DIST_DIR="${DIST_DIR:-"$ROOT_DIR/dist"}"
BUILD_DIR="${BUILD_DIR:-"$DIST_DIR/build"}"
OUTPUT_DIR="${OUTPUT_DIR:-"$DIST_DIR/release"}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="${APP_NAME:-OpenMUX.app}"
VERSION="${RELEASE_VERSION:-}"
BUILD_NUMBER="${BUNDLE_VERSION:-${BUILD_NUMBER:-1}}"

if [ -z "$VERSION" ]; then
  if [ -f "$ROOT_DIR/VERSION" ]; then
    VERSION="$(sed -n '1p' "$ROOT_DIR/VERSION")"
  fi
fi

VERSION="${VERSION#v}"
if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: release version must be MAJOR.MINOR.PATCH; set RELEASE_VERSION or update VERSION" >&2
  exit 1
fi

APP_ARCHIVE_NAME="${APP_ARCHIVE_NAME:-OpenMUX-$VERSION-macos-unsigned.zip}"
CLI_ARCHIVE_NAME="${CLI_ARCHIVE_NAME:-omux-$VERSION-macos.tar.gz}"
CHECKSUM_FILE_NAME="${CHECKSUM_FILE_NAME:-checksums.txt}"
INSTALLER_SCRIPT_NAME="${INSTALLER_SCRIPT_NAME:-openmux-install.sh}"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openmux-release.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}

trap cleanup EXIT INT TERM

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/$APP_ARCHIVE_NAME" "$OUTPUT_DIR/$CLI_ARCHIVE_NAME" "$OUTPUT_DIR/$CHECKSUM_FILE_NAME" "$OUTPUT_DIR/$INSTALLER_SCRIPT_NAME"

cd "$ROOT_DIR"

DIST_DIR="$BUILD_DIR" \
CONFIGURATION="$CONFIGURATION" \
SHORT_VERSION="$VERSION" \
BUNDLE_VERSION="$BUILD_NUMBER" \
APP_NAME="$APP_NAME" \
./Scripts/publish-unsigned.sh >/dev/null

APP_BUNDLE="$BUILD_DIR/$APP_NAME"
if [ ! -d "$APP_BUNDLE" ]; then
  echo "error: missing app bundle at $APP_BUNDLE" >&2
  exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$OUTPUT_DIR/$APP_ARCHIVE_NAME"

swift build -c "$CONFIGURATION" --product omux >/dev/null
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
CLI_BIN="$BIN_DIR/omux"

if [ ! -x "$CLI_BIN" ]; then
  echo "error: missing omux binary at $CLI_BIN" >&2
  exit 1
fi

CLI_STAGING_DIR="$STAGING_DIR/omux-$VERSION-macos"
mkdir -p "$CLI_STAGING_DIR"
cp "$CLI_BIN" "$CLI_STAGING_DIR/omux"
cp "$ROOT_DIR/VERSION" "$CLI_STAGING_DIR/VERSION"
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$CLI_STAGING_DIR"/ \;

if [ -f "$ROOT_DIR/LICENSE" ]; then
  cp "$ROOT_DIR/LICENSE" "$CLI_STAGING_DIR/"
fi

tar -C "$STAGING_DIR" -czf "$OUTPUT_DIR/$CLI_ARCHIVE_NAME" "$(basename "$CLI_STAGING_DIR")"

sed "s/@RELEASE_VERSION@/$VERSION/g" "$ROOT_DIR/Scripts/openmux-install.sh.in" > "$OUTPUT_DIR/$INSTALLER_SCRIPT_NAME"
chmod +x "$OUTPUT_DIR/$INSTALLER_SCRIPT_NAME"

(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$APP_ARCHIVE_NAME" "$CLI_ARCHIVE_NAME" "$INSTALLER_SCRIPT_NAME" > "$CHECKSUM_FILE_NAME"
)

printf 'Release assets created at %s\n' "$OUTPUT_DIR"
