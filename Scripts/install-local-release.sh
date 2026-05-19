#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RELEASE_DIR="${RELEASE_DIR:-"$ROOT_DIR/dist/release"}"
TARGET_APP="${TARGET_APP:-/Applications/OpenMUX.app}"
APP_NAME="${APP_NAME:-OpenMUX.app}"
BUNDLE_ID="${BUNDLE_ID:-dev.fingergun.omux}"
SKIP_PACKAGE="${SKIP_PACKAGE:-0}"
RELAUNCH="${RELAUNCH:-1}"
DETACH_INSTALL="${DETACH_INSTALL:-1}"
QUIT_TIMEOUT_SECONDS="${QUIT_TIMEOUT_SECONDS:-20}"
LAUNCH_TIMEOUT_SECONDS="${LAUNCH_TIMEOUT_SECONDS:-20}"

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if [ "$SKIP_PACKAGE" != "1" ]; then
  "$ROOT_DIR/Scripts/package-release.sh"
fi

[ -d "$RELEASE_DIR" ] || fail "release directory does not exist: $RELEASE_DIR"

APP_ARCHIVE="$(ls -t "$RELEASE_DIR"/OpenMUX-*-macos-unsigned.zip 2>/dev/null | sed -n '1p' || true)"

[ -n "$APP_ARCHIVE" ] || fail "no OpenMUX app archive found in $RELEASE_DIR"
[ -f "$APP_ARCHIVE" ] || fail "app archive does not exist: $APP_ARCHIVE"

TARGET_PARENT="$(dirname "$TARGET_APP")"
[ -d "$TARGET_PARENT" ] || fail "install parent does not exist: $TARGET_PARENT"
[ -w "$TARGET_PARENT" ] || fail "install parent is not writable: $TARGET_PARENT"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/openmux-local-install.XXXXXX")"

log "Unpacking $(basename "$APP_ARCHIVE")..."
ditto -x -k "$APP_ARCHIVE" "$STAGING_DIR"

STAGED_APP="$STAGING_DIR/$APP_NAME"
[ -d "$STAGED_APP" ] || fail "archive did not contain $APP_NAME"
[ -x "$STAGED_APP/Contents/MacOS/OpenMUXApp" ] || fail "staged app is missing OpenMUXApp executable"

HELPER_SCRIPT="$STAGING_DIR/install-local-release-helper.sh"
HELPER_LOG="${TMPDIR:-/tmp}/openmux-local-install-$(basename "$STAGING_DIR").log"

cat > "$HELPER_SCRIPT" <<'EOF'
#!/bin/sh
set -eu

STAGED_APP="$1"
TARGET_APP="$2"
BUNDLE_ID="$3"
RELAUNCH="$4"
QUIT_TIMEOUT_SECONDS="$5"
LAUNCH_TIMEOUT_SECONDS="$6"
STAGING_DIR="$7"
APP_ARCHIVE="$8"
HELPER_LOG="$9"

log() {
  printf '%s\n' "$*" >> "$HELPER_LOG"
}

fail() {
  log "error: $*"
  exit 1
}

is_openmux_running() {
  [ "$(osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null || printf 'false')" = "true" ]
}

validate_install_target() {
  [ -n "$TARGET_APP" ] || fail "install target is empty"
  [ "$TARGET_APP" != "/" ] || fail "refusing to install to filesystem root"

  target_name="$(basename "$TARGET_APP")"
  target_parent="$(dirname "$TARGET_APP")"
  case "$target_name" in
    *.app) ;;
    *) fail "install target must be a .app bundle: $TARGET_APP" ;;
  esac

  [ -d "$target_parent" ] || fail "install target parent does not exist: $target_parent"
  target_parent_real="$(realpath "$target_parent")" || fail "cannot canonicalize install parent: $target_parent"
  target_canonical="$target_parent_real/$target_name"

  case "$target_canonical" in
    ""|"/"|"/Applications"|"/Library"|"/System"|"/Users"|"/private"|"/var"|"/tmp")
      fail "refusing unsafe install target: $target_canonical"
      ;;
    *.app) ;;
    *) fail "canonical install target must be a .app bundle: $target_canonical" ;;
  esac

  staged_name="$(basename "$STAGED_APP")"
  case "$staged_name" in
    *.app) ;;
    *) fail "staged app must be a .app bundle: $STAGED_APP" ;;
  esac
  [ -d "$STAGED_APP/Contents/MacOS" ] || fail "staged app is not a macOS app bundle: $STAGED_APP"

  if [ -e "$TARGET_APP" ]; then
    target_existing_real="$(realpath "$TARGET_APP")" || fail "cannot canonicalize existing install target: $TARGET_APP"
    case "$target_existing_real" in
      ""|"/"|"/Applications"|"/Library"|"/System"|"/Users"|"/private"|"/var"|"/tmp")
        fail "refusing unsafe existing install target: $target_existing_real"
        ;;
      *.app) ;;
      *) fail "existing install target must resolve to a .app bundle: $target_existing_real" ;;
    esac
  fi
}

log "Starting local OpenMUX install from $APP_ARCHIVE"

if is_openmux_running; then
  log "Quitting OpenMUX"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  elapsed=0
  while is_openmux_running; do
    if [ "$elapsed" -ge "$QUIT_TIMEOUT_SECONDS" ]; then
      fail "OpenMUX is still running after ${QUIT_TIMEOUT_SECONDS}s"
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
fi

log "Installing to $TARGET_APP"
validate_install_target
rm -rf "$TARGET_APP"
ditto "$STAGED_APP" "$TARGET_APP"

if [ "$RELAUNCH" = "1" ]; then
  log "Launching OpenMUX"
  open -n "$TARGET_APP"
  elapsed=0
  while ! is_openmux_running; do
    if [ "$elapsed" -ge "$LAUNCH_TIMEOUT_SECONDS" ]; then
      fail "OpenMUX did not launch after ${LAUNCH_TIMEOUT_SECONDS}s"
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
fi

log "Installed local release successfully"
rm -rf "$STAGING_DIR"
EOF
chmod +x "$HELPER_SCRIPT"

if [ "$DETACH_INSTALL" = "1" ]; then
  log "Handing off install. Progress log: $HELPER_LOG"
  nohup "$HELPER_SCRIPT" "$STAGED_APP" "$TARGET_APP" "$BUNDLE_ID" "$RELAUNCH" "$QUIT_TIMEOUT_SECONDS" "$LAUNCH_TIMEOUT_SECONDS" "$STAGING_DIR" "$APP_ARCHIVE" "$HELPER_LOG" >> "$HELPER_LOG" 2>&1 &
  log "OpenMUX will quit, install, and relaunch in the background."
  exit 0
fi

"$HELPER_SCRIPT" "$STAGED_APP" "$TARGET_APP" "$BUNDLE_ID" "$RELAUNCH" "$QUIT_TIMEOUT_SECONDS" "$LAUNCH_TIMEOUT_SECONDS" "$STAGING_DIR" "$APP_ARCHIVE" "$HELPER_LOG"

log "Installed local release from $APP_ARCHIVE"
