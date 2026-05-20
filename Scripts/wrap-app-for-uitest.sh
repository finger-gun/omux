#!/bin/sh
# wrap-app-for-uitest.sh
# Wraps the SwiftPM debug binary in a minimal .app bundle so XCUITest can
# launch it by bundle identifier (dev.fingergun.omux.debug) without touching
# the installed OpenMUX instance (dev.fingergun.omux).
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BIN_DIR="$(swift build --show-bin-path 2>/dev/null)"
APP_BIN="$BIN_DIR/OpenMUXApp"

if [ ! -x "$APP_BIN" ]; then
  echo "error: debug binary not found at $APP_BIN — run 'make build' first" >&2
  exit 1
fi

UITEST_APP_DIR="$ROOT_DIR/.build/UITestApp"
BUNDLE_PATH="$UITEST_APP_DIR/OpenMUX.app"
CONTENTS_DIR="$BUNDLE_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$BUNDLE_PATH"
mkdir -p "$MACOS_DIR"

cp "$APP_BIN" "$MACOS_DIR/OpenMUXApp"

# Mirror the production Contents/Resources layout so runtime resource lookups
# (Ghostty assets, packaged fonts, SwiftPM bundles) succeed during UI tests.
RESOURCES_DIR="$CONTENTS_DIR/Resources"
mkdir -p "$RESOURCES_DIR"

# Copy any .bundle directories produced by SwiftPM alongside the binary.
for bundle in "$BIN_DIR"/*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$RESOURCES_DIR/"
done

# Copy Ghostty runtime share resources if present (fonts, shaders, themes…).
GHOSTTY_SHARE="$ROOT_DIR/Vendor/ghostty/zig-out/share/ghostty"
if [ -d "$GHOSTTY_SHARE" ]; then
  cp -R "$GHOSTTY_SHARE" "$RESOURCES_DIR/ghostty"
fi

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>OpenMUX Debug</string>
    <key>CFBundleExecutable</key>
    <string>OpenMUXApp</string>
    <key>CFBundleIdentifier</key>
    <string>dev.fingergun.omux.debug</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>OpenMUX</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc sign so macOS will launch the bundle.
codesign --force --sign - "$BUNDLE_PATH" >/dev/null

# Register with Launch Services so XCUIApplication(bundleIdentifier:) can find it.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -f "$BUNDLE_PATH"

printf 'UI test app bundle ready at %s\n' "$BUNDLE_PATH"
