#!/bin/bash
#
# Generates Packaging/Yakitori.icns.
#
# Usage:
#   Scripts/make-icon.sh [source.png]
#
# If a source PNG (default Packaging/Yakitori-Source.png) exists it is used to
# build every macOS icon size; otherwise a programmatic placeholder is rendered.
# The source should be a square 1024x1024 PNG with the macOS rounded-square shape
# already applied (transparent corners); macOS does not round icons for you.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/Packaging/AppIcon.iconset"
SOURCE="${1:-$ROOT/Packaging/Yakitori-Source.png}"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

if [ -f "$SOURCE" ]; then
    echo "Building iconset from $SOURCE"
    while read -r name size; do
        [ -z "$name" ] && continue
        sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/$name" >/dev/null
    done <<'SIZES'
icon_16x16.png 16
icon_16x16@2x.png 32
icon_32x32.png 32
icon_32x32@2x.png 64
icon_128x128.png 128
icon_128x128@2x.png 256
icon_256x256.png 256
icon_256x256@2x.png 512
icon_512x512.png 512
icon_512x512@2x.png 1024
SIZES
else
    echo "No source PNG found; rendering the placeholder icon"
    swift "$ROOT/Scripts/RenderIcon.swift" "$ICONSET"
fi

iconutil -c icns "$ICONSET" -o "$ROOT/Packaging/Yakitori.icns"
echo "Wrote $ROOT/Packaging/Yakitori.icns"
