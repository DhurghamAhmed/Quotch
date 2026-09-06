#!/bin/bash
# Builds Quotch.app without opening Xcode.
#
# Use this when the .xcodeproj gives you trouble, or when you just want a fast
# rebuild loop. Requires the Xcode command line tools (`xcode-select --install`).
#
#   ./build.sh          build into ./build/Quotch.app
#   ./build.sh run      build, then relaunch the app
#
set -euo pipefail

APP_NAME="Quotch"
BUNDLE_ID="com.dhurgham.Quotch"
VERSION="1.0"
DEPLOY_TARGET="14.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$ROOT/$APP_NAME"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "error: swiftc not found. Install the Xcode command line tools:" >&2
  echo "       xcode-select --install" >&2
  exit 1
fi

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) TARGET_TRIPLE="arm64-apple-macos$DEPLOY_TARGET" ;;
  x86_64) TARGET_TRIPLE="x86_64-apple-macos$DEPLOY_TARGET" ;;
  *) echo "error: unsupported architecture $ARCH" >&2; exit 1 ;;
esac

echo "==> Cleaning"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "==> Collecting sources"
SOURCES=()
while IFS= read -r -d '' file; do
  SOURCES+=("$file")
done < <(find "$SRC_DIR" -name '*.swift' -print0)
echo "    ${#SOURCES[@]} Swift files"

echo "==> Compiling for $TARGET_TRIPLE"
swiftc \
  -target "$TARGET_TRIPLE" \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -swift-version 5 \
  -O \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -framework Security \
  -o "$MACOS_DIR/$APP_NAME" \
  "${SOURCES[@]}"

echo "==> Writing Info.plist"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>$APP_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>$BUNDLE_ID</string>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>$DEPLOY_TARGET</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP_DIR" >/dev/null 2>&1 || {
  echo "    warning: ad-hoc signing failed; the app may still run" >&2
}

echo "==> Built $APP_DIR"

if [[ "${1:-}" == "run" ]]; then
  echo "==> Relaunching"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.4
  open "$APP_DIR"
fi
