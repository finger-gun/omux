#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
WAIT_SECONDS="${SMOKE_WAIT_SECONDS:-8}"
ARCHIVE_PATH="${APP_ARCHIVE:-}"

if [ -z "$ARCHIVE_PATH" ]; then
  archive_count=0
  for candidate in "$ROOT_DIR"/dist/release/OpenMUX-*-macos-unsigned.zip; do
    [ -f "$candidate" ] || continue
    archive_count=$((archive_count + 1))
    ARCHIVE_PATH="$candidate"
  done

  if [ "$archive_count" -ne 1 ]; then
    echo "Expected exactly one OpenMUX app release archive; set APP_ARCHIVE explicitly." >&2
    exit 1
  fi
fi

if [ ! -f "$ARCHIVE_PATH" ]; then
  echo "OpenMUX app release archive does not exist: $ARCHIVE_PATH" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openmux-packaged-smoke.XXXXXX")"
UNPACK_DIR="$WORK_DIR/unpacked"
LOG_FILE="$WORK_DIR/openmux-packaged-app.log"
HOME_DIR="$WORK_DIR/home"
OMUX_HOME_DIR="$WORK_DIR/omux-home"
HIDDEN_BUNDLES_DIR="$WORK_DIR/hidden-swiftpm-bundles"
APP_PID=""

cleanup() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi

  if [ -d "$HIDDEN_BUNDLES_DIR" ]; then
    for bundle in "$HIDDEN_BUNDLES_DIR"/*.bundle; do
      [ -e "$bundle" ] || continue
      mv "$bundle" "$BIN_DIR"/
    done
  fi

  rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$UNPACK_DIR" "$HOME_DIR" "$OMUX_HOME_DIR" "$HIDDEN_BUNDLES_DIR"

cat > "$OMUX_HOME_DIR/config.toml" <<'EOF'
schema = 1

[theme]
name = "dracula"

[ghostty]
"copy-on-select" = false
EOF

cd "$ROOT_DIR"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
for bundle in "$BIN_DIR"/*.bundle; do
  [ -e "$bundle" ] || continue
  mv "$bundle" "$HIDDEN_BUNDLES_DIR"/
done

ditto -x -k "$ARCHIVE_PATH" "$UNPACK_DIR"
APP_BIN="$UNPACK_DIR/OpenMUX.app/Contents/MacOS/OpenMUXApp"
if [ ! -x "$APP_BIN" ]; then
  echo "Packaged OpenMUXApp binary is not executable: $APP_BIN" >&2
  exit 1
fi

(
  cd "$WORK_DIR"
  HOME="$HOME_DIR" OMUX_HOME="$OMUX_HOME_DIR" NSUnbufferedIO=YES "$APP_BIN" >"$LOG_FILE" 2>&1
) &
APP_PID=$!

elapsed=0
while [ "$elapsed" -lt "$WAIT_SECONDS" ]; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    wait "$APP_PID" || true
    echo "Packaged OpenMUXApp exited before smoke test completed" >&2
    cat "$LOG_FILE" >&2
    exit 1
  fi

  sleep 1
  elapsed=$((elapsed + 1))
done

echo "Packaged OpenMUXApp smoke test passed"
