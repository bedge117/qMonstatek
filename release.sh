#!/bin/bash
# release.sh — Build qMonstatek and package the installer
#
# Usage:
#   ./release.sh              Build with current version from CMakeLists.txt
#   ./release.sh 1.3.0        Bump to 1.3.0, then build
#
# What it does:
#   1. Syncs version across CMakeLists.txt, main.cpp, and .iss
#   2. Builds qMonstatek (mingw32-make)
#   3. Copies exe to deploy/
#   4. Compiles Inno Setup installer
#   5. Zips the installer (avoids Windows Mark of the Web blocking)
#   6. Output: installer_output/qMonstatek_v{VERSION}_setup.zip

set -e

# Resolve paths relative to this script's location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$SCRIPT_DIR"
BUILD_DIR="$PROJ_DIR/build"
DEPLOY_DIR="$PROJ_DIR/deploy"
ISS_FILE="$PROJ_DIR/installer/qmonstatek.iss"
MAIN_CPP="$PROJ_DIR/src/main.cpp"
CMAKELISTS="$PROJ_DIR/CMakeLists.txt"
MAKE="C:/Qt/Tools/mingw64/bin/mingw32-make.exe"
ISCC="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
OUT_DIR="$PROJ_DIR/installer_output"

# ── Read current version from CMakeLists.txt ──
current_version=$(grep 'project(qmonstatek VERSION' "$CMAKELISTS" | sed 's/.*VERSION \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/')
if [ -z "$current_version" ]; then
    echo "ERROR: Could not parse version from CMakeLists.txt"
    exit 1
fi

# ── If version argument provided, use it; otherwise use current ──
VERSION="${1:-$current_version}"
echo "=== qMonstatek Release Build v$VERSION ==="

# ── 1. Sync version everywhere ──
echo "[1/6] Syncing version to $VERSION..."

sed -i "s/project(qmonstatek VERSION [0-9]\+\.[0-9]\+\.[0-9]\+/project(qmonstatek VERSION $VERSION/" "$CMAKELISTS"
sed -i "s/setApplicationVersion(\"[0-9]\+\.[0-9]\+\.[0-9]\+\")/setApplicationVersion(\"$VERSION\")/" "$MAIN_CPP"
sed -i "s/#define MyAppVersion \"[0-9]\+\.[0-9]\+\.[0-9]\+\"/#define MyAppVersion \"$VERSION\"/" "$ISS_FILE"

echo "  CMakeLists.txt: $(grep 'project(qmonstatek VERSION' "$CMAKELISTS" | xargs)"
echo "  main.cpp:       $(grep 'setApplicationVersion' "$MAIN_CPP" | xargs)"
echo "  .iss:           $(grep '#define MyAppVersion' "$ISS_FILE" | xargs)"

# ── 2. Build ──
echo "[2/6] Building qMonstatek..."
cd "$BUILD_DIR"
"$MAKE" -j8 2>&1 | tail -5
echo "  Build complete."

# ── 3. Deploy exe ──
echo "[3/6] Copying exe to deploy..."
cp "$BUILD_DIR/src/qmonstatek.exe" "$DEPLOY_DIR/qmonstatek.exe"

# ── 4. Compile installer ──
echo "[4/6] Compiling Inno Setup installer..."
if [ ! -f "$ISCC" ]; then
    echo "ERROR: ISCC.exe not found at: $ISCC"
    echo "Install Inno Setup 6 from https://jrsoftware.org/isdl.php"
    exit 1
fi

"$ISCC" "$ISS_FILE" 2>&1 | tail -5

SETUP_EXE="$OUT_DIR/qMonstatek_v${VERSION}_setup.exe"
if [ ! -f "$SETUP_EXE" ]; then
    echo "ERROR: Installer not found at: $SETUP_EXE"
    exit 1
fi

# ── 5. Zip the installer ──
echo "[5/6] Zipping installer..."
SETUP_ZIP="$OUT_DIR/qMonstatek_v${VERSION}_setup.zip"
rm -f "$SETUP_ZIP"
cd "$OUT_DIR"
powershell -Command "Compress-Archive -Path 'qMonstatek_v${VERSION}_setup.exe' -DestinationPath 'qMonstatek_v${VERSION}_setup.zip'"

if [ ! -f "$SETUP_ZIP" ]; then
    echo "ERROR: Failed to create zip"
    exit 1
fi

# ── 6. Done ──
SIZE=$(du -h "$SETUP_ZIP" | cut -f1)
echo ""
echo "[6/6] Done!"
echo "  Installer ZIP: $SETUP_ZIP"
echo "  Size:          $SIZE"
echo ""
echo "  Upload this file as a release asset on GitHub."
