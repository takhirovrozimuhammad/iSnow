#!/bin/zsh
# Builds iSnow.app (release, universal: Apple silicon + Intel) into build/ and signs it.
#   ./build.sh             build/iSnow.app
#   ./build.sh --install   the same, then copies it to ~/Applications and launches it
#   ./build.sh --no-sign   leave the app unsigned (used by scripts/release.sh, which signs it itself)
# Signing uses your "Apple Development" certificate when you have one – macOS then keeps the
# Accessibility permission across rebuilds. Without a certificate the app is signed ad hoc.
# Works with full Xcode or with just the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=0 SIGN=1
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --no-sign) SIGN=0 ;;
    *) echo "usage: ./build.sh [--install] [--no-sign]" >&2; exit 64 ;;
  esac
done

mkdir -p build
BIN="build/iSnow-universal"
if [[ -z "${ISNOW_SEPARATE_ARCHS:-}" ]] && xcrun --find xcodebuild >/dev/null 2>&1; then
  # Full Xcode: SwiftPM builds both architectures in one go.
  swift build -c release --arch arm64 --arch x86_64
  cp "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/iSnow" "$BIN"
else
  # Command Line Tools only (no xcodebuild): build each architecture on its own and join them.
  SLICES=()
  for arch in arm64 x86_64; do
    triple="${arch}-apple-macosx14.0"
    scratch=".build/cli-${arch}"
    echo "Building ${arch}…"
    swift build -c release --triple "$triple" --scratch-path "$scratch"
    SLICES+=("$(swift build -c release --triple "$triple" --scratch-path "$scratch" --show-bin-path)/iSnow")
  done
  lipo -create -output "$BIN" "${SLICES[@]}"
fi
echo "Architectures: $(lipo -archs "$BIN")"

APP="build/iSnow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$BIN" "$APP/Contents/MacOS/iSnow"
strip -x "$APP/Contents/MacOS/iSnow"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp LICENSE NOTICE.md "$APP/Contents/Resources/"

# The icon is generated; regenerate it when scripts/make-icon.swift changed.
if [[ ! -f build/AppIcon.icns || scripts/make-icon.swift -nt build/AppIcon.icns || Sources/iSnow/BrandMark.swift -nt build/AppIcon.icns ]]; then
  echo "Generating the app icon…"
  rm -rf build/AppIcon.iconset
  swiftc Sources/iSnow/BrandMark.swift scripts/make-icon.swift -o build/make-icon
  build/make-icon build
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
  rm -rf build/AppIcon.iconset
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if (( SIGN )); then
  # Pick the certificate by its SHA-1 hash – names can be ambiguous (several certificates, same name).
  CERT="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development/ {print $2; exit}')"
  if [[ -n "$CERT" ]]; then
    codesign --force --sign "$CERT" "$APP"
    echo "Signed with: $(security find-identity -v -p codesigning | awk -F'"' -v h="$CERT" '$0 ~ h {print $2; exit}') ($CERT)"
  else
    codesign --force --sign - "$APP"
    echo "Signed ad hoc (no Apple Development certificate found)"
  fi
fi
echo "Built: $APP"

if (( INSTALL )); then
  # Quit only the installed copy (not a debug build started from .build/), and wait for it to exit.
  pkill -f "/Applications/iSnow.app/Contents/MacOS/iSnow" 2>/dev/null || true
  for _ in {1..20}; do
    pgrep -f "/Applications/iSnow.app/Contents/MacOS/iSnow" >/dev/null || break
    sleep 0.1
  done
  mkdir -p ~/Applications
  rm -rf ~/Applications/iSnow.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/iSnow.app
  echo "Installed and launched: ~/Applications/iSnow.app"
fi
