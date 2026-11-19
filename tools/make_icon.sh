#!/bin/zsh
# Regenerates Resources/AppIcon.icns from tools/make_icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET" Resources
for s in 16 32 128 256 512; do
  swift tools/make_icon.swift "$SET/icon_${s}x${s}.png" $s >/dev/null
  swift tools/make_icon.swift "$SET/icon_${s}x${s}@2x.png" $((s * 2)) >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns"
