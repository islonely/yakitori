#!/bin/bash
#
# Installs the built app into /Applications so it behaves like a normal app:
# searchable in Spotlight, listed in Launchpad, and convenient to pin to the
# Dock.
#
# Usage:
#   Scripts/build-app.sh release
#   Scripts/install-app.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/dist/Yakitori.app"
DESTINATION="/Applications/Yakitori.app"

if [ ! -d "$SOURCE" ]; then
    echo "Build the app first: Scripts/build-app.sh release" >&2
    exit 1
fi

echo "Quitting any running copy…"
osascript -e 'tell application "Yakitori" to quit' >/dev/null 2>&1 || true
pkill -f "Yakitori.app/Contents/MacOS/WritingTracker" 2>/dev/null || true
sleep 1

echo "Installing to $DESTINATION…"
rm -rf "$DESTINATION"
cp -R "$SOURCE" "$DESTINATION"

# Re-register with Launch Services so Spotlight/Launchpad pick it up promptly.
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$DESTINATION" >/dev/null 2>&1 || true

echo "Installed $DESTINATION"
echo "Open it from Spotlight/Launchpad, or: open \"$DESTINATION\""
