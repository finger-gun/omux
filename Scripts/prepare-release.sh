#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"

usage() {
  echo "usage: Scripts/prepare-release.sh MAJOR.MINOR.PATCH < changelog-body.md" >&2
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

VERSION="$1"
case "$VERSION" in
  v*)
    echo "error: version must not include a leading 'v'" >&2
    exit 1
    ;;
esac

if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: version must be MAJOR.MINOR.PATCH" >&2
  exit 1
fi

BODY_FILE="$(mktemp "${TMPDIR:-/tmp}/openmux-changelog-body.XXXXXX")"
NEW_CHANGELOG="$(mktemp "${TMPDIR:-/tmp}/openmux-changelog.XXXXXX")"

cleanup() {
  rm -f "$BODY_FILE" "$NEW_CHANGELOG"
}

trap cleanup EXIT INT TERM

cat > "$BODY_FILE"

if ! grep -Eq '[^[:space:]]' "$BODY_FILE"; then
  echo "error: changelog body is required on stdin" >&2
  exit 1
fi

if [ ! -f "$CHANGELOG_FILE" ]; then
  {
    printf '# Changelog\n\n'
    printf '## %s\n\n' "$VERSION"
    cat "$BODY_FILE"
    printf '\n'
  } > "$NEW_CHANGELOG"
else
  awk -v version="$VERSION" -v body_file="$BODY_FILE" '
    BEGIN {
      inserted = 0
    }
    NR == 1 {
      print
      next
    }
    inserted == 0 && $0 ~ /^## / {
      print ""
      printf "## %s\n\n", version
      while ((getline line < body_file) > 0) {
        print line
      }
      close(body_file)
      print ""
      inserted = 1
    }
    {
      print
    }
    END {
      if (inserted == 0) {
        print ""
        printf "## %s\n\n", version
        while ((getline line < body_file) > 0) {
          print line
        }
        close(body_file)
      }
    }
  ' "$CHANGELOG_FILE" > "$NEW_CHANGELOG"
fi

printf '%s\n' "$VERSION" > "$VERSION_FILE"
mv "$NEW_CHANGELOG" "$CHANGELOG_FILE"

printf 'Prepared OpenMUX release %s\n' "$VERSION"
