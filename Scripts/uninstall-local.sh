#!/bin/sh
set -u

BUNDLE_ID="dev.fingergun.omux"
APP_NAME="OpenMUX.app"
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HOME_DIR="${HOME:?HOME is required}"
TMP_ROOT="${TMPDIR:-/tmp}"

DRY_RUN=0
ASSUME_YES=0
REMOVE_UNKNOWN_CLI=0
FAILED=0

usage() {
  cat <<EOF
usage: Scripts/uninstall-local.sh [--dry-run] [--yes] [--remove-unknown-cli]

Removes local OpenMUX installs and user data:
  - /Applications/OpenMUX.app and ~/Applications/OpenMUX.app
  - known omux CLI install paths
  - ~/.omux configuration, themes, hooks, generated files, and control socket
  - ~/Library/Application Support/OpenMUX workspace and scrollback state
  - OpenMUX preferences, caches, saved app state, and update staging leftovers

Options:
  --dry-run             Print what would be removed without deleting anything.
  --yes, -y            Do not prompt for confirmation.
  --remove-unknown-cli Remove non-symlink omux files at known CLI paths.
                        By default, only OpenMUX-looking symlinks are removed.
  --help, -h           Show this help.
EOF
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

exists_or_symlink() {
  [ -e "$1" ] || [ -L "$1" ]
}

run_rm() {
  label="$1"
  path="$2"

  if ! exists_or_symlink "$path"; then
    log "skip missing $label: $path"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "would remove $label: $path"
    return
  fi

  if rm -rf "$path"; then
    log "removed $label: $path"
  else
    warn "failed to remove $label: $path"
    FAILED=1
  fi
}

run_defaults_delete() {
  domain="$1"

  if ! defaults read "$domain" >/dev/null 2>&1; then
    log "skip missing defaults domain: $domain"
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "would delete defaults domain: $domain"
    return
  fi

  if defaults delete "$domain"; then
    log "deleted defaults domain: $domain"
  else
    warn "failed to delete defaults domain: $domain"
    FAILED=1
  fi
}

is_openmux_cli_symlink_target() {
  target="$1"

  case "$target" in
    *"/OpenMUX.app/Contents/MacOS/omux")
      return 0
      ;;
    "$ROOT_DIR"/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

remove_cli_path() {
  path="$1"

  if ! exists_or_symlink "$path"; then
    log "skip missing CLI path: $path"
    return
  fi

  if [ -L "$path" ]; then
    target="$(readlink "$path" 2>/dev/null || true)"
    if is_openmux_cli_symlink_target "$target"; then
      run_rm "CLI symlink" "$path"
    else
      warn "skipping CLI symlink with unexpected target: $path -> $target"
    fi
    return
  fi

  if [ "$REMOVE_UNKNOWN_CLI" -eq 1 ]; then
    run_rm "CLI file" "$path"
  else
    warn "skipping non-symlink CLI path: $path"
    warn "pass --remove-unknown-cli to remove it if this is an OpenMUX-installed binary"
  fi
}

remove_update_staging() {
  found=0
  for path in "$TMP_ROOT"/openmux-update-* "$TMP_ROOT"/openmux-install-*; do
    if exists_or_symlink "$path"; then
      found=1
      run_rm "update staging directory" "$path"
    fi
  done

  if [ "$found" -eq 0 ]; then
    log "skip missing update staging directories: $TMP_ROOT/openmux-update-* $TMP_ROOT/openmux-install-*"
  fi
}

confirm() {
  if [ "$DRY_RUN" -eq 1 ] || [ "$ASSUME_YES" -eq 1 ]; then
    return
  fi

  cat <<EOF
This will remove local OpenMUX installs, CLI links, config, preferences,
workspace state, and persisted scrollback for the current user.

It does not quit a running OpenMUX instance. Quit OpenMUX first if it is open.
EOF
  printf 'Continue? [y/N] '
  read answer
  case "$answer" in
    y|Y|yes|YES)
      ;;
    *)
      log "Cancelled."
      exit 0
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --yes|-y)
      ASSUME_YES=1
      ;;
    --remove-unknown-cli)
      REMOVE_UNKNOWN_CLI=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
  shift
done

confirm

run_rm "system app bundle" "/Applications/$APP_NAME"
run_rm "user app bundle" "$HOME_DIR/Applications/$APP_NAME"

remove_cli_path "$HOME_DIR/.local/bin/omux"
remove_cli_path "$HOME_DIR/bin/omux"
remove_cli_path "/opt/homebrew/bin/omux"
remove_cli_path "/usr/local/bin/omux"

run_rm "OpenMUX home" "$HOME_DIR/.omux"
run_rm "application support" "$HOME_DIR/Library/Application Support/OpenMUX"
run_rm "cache directory" "$HOME_DIR/Library/Caches/OpenMUX"
run_rm "cache directory" "$HOME_DIR/Library/Caches/$BUNDLE_ID"
run_rm "saved app state" "$HOME_DIR/Library/Saved Application State/$BUNDLE_ID.savedState"
run_defaults_delete "$BUNDLE_ID"
run_rm "preferences plist" "$HOME_DIR/Library/Preferences/$BUNDLE_ID.plist"
remove_update_staging

if [ "$DRY_RUN" -eq 1 ]; then
  log "Dry run complete. Re-run without --dry-run to remove these paths."
fi

exit "$FAILED"
