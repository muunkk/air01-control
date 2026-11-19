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

swiftc -O -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macos14.0" \
  -framework IOKit -framework AppKit -framework SwiftUI \
  Sources/*.swift -o "$BIN"

# Ad-hoc sign so macOS privacy permissions stick to a stable identity.
codesign --force --sign - --identifier local.air01control "$APP" >/dev/null

echo "Built $APP ($(du -sh "$APP" | cut -f1))"

if [[ "${1:-}" == "install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/"Air01 Control.app"
  cp -R "$APP" ~/Applications/
  echo "Installed to ~/Applications/Air01 Control.app"
fi
