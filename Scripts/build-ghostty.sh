#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/ghostty"
PINNED_REF_FILE="$VENDOR_DIR/PINNED_REF"
TOOL_DIR="$ROOT_DIR/.build/tools"
ZIG_VERSION="0.15.2"
ZIG_DIR="$TOOL_DIR/zig-$ZIG_VERSION"
ZIG_BIN="$ZIG_DIR/zig"

if [ ! -d "$VENDOR_DIR" ]; then
  echo "Expected vendored ghostty checkout at $VENDOR_DIR" >&2
  exit 1
fi

if [ ! -f "$PINNED_REF_FILE" ]; then
  echo "Missing pinned ref file at $PINNED_REF_FILE" >&2
  exit 1
fi

download_zig() {
  archive="$TOOL_DIR/zig-macos-aarch64-$ZIG_VERSION.tar.xz"
  url="https://ziglang.org/download/$ZIG_VERSION/zig-macos-aarch64-$ZIG_VERSION.tar.xz"

  mkdir -p "$TOOL_DIR"
  if [ ! -f "$archive" ]; then
    curl -L "$url" -o "$archive"
  fi

  rm -rf "$ZIG_DIR"
  mkdir -p "$ZIG_DIR"
  tar -xJf "$archive" -C "$TOOL_DIR"
  extracted="$TOOL_DIR/zig-macos-aarch64-$ZIG_VERSION"
  rm -rf "$ZIG_DIR"
  mv "$extracted" "$ZIG_DIR"
}

ensure_zig() {
  if [ -x "$ZIG_BIN" ] && [ "$("$ZIG_BIN" version)" = "$ZIG_VERSION" ]; then
    return
  fi

  if command -v brew >/dev/null 2>&1; then
    BREW_ZIG="$(brew --prefix zig@0.15 2>/dev/null || true)"
    if [ -n "$BREW_ZIG" ] && [ -x "$BREW_ZIG/bin/zig" ] && [ "$("$BREW_ZIG/bin/zig" version)" = "$ZIG_VERSION" ]; then
      ZIG_BIN="$BREW_ZIG/bin/zig"
      return
    fi
  fi

  if command -v zig >/dev/null 2>&1 && [ "$(zig version)" = "$ZIG_VERSION" ]; then
    ZIG_BIN="$(command -v zig)"
    return
  fi

  download_zig
}

PINNED_REF="$(cat "$PINNED_REF_FILE")"
ensure_zig

echo "Building GhosttyKit xcframework against pinned snapshot: $PINNED_REF"
"$ZIG_BIN" version

cd "$VENDOR_DIR"
"$ZIG_BIN" build \
  -Dapp-runtime=none \
  -Demit-lib-vt=false \
  -Demit-macos-app=false \
  -Demit-xcframework=true \
  -Dxcframework-target=native \
  -Doptimize=ReleaseFast

if [ ! -d "$VENDOR_DIR/macos/GhosttyKit.xcframework" ]; then
  echo "Expected xcframework at $VENDOR_DIR/macos/GhosttyKit.xcframework" >&2
  exit 1
fi

echo "Built $VENDOR_DIR/macos/GhosttyKit.xcframework"
