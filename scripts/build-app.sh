#!/bin/bash
# Builds build/CronBuddy.app (and optionally a DMG).
#   scripts/build-app.sh            release build, ad-hoc signed
#   UNIVERSAL=1 scripts/build-app.sh   arm64 + x86_64
#   CODESIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh   signed for distribution
#   DMG=1 scripts/build-app.sh      also writes build/CronBuddy-<version>.dmg
#   CONFIGURATION=debug scripts/build-app.sh   debug build (includes UI snapshot hooks)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
SCRATCH="${SCRATCH_PATH:-$HOME/Library/Caches/cronbuddy-build}"
CONFIGURATION="${CONFIGURATION:-release}"

# exFAT and network volumes sprout AppleDouble files that SwiftPM would try to compile.
find Sources Tests -name '._*' -delete 2>/dev/null || true

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c "$CONFIGURATION" --product CronBuddy --scratch-path "$SCRATCH" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_DIR="$(swift build -c "$CONFIGURATION" --scratch-path "$SCRATCH" --show-bin-path "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}")"

APP="build/CronBuddy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CronBuddy" "$APP/Contents/MacOS/CronBuddy"
cp assets/app_icon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Support/Info.plist > "$APP/Contents/Info.plist"
dot_clean -m "$APP" 2>/dev/null || true
xattr -cr "$APP"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"

if [[ "${DMG:-0}" == "1" ]]; then
  DMG_PATH="build/CronBuddy-$VERSION.dmg"
  STAGING="$(mktemp -d)"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  rm -f "$DMG_PATH"
  hdiutil create -volname "CronBuddy" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
  rm -rf "$STAGING"
  [[ -n "${CODESIGN_IDENTITY:-}" ]] && codesign --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
  echo "Built $DMG_PATH"
fi
