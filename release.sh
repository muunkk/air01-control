#!/bin/zsh
# Publish a GitHub release of the version in ./VERSION.
#   1. bump VERSION, merge to main via a PR
#   2. on an up-to-date main: ./release.sh "What changed"
# The app's "Check for Updates" picks up the newest release.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
NOTES="${1:-Air01 Control $VERSION}"
TAG="v$VERSION"
ZIP="build/Air01-Control-$VERSION.zip"

[[ "$(git branch --show-current)" == "main" ]] || { echo "Release from main."; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Working tree not clean."; exit 1; }
git fetch -q origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "Local main differs from origin/main."; exit 1; }
if gh release view "$TAG" >/dev/null 2>&1; then echo "$TAG already exists; bump VERSION."; exit 1; fi

./build.sh
"build/Air01 Control.app/Contents/MacOS/Air01Control" --selftest >/dev/null
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/Air01 Control.app" "$ZIP"

gh release create "$TAG" "$ZIP" --target main --title "Air01 Control $VERSION" --notes "$NOTES"
echo "Released $TAG"
