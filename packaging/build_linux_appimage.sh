#!/usr/bin/env bash
#
# build_linux_appimage.sh — build qMonstatek on Linux and package it as an
# AppImage, bundling the STM32CubeProgrammer CLI so DFU Flash works out of the box.
#
# Run this ON a Linux box that has:
#   - Qt 6 for Linux (set QT_DIR below or via env)
#   - CMake + gcc/clang, plus FUSE (to run the AppImage)
#   - STM32CubeProgrammer installed (so its CLI can be copied into the AppImage)
#
# It downloads linuxdeploy + the Qt plugin on first run.
#
# Usage:  QT_DIR=~/Qt/6.4.2/gcc_64 ./packaging/build_linux_appimage.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."          # repo root

QT_DIR="${QT_DIR:-$HOME/Qt/6.4.2/gcc_64}"
BUILD_DIR="build-linux"
TOOLS_DIR="packaging/.tools"
VERSION="$(grep -m1 -oE 'VERSION [0-9]+\.[0-9]+\.[0-9]+' CMakeLists.txt | awk '{print $2}')"
echo ">> qMonstatek v${VERSION} — Linux AppImage"

export PATH="$QT_DIR/bin:$PATH"
export QMAKE="$QT_DIR/bin/qmake"

# ── 1. Configure + build ──────────────────────────────────────────────
cmake -S . -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$QT_DIR"
cmake --build "$BUILD_DIR" -j"$(nproc)"

BIN="$(find "$BUILD_DIR" -maxdepth 3 -name 'qmonstatek' -type f | head -1)"
[ -n "$BIN" ] || { echo "ERROR: qmonstatek binary not found in $BUILD_DIR"; exit 1; }

# ── 2. Stage an AppDir ────────────────────────────────────────────────
APPDIR="$BUILD_DIR/AppDir"
rm -rf "$APPDIR"
install -Dm755 "$BIN" "$APPDIR/usr/bin/qmonstatek"
install -Dm644 "src/resources/icons/app_icon.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/qmonstatek.png"
cat > "$APPDIR/qmonstatek.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=qMonstatek
Exec=qmonstatek
Icon=qmonstatek
Categories=Utility;
EOF

# ── 3. Bundle the STM32CubeProgrammer CLI (for DFU Flash) ──────────────
CUBE_BIN=""
for c in /opt/st/STM32CubeProgrammer/bin "$HOME/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin" /opt/stm32cubeprog/bin; do
    [ -x "$c/STM32_Programmer_CLI" ] && { CUBE_BIN="$c"; break; }
done
if [ -n "$CUBE_BIN" ]; then
    echo ">> Bundling STM32CubeProgrammer CLI from $CUBE_BIN"
    DEST="$APPDIR/usr/bin/stm32prog/bin"
    mkdir -p "$DEST"
    cp -R "$CUBE_BIN/." "$DEST/"
    # its shared libs usually sit alongside or one level up
    [ -d "$(dirname "$CUBE_BIN")/lib" ] && cp -R "$(dirname "$CUBE_BIN")/lib" "$APPDIR/usr/bin/stm32prog/" || true
else
    echo "!! STM32CubeProgrammer not found — DFU Flash won't be bundled."
fi

# ── 4. linuxdeploy + Qt plugin → AppImage ─────────────────────────────
mkdir -p "$TOOLS_DIR"
grab() { [ -f "$TOOLS_DIR/$1" ] || { echo ">> downloading $1"; curl -fsSL "$2" -o "$TOOLS_DIR/$1"; chmod +x "$TOOLS_DIR/$1"; }; }
grab linuxdeploy.AppImage           "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
grab linuxdeploy-plugin-qt.AppImage "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage"

export OUTPUT="qMonstatek_v${VERSION}_linux.AppImage"
export QML_SOURCES_PATHS="src/qml"
rm -f "$OUTPUT"
"$TOOLS_DIR/linuxdeploy.AppImage" --appdir "$APPDIR" \
    --plugin qt \
    --output appimage
echo ">> Created $OUTPUT"
