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
  echo "Vendor cmux's Ghostty fork (carries the embedding API + stays buildable):"
  echo "  git submodule add https://github.com/manaflow-ai/ghostty vendor/ghostty"
  echo "  git submodule update --init --recursive"
  exit 1
fi

echo "==> Building GhosttyKit.xcframework (this compiles libghostty; takes a while)…"
cd "$GHOSTTY_DIR"

# Produce GhosttyKit.xcframework (static lib + ghostty.h embedding header).
# Native target, matching cmux's documented dev build. Add
# -Dxcframework-target=universal for a distributable Intel+arm64 build.
zig build -Demit-xcframework=true -Doptimize=ReleaseFast

# Locate the produced framework and copy it into place.
PRODUCED="$(find "$GHOSTTY_DIR" -name 'GhosttyKit.xcframework' -maxdepth 4 | head -1 || true)"
if [ -z "$PRODUCED" ]; then
  echo "Could not find GhosttyKit.xcframework after build." >&2
  exit 1
fi
rm -rf "$OUT"
cp -R "$PRODUCED" "$OUT"

# Ghostty's build.zig names the single-target macOS archive `ghostty-internal.a`
# (combined/fat slices get `lib…-fat.a`). SwiftPM's linker rejects static
# libraries without a `lib` prefix, so lib-prefix any such archive and patch the
# xcframework's Info.plist to match.
python3 - "$OUT" <<'PY'
import os, sys, plistlib
xc = sys.argv[1]
plist_path = os.path.join(xc, "Info.plist")
with open(plist_path, "rb") as f:
    info = plistlib.load(f)
changed = False
for lib in info.get("AvailableLibraries", []):
    ident, name = lib["LibraryIdentifier"], lib["LibraryPath"]
    if name.startswith("lib"):
        continue
    newname = "lib" + name
    src = os.path.join(xc, ident, name)
    if os.path.exists(src):
        os.rename(src, os.path.join(xc, ident, newname))
    lib["LibraryPath"] = newname
    if lib.get("BinaryPath") == name:
        lib["BinaryPath"] = newname
    changed = True
    print(f"renamed {ident}/{name} -> {newname}")
if changed:
    with open(plist_path, "wb") as f:
        plistlib.dump(info, f)
    print("patched Info.plist")
PY

echo "==> Done: $OUT"
echo "Now: cd $ROOT && swift build"
