#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/ghostty"
PINNED_REF_FILE="$VENDOR_DIR/PINNED_REF"

if [ ! -d "$VENDOR_DIR" ]; then
  echo "Expected vendored ghostty checkout at $VENDOR_DIR" >&2
  exit 1
fi

if [ ! -f "$PINNED_REF_FILE" ]; then
  echo "Missing pinned ref file at $PINNED_REF_FILE" >&2
  exit 1
fi

PINNED_REF="$(cat "$PINNED_REF_FILE")"
echo "Building libghostty bridge against pinned snapshot: $PINNED_REF"
echo "Hook this script into the vendored Ghostty build once the snapshot is checked in."
