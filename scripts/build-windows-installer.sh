#!/bin/bash
# Build CLAN-AI Windows installer (.exe)
# Usage: ./scripts/build-windows-installer.sh
# Requires: Flutter SDK, NSIS (nsis.sourceforge.io)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_ROOT/dist"

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

# Find the generated MSIX file
MSIX_FILE=$(find "$PROJECT_ROOT" -name "clan_ai_*.msix" -o -name "*.msix" 2>/dev/null | head -1)
if [ -z "$MSIX_FILE" ]; then
    echo "ERROR: MSIX file not found after build"
    echo "Expected: clan_ai_*.msix"
    exit 1
fi

echo "    Found MSIX: $MSIX_FILE"

# Step 4: Prepare distribution directory
echo "[4/6] Preparing distribution directory..."
mkdir -p "$DIST_DIR"
cp "$MSIX_FILE" "$DIST_DIR/clan_ai_$(date +%Y%m%d).msix"
MSIX_COPY="$DIST_DIR/clan_ai_$(date +%Y%m%d).msix"
echo "    Copied to: $MSIX_COPY"
echo ""

# Step 5: Build NSIS installer
echo "[5/6] Building NSIS installer..."
# Update the NSIS script with current paths
NSIS_SCRIPT="$PROJECT_ROOT/installer/nsis_installer.nsi"

# Create a temporary NSIS script with correct paths
TEMP_NSI="$DIST_DIR/temp_installer.nsi"
sed "s|${MSIX_SOURCE}|${MSIX_COPY}|g; s|${INSTALLER_OUTPUT}|${DIST_DIR}/CLAN-AI_$(date +%Y%m%d)_Setup.exe|g" \
    "$NSIS_SCRIPT" > "$TEMP_NSI"

if command -v makensis &> /dev/null; then
    makensis "$TEMP_NSI"
    echo "    NSIS installer built successfully"
else
    echo "    WARNING: NSIS (makensis) not found in PATH"
    echo "    Skipping NSIS installer step."
    echo "    The MSIX file at $MSIX_COPY can be installed manually:"
    echo "      1. Double-click the .msix file"
    echo "      2. Or run: Add-AppxPackage -Path $MSIX_COPY"
fi
echo ""

# Step 6: Generate checksums and README
echo "[6/6] Generating distribution files..."

# Create checksum file
sha256sum "$MSIX_COPY" > "$DIST_DIR/checksums.sha256" 2>/dev/null || \
    shasum -a 256 "$MSIX_COPY" > "$DIST_DIR/checksums.sha256" 2>/dev/null || true

# Create a simple README for the release
cat > "$DIST_DIR/README.txt" << EOF
CLAN-AI Windows Installer
=========================

Files in this directory:

  $(basename $MSIX_COPY)     - MSIX package (direct install)
  $(basename $DIST_DIR)/CLAN-AI_*.exe - NSIS installer (if NSIS installed)
  checksums.sha256           - SHA-256 checksums for verification
  README.txt                 - This file

Installation Methods:

  Method 1 (Recommended):
    Double-click the .exe installer file
  
  Method 2 (Direct):
    Double-click the .msix file
    If prompted about sideloading, enable it in:
    Settings > Apps > Developer Options > App Development Licenses
  
  Method 3 (PowerShell):
    Add-AppxPackage -Path "$(basename $MSIX_COPY)"

Requirements:
  - Windows 10 (version 1809) or later
  - Microsoft Account (for sideloading with self-signed cert)

For more information, visit: https://github.com/clan-ai/clan_ai

EOF

# Clean up temp files
rm -f "$TEMP_NSI"

# List output files
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
