#!/usr/bin/env bash
#
# Regenerates the PWA icons under web/icons/ and web/favicon.png from the
# app's icon source.
#
# Source priority:
#   1. macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png
#      (highest resolution rendering of the logo; transparent background)
#   2. msix/assets/icon100x100.png (fallback for the same logo at 100px)
#
# Requires ImageMagick 7 (the `magick` binary; add a `convert` fallback).
#
# Usage:
#   ./scripts/generate-web-icons.sh [path-to-source-icon.png]
#
# Outputs:
#   web/icons/Icon-192.png            (any, transparency preserved)
#   web/icons/Icon-512.png            (any, transparency preserved)
#   web/icons/Icon-maskable-192.png   (full-bleed, brand-dark background)
#   web/icons/Icon-maskable-512.png   (full-bleed, brand-dark background)
#   web/icons/apple-touch-icon.png    (180x180, used by iOS Safari)
#   web/favicon.png                   (32x32)
#
# Maskable note: the OS mask crops to a circle with its radius at 40% of the
# canvas, so the important content must live inside the central ~80% safe
# zone and the rest of the square must be opaque. We scale the source to 68%
# of the canvas and composite it centered over the brand-dark background
# (AppTheme.darkBg = #0F1117), matching the app's default theme.
set -euo pipefail

MAGICK="$(command -v magick || command -v convert || { echo "ImageMagick (magick/convert) not found" >&2; exit 1; })"

SOURCE="${1:-macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png}"
[ -f "$SOURCE" ] || SOURCE="msix/assets/icon100x100.png"
[ -f "$SOURCE" ] || { echo "Icon source not found: $SOURCE" >&2; exit 1; }

OUT="web/icons"
BG="#0F1117"          # AppTheme.darkBg — brand dark for maskable full-bleed
SAFE_ZONE_PCT=68      # content scale relative to canvas (fits the 80% safe zone)

mkdir -p "$OUT"

# "any" purpose icons — transparency preserved.
"$MAGICK" "$SOURCE" -resize 192x192 "$OUT/Icon-192.png"
"$MAGICK" "$SOURCE" -resize 512x512 "$OUT/Icon-512.png"

# Maskable icons — opaque full-bleed square, content centered in safe zone.
"$MAGICK" -size 192x192 "xc:$BG" -depth 8 \
  \( "$SOURCE" -resize $((192 * SAFE_ZONE_PCT / 100))x$((192 * SAFE_ZONE_PCT / 100)) \) \
  -gravity center -composite "$OUT/Icon-maskable-192.png"
"$MAGICK" -size 512x512 "xc:$BG" -depth 8 \
  \( "$SOURCE" -resize $((512 * SAFE_ZONE_PCT / 100))x$((512 * SAFE_ZONE_PCT / 100)) \) \
  -gravity center -composite "$OUT/Icon-maskable-512.png"

# iOS home-screen icon and favicon.
"$MAGICK" "$SOURCE" -resize 180x180 "$OUT/apple-touch-icon.png"
"$MAGICK" "$SOURCE" -resize 32x32 web/favicon.png

echo "Icons regenerated from $SOURCE"
"$MAGICK" identify "$OUT/Icon-192.png" "$OUT/Icon-512.png" \
  "$OUT/Icon-maskable-192.png" "$OUT/Icon-maskable-512.png" \
  "$OUT/apple-touch-icon.png" web/favicon.png | sed 's/^/  /'