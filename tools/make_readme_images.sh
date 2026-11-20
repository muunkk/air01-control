#!/bin/zsh
# Regenerates docs/screenshot.png and docs/icon.png from the app's own UI.
# Builds the app, renders offscreen snapshots with sample data (no keyboard
# needed), then frames them with tools/make_readme_images.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh >/dev/null
SNAP="$(mktemp -d)"
"build/Air01 Control.app/Contents/MacOS/Air01Control" --snapshot "$SNAP" >/dev/null
mkdir -p docs
swift tools/make_readme_images.swift "$SNAP" Resources/AppIcon.icns docs
rm -rf "$SNAP"
