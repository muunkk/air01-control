# Air01 Control

A tiny native macOS app (~560 KB, SwiftUI + IOKit, no dependencies) for the Akko Air01's
built-in settings: backlight and side-light effect, colour, saturation, brightness, speed and direction,
active profile, debounce and sleep timers. It reads the current values from the keyboard and
saves changes back automatically.

## Install

Download `Air01-Control-<version>.zip` from the
[latest release](https://github.com/muunkk/air01-control/releases/latest), unzip it, and move
**Air01 Control.app** to `~/Applications`. After that, the app updates itself: it checks on
launch, and the footer button or **Air01 Control → Check for Updates…** installs a new
version and relaunches. The repo is private, so checking uses the GitHub CLI login on this
Mac (`brew install gh && gh auth login`).

## Use

- **Connect the USB-C cable.** Bluetooth and the 2.4 GHz dongle don't carry the settings
  channel. If the keyboard doesn't show up, slide its mode switch to wired.
- Changes save to the keyboard about a second after you stop adjusting.
- Click ↻ (or switch back to the app) to re-read settings after changing them with Fn shortcuts.
- **Profiles** shows all four profiles and marks the active one; click one to switch. On the
  Air01, profiles hold separate key layouts, so each card says how its keys differ from
  profile 1. Lighting is shared: a scan of all four profiles read identical lighting.

## Safety

- Writes are enabled only for the hardware revision confirmed to use this protocol
  (identify ID **4010**, USB `38ee:0005`). Other Air01 revisions (IDs 3013, 3452, 3658, 3818)
  are shown read-only.
- No firmware, flash-erase, bootloader, factory-reset or keymap commands exist in the code.
- The app keeps at least 1 s of quiet after every save, because the firmware commits each
  setting to flash and traffic during a commit can lock up the USB endpoint.

## Build and release

```sh
./build.sh           # -> build/Air01 Control.app (version from ./VERSION)
./build.sh install   # also copies it to ~/Applications
./release.sh "notes" # on an up-to-date main: zip the app, publish GitHub release v<VERSION>
```

To ship an update: bump `VERSION` in a PR, merge it, then run `release.sh` from `main`.

The app icon is drawn in code: `tools/make_icon.sh` regenerates `Resources/AppIcon.icns`
from `tools/make_icon.swift`.

Diagnostics (from the built binary in `Contents/MacOS/Air01Control`):

- `--probe` lists matching HID devices and does a read-only settings read.
- `--keymaps` reads all four profiles' key layouts (read-only).
- `--update-now` runs the updater without the UI.
- `--selftest` checks the packet encoder and decoder.
- `--snapshot <dir>` renders the UI offscreen to PNGs.

Protocol facts come from the open-source [sharkfin](https://github.com/dniminenn/sharkfin)
project's `docs/PROTOCOL.md` and its device registry. No sharkfin code is included.
