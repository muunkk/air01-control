# Air01 Control

An unofficial, tiny native macOS app (SwiftUI + IOKit, no dependencies) for the Akko Air01's
built-in settings: backlight and side-light effect, colour, saturation, brightness, speed and direction,
active profile, debounce and sleep timers. It reads the current values from the keyboard and
saves changes back automatically.

## Install

Download `Air01-Control-<version>.zip` from the
[latest release](https://github.com/muunkk/air01-control/releases/latest), unzip it, and move
**Air01 Control.app** to `~/Applications`. Needs macOS 14 or later; runs natively on Apple
Silicon and Intel.

Releases are signed with a Developer ID and notarized by Apple, so the app opens normally.
If macOS asks, allow it under **System Settings → Privacy & Security → Input Monitoring**, which
it needs to talk to the keyboard. Updates keep the same signature, so the permission carries over.

After that, the app updates itself: it checks GitHub Releases on launch, and the footer button
or **Air01 Control → Check for Updates…** installs a new version and relaunches.

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
- No firmware, flash-erase, bootloader, factory-reset or keymap-write commands exist in the code.
- The app keeps at least 1 s of quiet after every save, because the firmware commits each
  setting to flash and traffic during a commit can lock up the USB endpoint.

## Build and release

```sh
./build.sh           # -> build/Air01 Control.app, universal (version from ./VERSION)
./build.sh install   # also copies it to ~/Applications
./release.sh "notes" # on an up-to-date main: notarize, zip, publish GitHub release v<VERSION>
```

To ship an update: bump `VERSION` in a PR, merge it, then run `release.sh` from `main`.

`build.sh` signs with the first **Developer ID Application** certificate in your keychain
(override with `SIGN_IDENTITY`), using the hardened runtime. Without one it signs ad-hoc, which
runs on your own Mac but can't be released. `release.sh` notarizes and staples the app; it reads
App Store Connect API credentials from a notarytool keychain profile (default `air01-notary`,
override with `NOTARY_PROFILE`), set up once with:

```sh
xcrun notarytool store-credentials air01-notary \
  --key AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-uuid>
```

The updater only installs a download that passes a strict code-signature check and, when the
running app has a Developer ID, carries the same Team ID.

The app icon is drawn in code: `tools/make_icon.sh` regenerates `Resources/AppIcon.icns`
from `tools/make_icon.swift`.

Diagnostics (from the built binary in `Contents/MacOS/Air01Control`):

- `--probe` lists matching HID devices and does a read-only settings read.
- `--keymaps` reads all four profiles' key layouts (read-only).
- `--update-now` runs the updater without the UI.
- `--selftest` checks the packet encoder and decoder.
- `--snapshot <dir>` renders the UI offscreen to PNGs.

Building needs the Xcode Command Line Tools (`xcode-select --install`).

## Credits

Protocol facts come from the open-source [sharkfin](https://github.com/dniminenn/sharkfin)
project (GPL-3.0-or-later): its `docs/PROTOCOL.md`, its device registry, and the Air01's
lighting-effect lists in `app/src-tauri/data/light-layouts.json`. No sharkfin code is included.

## Disclaimer

Air01 Control is an independent project. It is not affiliated with, endorsed by or supported
by Akko. "Akko" and "Air01" are used only to say which keyboard it works with.

The app writes settings to the keyboard's flash memory using a protocol worked out by the
community, not published by Akko. It is provided as is, without any warranty; you use it at
your own risk. See sections 15 and 16 of the license.

## License

Copyright (C) 2026 Mel Boonchan. Licensed under [GPL-3.0-or-later](LICENSE). The license
applies to every version in this repository's history, including earlier commits, branches,
pull requests and releases. Material derived from other projects keeps its original copyright
and notices.

This program is free software: you can redistribute it and/or modify it under the terms of
the GNU General Public License as published by the Free Software Foundation, either version 3
of the License, or (at your option) any later version.
