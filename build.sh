#!/bin/zsh
# Builds "Air01 Control.app" with swiftc (no Xcode project needed).
#   ./build.sh            build into ./build
#   ./build.sh install    build, then copy to ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Air01 Control.app"
BIN="$APP/Contents/MacOS/Air01Control"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
VERSION="$(tr -d '[:space:]' < VERSION)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

# Universal binary: Apple Silicon and Intel.
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library \
    -target "$ARCH-apple-macos14.0" \
    -framework IOKit -framework AppKit -framework SwiftUI \
    Sources/*.swift -o "build/Air01Control-$ARCH"
done
lipo -create build/Air01Control-arm64 build/Air01Control-x86_64 -output "$BIN"
rm -f build/Air01Control-arm64 build/Air01Control-x86_64

# Ad-hoc sign so macOS privacy permissions stick to a stable identity.
codesign --force --sign - --identifier io.github.muunkk.air01control "$APP" >/dev/null

echo "Built $APP v$VERSION ($(du -sh "$APP" | cut -f1))"

if [[ "${1:-}" == "install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/"Air01 Control.app"
  cp -R "$APP" ~/Applications/
  echo "Installed to ~/Applications/Air01 Control.app"
fi
