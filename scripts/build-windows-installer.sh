#!/bin/bash
# Build CLAN-AI Windows installer (.exe)
# Usage: ./scripts/build-windows-installer.sh
# Requires: Flutter SDK, NSIS (nsis.sourceforge.io)
#
# This is the POSIX (Linux/macOS) convenience path; it cross-builds the
# installer with makensis. On Windows prefer the native
# scripts/build-windows-installer.bat.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_ROOT/dist"
INSTALLER_DIR="$PROJECT_ROOT/installer"
NSIS_SCRIPT="$INSTALLER_DIR/nsis_installer.nsi"

cd "$PROJECT_ROOT"

echo "============================================"
echo "  CLAN-AI Windows Installer Builder"
echo "============================================"
echo ""

# Step 1: Verify Flutter setup
echo "[1/6] Verifying Flutter setup..."
if ! command -v flutter &> /dev/null; then
    echo "ERROR: Flutter is not installed or not in PATH"
    exit 1
fi
flutter --version
flutter pub get
echo ""

# Step 2: Build Windows release binary
echo "[2/6] Building Windows release binary..."
flutter build windows --release
echo ""

# Step 3: Build MSIX package
echo "[3/6] Building MSIX package..."
dart run msix:create
echo ""

# Locate the generated MSIX
MSIX_FILE="$(find "$PROJECT_ROOT/build" -type f -name '*.msix' 2>/dev/null | head -1)"
if [ -z "$MSIX_FILE" ]; then
    echo "ERROR: MSIX file not found under build/"
    echo "Expected something like build/msix/windows/clan_ai_*.msix"
    exit 1
fi
echo "    Found MSIX: $MSIX_FILE"
echo ""

# Step 4: Prepare distribution directory
echo "[4/6] Preparing distribution directory..."
mkdir -p "$DIST_DIR"
DATE_STAMP="$(date +%Y%m%d)"
VERSION="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' pubspec.yaml | head -1)"
if [ -z "$VERSION" ]; then
    echo "ERROR: Could not parse version from pubspec.yaml"
    exit 1
fi
MSIX_COPY="$DIST_DIR/clan_ai_${DATE_STAMP}.msix"
cp "$MSIX_FILE" "$MSIX_COPY"
echo "    Copied to: $MSIX_COPY"
echo "    Version:   $VERSION"
echo ""

# Step 5: Build NSIS installer
echo "[5/6] Building NSIS installer..."
NSIS_OUTPUT="$DIST_DIR/CLAN-AI_Setup.exe"

if ! command -v makensis &> /dev/null; then
    echo "    WARNING: NSIS (makensis) not found in PATH"
    echo "    Skipping NSIS installer step."
    echo "    The MSIX file at $MSIX_COPY can be installed manually:"
    echo "      1. Double-click the .msix file"
    echo "      2. Or run: Add-AppxPackage -Path $MSIX_COPY"
    echo ""
    echo "============================================"
    echo "  Build Complete (MSIX only)"
    echo "============================================"
    ls -lh "$DIST_DIR" | tail -n +2
    exit 0
fi

# NSIS resolves MUI_ICON relative to the .nsi. Generate installer/icon.ico when
# an image tool is available; the .nsi uses NSIS's default icon otherwise.
if [ ! -f "$INSTALLER_DIR/icon.ico" ]; then
    ICON_PNG="$PROJECT_ROOT/msix/assets/icon100x100.png"
    if command -v convert &> /dev/null && [ -f "$ICON_PNG" ]; then
        echo "    Creating installer/icon.ico..."
        convert "$ICON_PNG" -resize 32x32 "$INSTALLER_DIR/icon.ico"
    elif command -v python3 &> /dev/null && [ -f "$ICON_PNG" ] && \
         python3 -c "import PIL" 2>/dev/null; then
        echo "    Creating installer/icon.ico..."
        python3 -c "from PIL import Image; Image.open('$ICON_PNG').resize((32, 32)).save('$INSTALLER_DIR/icon.ico')"
    else
        echo "    No image tool available; using NSIS default icon."
    fi
fi

# The .nsi embeds MSIX_SOURCE at compile time, so pass an absolute path.
makensis \
    "/DMSIX_SOURCE=$MSIX_COPY" \
    "/DDIST_DIR=$DIST_DIR" \
    "/DINSTALLER_OUTPUT=$NSIS_OUTPUT" \
    "/DAPP_VERSION=$VERSION" \
    "$NSIS_SCRIPT"

if [ ! -f "$NSIS_OUTPUT" ]; then
    echo "ERROR: NSIS installer not produced at $NSIS_OUTPUT"
    exit 1
fi
FINAL_EXE="$DIST_DIR/CLAN-AI_${VERSION}_Setup.exe"
mv "$NSIS_OUTPUT" "$FINAL_EXE"
echo "    NSIS installer built: $FINAL_EXE"
echo ""

# Step 6: Generate checksums and README
echo "[6/6] Generating distribution files..."
{
    if command -v sha256sum &> /dev/null; then
        sha256sum "$MSIX_COPY" "$FINAL_EXE"
    else
        shasum -a 256 "$MSIX_COPY" "$FINAL_EXE"
    fi
} > "$DIST_DIR/checksums.sha256" 2>/dev/null || true

cat > "$DIST_DIR/README.txt" << EOF
CLAN-AI Windows Installer
=========================

Files in this directory:

  $(basename "$MSIX_COPY")      - MSIX package (direct install)
  $(basename "$FINAL_EXE")      - NSIS installer (recommended)
  checksums.sha256              - SHA-256 checksums for verification
  README.txt                    - This file

Installation Methods:

  Method 1 (Recommended):
    Double-click the .exe installer

  Method 2 (Direct):
    Double-click the .msix file
    If prompted about sideloading, enable it in:
    Settings > Apps > Developer Options > App Development Licenses

  Method 3 (PowerShell):
    Add-AppxPackage -Path "$(basename "$MSIX_COPY")"

Requirements:
  - Windows 10 (version 1809) or later
  - Microsoft Account (for sideloading with self-signed cert)

For more information, visit: https://github.com/CyberShockwave159/CLAN-AI
EOF

echo ""
echo "============================================"
echo "  Build Complete!"
echo "============================================"
echo ""
echo "Distribution files are in: $DIST_DIR"
echo ""
ls -lh "$DIST_DIR" | tail -n +2
echo ""
echo "Next steps:"
echo "  1. Upload files to GitHub Releases"
echo "  2. Share the .exe installer with users"
echo ""
