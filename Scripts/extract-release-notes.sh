#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CHANGELOG_FILE="${CHANGELOG_FILE:-"$ROOT_DIR/CHANGELOG.md"}"

usage() {
  echo "usage: Scripts/extract-release-notes.sh MAJOR.MINOR.PATCH [output-file]" >&2
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 1
fi

VERSION="${1#v}"
OUTPUT_FILE="${2:-}"

if ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: version must be MAJOR.MINOR.PATCH" >&2
  exit 1
fi

if [ ! -f "$CHANGELOG_FILE" ]; then
  echo "error: missing changelog at $CHANGELOG_FILE" >&2
  exit 1
fi

NOTES_FILE="$(mktemp "${TMPDIR:-/tmp}/openmux-release-notes.XXXXXX")"

cleanup() {
  rm -f "$NOTES_FILE"
}

trap cleanup EXIT INT TERM

awk -v version="$VERSION" '
  BEGIN {
    in_section = 0
    found = 0
  }
  $0 == "## " version {
    in_section = 1
    found = 1
    next
  }
  in_section && $0 ~ /^## / {
    exit
  }
  in_section {
    if (started == 0 && $0 ~ /^[[:space:]]*$/) {
      next
    }
    started = 1
    print
  }
  END {
    if (found == 0) {
      exit 2
    }
  }
' "$CHANGELOG_FILE" > "$NOTES_FILE" || {
  status=$?
  if [ "$status" -eq 2 ]; then
    echo "error: CHANGELOG.md is missing a section for $VERSION" >&2
  fi
  exit "$status"
}

if ! grep -Eq '[^[:space:]]' "$NOTES_FILE"; then
  echo "error: CHANGELOG.md section for $VERSION is empty" >&2
  exit 1
fi

if [ -n "$OUTPUT_FILE" ]; then
  mkdir -p "$(dirname "$OUTPUT_FILE")"
  cp "$NOTES_FILE" "$OUTPUT_FILE"
else
  cat "$NOTES_FILE"
fi
