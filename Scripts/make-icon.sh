#!/bin/bash
#
# Generates Packaging/Yakitori.icns from a programmatically rendered icon.
#
# Usage:
#   Scripts/make-icon.sh
#
# To use your own artwork instead, replace Packaging/Yakitori.icns with an .icns
# built from a 1024x1024 PNG (or run `iconutil` on your own .iconset).
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/Packaging/AppIcon.iconset"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

swift "$ROOT/Scripts/RenderIcon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ROOT/Packaging/Yakitori.icns"

echo "Wrote $ROOT/Packaging/Yakitori.icns"
