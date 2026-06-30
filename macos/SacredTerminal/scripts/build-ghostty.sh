#!/usr/bin/env bash
# Build libghostty into vendor/GhosttyKit.xcframework, the same way cmux vendors
# Ghostty as a submodule and builds GhosttyKit. Run once on macOS before
# `swift build`. Requires: macOS, Xcode command line tools, and Zig (the version
# pinned by Ghostty — see vendor/ghostty/.zig-version), e.g. `brew install zig`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GHOSTTY_DIR="$ROOT/vendor/ghostty"
OUT="$ROOT/vendor/GhosttyKit.xcframework"

if [ ! -d "$GHOSTTY_DIR/.git" ] && [ ! -f "$GHOSTTY_DIR/build.zig" ]; then
  echo "Ghostty source not found at $GHOSTTY_DIR."
  echo "Vendor it as a submodule first:"
  echo "  git submodule add https://github.com/ghostty-org/ghostty vendor/ghostty"
  echo "  git submodule update --init --recursive"
  exit 1
fi

echo "==> Building GhosttyKit.xcframework (this compiles libghostty; takes a while)…"
cd "$GHOSTTY_DIR"

# Ghostty exposes an xcframework build step that produces GhosttyKit.xcframework
# containing the static lib + the ghostty.h embedding header.
zig build -Doptimize=ReleaseFast xcframework

# Locate the produced framework and copy it into place.
PRODUCED="$(find "$GHOSTTY_DIR" -name 'GhosttyKit.xcframework' -maxdepth 4 | head -1 || true)"
if [ -z "$PRODUCED" ]; then
  echo "Could not find GhosttyKit.xcframework after build." >&2
  exit 1
fi
rm -rf "$OUT"
cp -R "$PRODUCED" "$OUT"
echo "==> Done: $OUT"
echo "Now: cd $ROOT && swift build"
