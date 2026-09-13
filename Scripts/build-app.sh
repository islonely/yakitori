#!/bin/bash
#
# Builds a launchable WritingTracker.app bundle from the Swift package.
#
# Usage:
#   Scripts/build-app.sh [debug|release]
#
# The resulting bundle is written to dist/Yakitori.app
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"

echo "Building Yakitori ($CONFIG)…"
swift build -c "$CONFIG" --product WritingTracker

# Resolve the build output directory (works for both debug and release).
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/dist/Yakitori.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/WritingTracker" "$APP/Contents/MacOS/WritingTracker"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"

# App icon (generate with Scripts/make-icon.sh if missing).
if [ -f "$ROOT/Packaging/Yakitori.icns" ]; then
    cp "$ROOT/Packaging/Yakitori.icns" "$APP/Contents/Resources/Yakitori.icns"
else
    echo "Note: Packaging/Yakitori.icns not found; run Scripts/make-icon.sh to generate it."
fi

# Copy SwiftPM resource bundles (localization, etc.)
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
    cp -R "$bundle" "$APP/Contents/Resources/"
done
shopt -u nullglob

# Ad-hoc sign so macOS permissions (Accessibility / Automation) work reliably.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
    echo "Warning: codesign failed; permissions may need to be granted again after each build."

echo "Built $APP"
echo "Run with: open \"$APP\""
