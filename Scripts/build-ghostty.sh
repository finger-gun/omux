#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor/ghostty"
PINNED_REF_FILE="$VENDOR_DIR/PINNED_REF"
TOOL_DIR="$ROOT_DIR/.build/tools"
ZIG_VERSION="0.15.2"
ZIG_DIR="$TOOL_DIR/zig-$ZIG_VERSION"
ZIG_BIN="$ZIG_DIR/zig"
OUTPUT_DIR="$VENDOR_DIR/macos/GhosttyKit.xcframework"
BUILD_STAMP_FILE="$VENDOR_DIR/macos/GhosttyKit.xcframework.omux-build-stamp"

if [ ! -d "$VENDOR_DIR" ]; then
  echo "Expected vendored ghostty checkout at $VENDOR_DIR" >&2
  exit 1
fi

if [ ! -f "$PINNED_REF_FILE" ]; then
  echo "Missing pinned ref file at $PINNED_REF_FILE" >&2
  exit 1
fi

download_zig() {
  arch="$(uname -m)"
  case "$arch" in
    arm64)
      zig_arch="aarch64"
      ;;
    x86_64)
      zig_arch="x86_64"
      ;;
    *)
      echo "Unsupported macOS architecture for Zig fallback: $arch" >&2
      exit 1
      ;;
  esac

  archive="$TOOL_DIR/zig-macos-$zig_arch-$ZIG_VERSION.tar.xz"
  url_candidates="
https://ziglang.org/download/$ZIG_VERSION/zig-macos-$zig_arch-$ZIG_VERSION.tar.xz
https://ziglang.org/download/$ZIG_VERSION/zig-$zig_arch-macos-$ZIG_VERSION.tar.xz
"

  mkdir -p "$TOOL_DIR"
  if [ ! -f "$archive" ]; then
    downloaded_url=""
    for url in $url_candidates; do
      if curl -fL "$url" -o "$archive"; then
        downloaded_url="$url"
        break
      fi
      rm -f "$archive"
    done

    if [ -z "$downloaded_url" ]; then
      echo "Unable to download Zig $ZIG_VERSION from any known URL." >&2
      echo "Install zig@0.15 with Homebrew or provide zig $ZIG_VERSION on PATH." >&2
      exit 1
    fi
  fi

  rm -rf "$ZIG_DIR"
  tar -xJf "$archive" -C "$TOOL_DIR"
  extracted="$(find "$TOOL_DIR" -maxdepth 1 -type d -name "zig*${ZIG_VERSION}" ! -path "$ZIG_DIR" | head -n 1)"
  if [ -z "$extracted" ]; then
    echo "Unable to locate extracted Zig directory for version $ZIG_VERSION" >&2
    exit 1
  fi
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
SCRIPT_HASH="$(shasum -a 256 "$0" | awk '{print $1}')"
BUILD_STAMP="pinned_ref=$PINNED_REF;zig=$ZIG_VERSION;script=$SCRIPT_HASH"

if [ -d "$OUTPUT_DIR" ] && [ -f "$BUILD_STAMP_FILE" ] && [ "$(cat "$BUILD_STAMP_FILE")" = "$BUILD_STAMP" ]; then
  echo "Using cached GhosttyKit xcframework for pinned snapshot: $PINNED_REF"
  exit 0
fi

ensure_zig

echo "Building GhosttyKit xcframework against pinned snapshot: $PINNED_REF"
"$ZIG_BIN" version

cd "$VENDOR_DIR"
rm -rf "$OUTPUT_DIR" "$BUILD_STAMP_FILE"
"$ZIG_BIN" build \
  -Dapp-runtime=none \
  -Demit-lib-vt=false \
  -Demit-macos-app=false \
  -Demit-xcframework=true \
  -Dxcframework-target=native \
  -Doptimize=ReleaseFast

if [ ! -d "$OUTPUT_DIR" ]; then
  echo "Expected xcframework at $OUTPUT_DIR" >&2
  exit 1
fi

printf '%s\n' "$BUILD_STAMP" > "$BUILD_STAMP_FILE"

echo "Built $OUTPUT_DIR"
