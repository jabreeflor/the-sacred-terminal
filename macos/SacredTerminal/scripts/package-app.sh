#!/usr/bin/env bash
# Assemble SacredTerminal.app from `swift build` output + packaging/Info.plist.
# Run on macOS after build-ghostty.sh. For a signed/notarized build, open the
# package in Xcode instead (File > Open > Package.swift) and archive.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"

echo "==> swift build -c $CONFIG"
cd "$ROOT"
swift build -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/SacredTerminal"
APP="$ROOT/.build/SacredTerminal.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SacredTerminal"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"

# App icon (transparent-corner squircle; see Resources/AppIcon.png).
if [ -f "$ROOT/packaging/AppIcon.icns" ]; then
  cp "$ROOT/packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Bundle the GhosttyKit framework next to the binary.
if [ -d "$ROOT/vendor/GhosttyKit.xcframework" ]; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "$ROOT/vendor/GhosttyKit.xcframework" "$APP/Contents/Frameworks/"
fi

# Copy the resource bundle (brand icons).
cp -R "$ROOT/.build/$CONFIG/"*.bundle "$APP/Contents/Resources/" 2>/dev/null || true

echo "==> Built $APP"
echo "Run:  open '$APP'   (or codesign + notarize for distribution)"
