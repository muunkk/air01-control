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
SHA="$(git rev-parse HEAD)"
[[ "$SHA" == "$(git rev-parse origin/main)" ]] || { echo "Local main differs from origin/main."; exit 1; }
if gh release view "$TAG" >/dev/null 2>&1; then echo "$TAG already exists; bump VERSION."; exit 1; fi

APP="build/Air01 Control.app"
./build.sh
"$APP/Contents/MacOS/Air01Control" --selftest >/dev/null

# Releases must be Developer ID signed and notarized, so downloads open
# without a Gatekeeper warning. Notary credentials live in the keychain:
#   xcrun notarytool store-credentials air01-notary --key <AuthKey.p8> --key-id <id> --issuer <uuid>
PROFILE="${NOTARY_PROFILE:-air01-notary}"
codesign -dvv "$APP" 2>&1 | grep -q "^Authority=Developer ID Application" \
  || { echo "Not signed with a Developer ID; can't notarize."; exit 1; }
rm -f "$ZIP"
ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
echo "Notarizing (usually a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --timeout 30m \
  | tee /dev/stderr | grep -q "status: Accepted" || { echo "Notarization failed."; exit 1; }
xcrun stapler staple "$APP"
spctl -a -t exec -vv "$APP"
# Re-zip so the download carries the stapled ticket (works offline).
rm -f "$ZIP"
ditto -c -k --norsrc --keepParent "$APP" "$ZIP"

gh release create "$TAG" "$ZIP" --target "$SHA" --title "Air01 Control $VERSION" --notes "$NOTES"
echo "Released $TAG"
