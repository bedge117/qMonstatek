#!/usr/bin/env bash
#
# build_macos_dmg.sh — build qMonstatek on macOS and package it as a .dmg,
# bundling the STM32CubeProgrammer CLI so DFU Flash works out of the box.
#
# Run this ON a Mac that has:
#   - Qt 6 for macOS (set QT_DIR below or via env)
#   - CMake + a compiler (Xcode command line tools)
#   - STM32CubeProgrammer installed (so its CLI can be copied into the bundle)
#
# Usage:  QT_DIR=~/Qt/6.4.2/macos ./packaging/build_macos_dmg.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."          # repo root

QT_DIR="${QT_DIR:-$HOME/Qt/6.4.2/macos}"
BUILD_DIR="build-macos"
VERSION="$(grep -m1 -oE 'VERSION [0-9]+\.[0-9]+\.[0-9]+' CMakeLists.txt | awk '{print $2}')"
echo ">> qMonstatek v${VERSION} — macOS package"

[ -x "$QT_DIR/bin/macdeployqt" ] || { echo "ERROR: macdeployqt not found under QT_DIR=$QT_DIR"; exit 1; }

# ── 1. Configure + build ──────────────────────────────────────────────
cmake -S . -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$QT_DIR"
cmake --build "$BUILD_DIR" -j"$(sysctl -n hw.ncpu)"

APP_PATH="$(find "$BUILD_DIR" -maxdepth 4 -name 'qmonstatek.app' -type d | head -1)"
[ -n "$APP_PATH" ] || { echo "ERROR: qmonstatek.app not found in $BUILD_DIR"; exit 1; }
echo ">> App bundle: $APP_PATH"

# ── 2. Bundle Qt frameworks/plugins/QML ───────────────────────────────
"$QT_DIR/bin/macdeployqt" "$APP_PATH" -qmldir="src/qml"

# ── 3. Bundle the STM32CubeProgrammer CLI (for DFU Flash) ──────────────
CUBE_RES="/Applications/STMicroelectronics/STM32Cube/STM32CubeProgrammer/STM32CubeProgrammer.app/Contents/Resources"
DEST="$APP_PATH/Contents/Resources/stm32prog"
if [ -d "$CUBE_RES/bin" ]; then
    echo ">> Bundling STM32CubeProgrammer CLI from $CUBE_RES"
    mkdir -p "$DEST/bin"
    cp -R "$CUBE_RES/bin/." "$DEST/bin/"
    if [ -d "$CUBE_RES/api/lib" ]; then
        mkdir -p "$DEST/api/lib"
        cp -R "$CUBE_RES/api/lib/." "$DEST/api/lib/"
    fi
else
    echo "!! STM32CubeProgrammer not found at the default location."
    echo "!! DFU Flash won't be bundled; users would need to install it separately."
fi

# ── 4. Create the .dmg ────────────────────────────────────────────────
DMG="qMonstatek_v${VERSION}_macos.dmg"
rm -f "$DMG"
hdiutil create -volname "qMonstatek" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG"
echo ">> Created $DMG"
echo ">> NOTE: unsigned build — first launch needs right-click → Open (or: xattr -dr com.apple.quarantine qmonstatek.app)"
