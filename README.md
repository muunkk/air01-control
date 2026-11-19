# Air01 Control

A tiny native macOS app (~560 KB, SwiftUI + IOKit, no dependencies) for the Akko Air01's
built-in settings: backlight and side-light effect, colour, saturation, brightness, speed and direction,
active profile, debounce and sleep timers. It reads the current values from the keyboard and
saves changes back automatically.

## Use

- **Connect the USB-C cable.** Bluetooth and the 2.4 GHz dongle don't carry the settings
  channel. If the keyboard doesn't show up, slide its mode switch to wired.
- Changes save to the keyboard about a second after you stop adjusting.
- Click ↻ (or switch back to the app) to re-read settings after changing them with Fn shortcuts.

## Safety

- Writes are enabled only for the hardware revision confirmed to use this protocol
  (identify ID **4010**, USB `38ee:0005`). Other Air01 revisions (IDs 3013, 3452, 3658, 3818)
  are shown read-only.
- No firmware, flash-erase, bootloader, factory-reset or keymap commands exist in the code.
- The app keeps at least 1 s of quiet after every save, because the firmware commits each
  setting to flash and traffic during a commit can lock up the USB endpoint.

## Build

```sh
./build.sh           # -> build/Air01 Control.app
./build.sh install   # also copies it to ~/Applications
```

Diagnostics (from the built binary in `Contents/MacOS/Air01Control`):

- `--probe` lists matching HID devices and does a read-only settings read.
- `--selftest` checks the packet encoder and decoder.
- `--snapshot <dir>` renders the UI offscreen to PNGs.

Protocol facts come from the open-source [sharkfin](https://github.com/dniminenn/sharkfin)
project's `docs/PROTOCOL.md` and its device registry. No sharkfin code is included.
