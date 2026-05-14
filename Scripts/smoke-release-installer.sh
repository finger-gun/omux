#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RELEASE_DIR="${RELEASE_DIR:-"$ROOT_DIR/dist/release"}"
INSTALLER_PATH="${INSTALLER_PATH:-"$RELEASE_DIR/openmux-install.sh"}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openmux-installer-smoke.XXXXXX")"
HOME_DIR="$WORK_DIR/home"
OMUX_HOME_DIR="$WORK_DIR/omux-home"
TARGET_APP="$HOME_DIR/Applications/OpenMUX.app"
HIDDEN_BUNDLES_DIR="$WORK_DIR/hidden-swiftpm-bundles"
BIN_DIR=""

cleanup() {
  if [ -n "$BIN_DIR" ] && [ -d "$HIDDEN_BUNDLES_DIR" ]; then
    for bundle in "$HIDDEN_BUNDLES_DIR"/*.bundle; do
      [ -e "$bundle" ] || continue
      mv "$bundle" "$BIN_DIR"/
    done
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

[ -f "$INSTALLER_PATH" ] || {
  echo "Installer script does not exist: $INSTALLER_PATH" >&2
  exit 1
}

mkdir -p "$HOME_DIR/Applications" "$OMUX_HOME_DIR" "$HIDDEN_BUNDLES_DIR"

cd "$ROOT_DIR"
BIN_DIR="$(swift build -c release --show-bin-path)"
for bundle in "$BIN_DIR"/*.bundle; do
  [ -e "$bundle" ] || continue
  mv "$bundle" "$HIDDEN_BUNDLES_DIR"/
done

HOME="$HOME_DIR" \
OMUX_HOME="$OMUX_HOME_DIR" \
OPENMUX_RELEASE_BASE_URL="file://$RELEASE_DIR" \
sh "$INSTALLER_PATH" --yes --target "$TARGET_APP"

[ -x "$TARGET_APP/Contents/MacOS/omux" ] || {
  echo "Installed bundle is missing bundled omux executable" >&2
  exit 1
}

HOME="$HOME_DIR" \
OMUX_HOME="$OMUX_HOME_DIR" \
"$TARGET_APP/Contents/MacOS/omux" theme list >/dev/null

echo "Release installer smoke test passed"
