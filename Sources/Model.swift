import AppKit
import IOKit.hid
import SwiftUI

@MainActor
final class KeyboardModel: ObservableObject {
    enum Link: Equatable {
        case searching
        case bluetoothOnly(String)
        case connecting
        case usb
        case needsPermission
        case failed(String)
    }

    enum SaveState: Equatable { case idle, saving, saved, failed(String) }

    @Published var link: Link = .searching
    @Published var save: SaveState = .idle
    @Published var refreshing = false

    @Published var deviceID: UInt32?
    @Published var kind: BoardKind = .unknown
    @Published var usbID: String?
    @Published var firmware: String?
    @Published var led: Lighting?
    @Published var side: Lighting?
    @Published var profile: Int?
    @Published var debounce: Int?
    @Published var sleep: SleepTimes?
    @Published var autoOS: Bool?
    @Published var keymaps: [Int: [UInt8]] = [:]
    @Published var fnMaps: [Int: [UInt8]] = [:]
    @Published var osMode: Int?
    @Published var keyBusy = false
    @Published var keyStatus: String?
    @Published var backupProgress: (String, Double)?
    @Published var backupError: String?
    @Published var restoreResult: String?
    @Published var lastBackup: URL?
    private(set) var backedUpThisSession = false

    var writable: Bool { link == .usb && kind.canWrite }

    /// Fill with sample values (snapshot rendering only).
    func loadSample(link: Link) {
        self.link = link
        guard link == .usb else { return }
        kind = .air01Gen2; deviceID = 4010; firmware = "3.09"
        led = Lighting(mode: 4, speed: 3, brightness: 4, option: 0, rainbow: false, r: 0, g: 120, b: 255)
        side = Lighting(mode: 2, speed: 2, brightness: 3, option: 0, rainbow: true, r: 255, g: 0, b: 0)
        profile = 0; debounce = 5; autoOS = true
        var base = [UInt8](repeating: 0, count: Keymap.bytes)
        for k in Air01Layout.keys { base.replaceSubrange(k.slot * 4..<k.slot * 4 + 4, with: k.factory) }
        var gaming = base
        gaming.replaceSubrange(3 * 4..<3 * 4 + 4, with: KeyAction.key(0x29).bytes)  // Caps Lock -> Esc
        keymaps = [0: base, 1: gaming, 2: base, 3: base]
        var fnMac = [UInt8](repeating: 0, count: Keymap.bytes)
        fnMac.replaceSubrange(6 * 4..<6 * 4 + 4, with: KeyAction.media(0x70).bytes)
        fnMac.replaceSubrange(12 * 4..<12 * 4 + 4, with: KeyAction.media(0x6F).bytes)
        fnMaps = [0: fnMac, 1: fnMac]
        osMode = 1
        sleep = SleepTimes(sleepBT: 300, sleep24: 300, deepBT: 1800, deep24: 1800)
    }

    private var watcher: HIDWatcher?
    private var session: KeyboardSession?
    private var pending: [String: Task<Void, Never>] = [:]
    private var rescanTask: Task<Void, Never>?

    /// A model with no hardware behind it, for rendering snapshots.
    init(preview: Void) {}

    init() {
        let watcher = HIDWatcher()
        self.watcher = watcher
        watcher.onChange = { [weak self] in
            Task { @MainActor in self?.scheduleRescan() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.link == .usb, self.pending.isEmpty else { return }
                await self.refresh()
            }
        }
        scheduleRescan(after: 0)
    }

    // MARK: Connection

    /// IOKit fires removal before the device list updates; give it a beat.
    func scheduleRescan(after delay: Double = 0.4) {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
            guard !Task.isCancelled else { return }
            self?.rescan()
        }
    }

    private func rescan() {
        guard let watcher else { return }
        let infos = watcher.devices()
        if let s = infos.first(where: \.isSettingsInterface) {
            if let cur = session, CFEqual(cur.info.device, s.device), link != .needsPermission { return }
            connect(s)
            return
        }
        disconnect()
        if let bt = infos.first(where: \.isBluetooth) {
            link = .bluetoothOnly(bt.product)
        } else if infos.contains(where: \.isUSB) {
            link = .failed("Found a USB device from this maker but no settings interface on it. If that's the 2.4 GHz dongle, plug in the keyboard's USB-C cable instead.")
        } else {
            link = .searching
        }
    }

    private func connect(_ info: HIDInfo) {
        disconnect()
        link = .connecting
        usbID = info.idString
        do {
            session = try KeyboardSession(info)
        } catch HIDError.notPermitted {
            link = .needsPermission
            return
        } catch {
            link = .failed(error.localizedDescription)
            return
        }
        Task { await refresh() }
    }

    private func disconnect() {
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        session?.close()
        session = nil
        deviceID = nil; firmware = nil; usbID = nil
        led = nil; side = nil; profile = nil; debounce = nil; sleep = nil; autoOS = nil
        keymaps = [:]; fnMaps = [:]; osMode = nil; keyStatus = nil
        kind = .unknown
        save = .idle
    }

    func retry() { disconnect(); scheduleRescan(after: 0) }

    func requestPermission() {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Reading

    func refresh() async {
        guard let session else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let s = try await session.run { try $0.readSnapshot() }
            guard self.session === session else { return }
            deviceID = s.deviceID
            kind = s.kind
            firmware = s.firmware
            led = s.led
            side = s.side
            profile = s.profile
            debounce = s.debounce
            sleep = s.sleep
            autoOS = s.autoOS
            keymaps = s.keymaps
            fnMaps = s.fnMaps
            osMode = s.osMode
            link = .usb
        } catch {
            link = .failed(error.localizedDescription)
        }
    }

    // MARK: Writing

    /// Coalesce rapid changes (sliders, colour wheel) into one flash write.
    private func schedule(_ key: String, delay: Double = 0.35, _ op: @escaping (KeyboardSession) throws -> Void) {
        guard writable, let session else { return }
        pending[key]?.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
            guard !Task.isCancelled, let self else { return }
            self.save = .saving
            do {
                try await session.run(op)
                if self.pending.count <= 1 { self.save = .saved }
            } catch {
                self.save = .failed(error.localizedDescription)
            }
            if self.pending[key]?.isCancelled == false { self.pending[key] = nil }
        }
        pending[key] = task
    }

    func setLighting(_ l: Lighting, side isSide: Bool) {
        if isSide { side = l } else { led = l }
        let wire = isSide ? LedWire.air01Side : LedWire.air01Main
        schedule(isSide ? "side" : "led") { try $0.write(l.packet(wire)) }
    }

    func setDebounce(_ v: Int) {
        let v = min(max(v, 1), 10)
        debounce = v
        schedule("debounce") { try $0.write(Proto.packet(Gen2.setDebounce, [UInt8(v)])) }
    }

    func setSleep(_ t: SleepTimes) {
        sleep = t
        schedule("sleep") { try $0.write(t.packet()) }
    }

    func setProfile(_ p: Int) {
        guard writable, let session, p != profile else { return }
        // Flush anything pending for the old profile first (they share the queue).
        save = .saving
        Task {
            do {
                let got = try await session.run { try $0.switchProfile(p) }
                if got != p { throw HIDError.unexpected("The keyboard didn't take the profile switch.") }
                await refresh()
                save = .saved
            } catch {
                save = .failed(error.localizedDescription)
                await refresh()
            }
        }
    }

    /// One-line description of how a profile's keys differ from the factory layout.
    func keymapSummary(_ p: Int) -> String? {
        guard let m = keymaps[p], m.count == Keymap.bytes else { return nil }
        let changed = Air01Layout.keys.filter { Array(Keymap.slot(m, $0.slot)) != $0.factory }
        if changed.isEmpty { return "Factory key layout" }
        let shown = changed.prefix(2).map { "\($0.label) → \(KeyAction(Array(Keymap.slot(m, $0.slot))).name())" }
        let more = changed.count > 2 ? " +\(changed.count - 2) more" : ""
        return shown.joined(separator: ", ") + more
    }

    // MARK: Keys

    /// The layer map shown in the key editor (active profile).
    func layerMap(_ layer: KeyLayer) -> [UInt8]? {
        switch layer {
        case .base: return profile.flatMap { keymaps[$0] }
        case .fn(let os): return fnMaps[os]
        }
    }

    func value(_ layer: KeyLayer, slot: Int) -> [UInt8]? {
        guard let m = layerMap(layer), m.count == Keymap.bytes else { return nil }
        return Array(Keymap.slot(m, slot))
    }

    /// Write one key on the active profile. The first change of a session
    /// saves a full backup before anything is written.
    func assign(_ action: KeyAction, to slot: Int, on layer: KeyLayer) async {
        guard writable, let session, let p = profile, !keyBusy else { return }
        keyBusy = true
        defer { keyBusy = false }
        if !backedUpThisSession {
            keyStatus = "Saving a backup before your first change…"
            guard await backUpNow() != nil else {
                keyStatus = "Couldn't save a backup, so nothing was changed."
                return
            }
        }
        let name = Air01Layout.key(slot)?.label ?? "key"
        keyStatus = "Saving \(name)…"
        let bytes = action.bytes
        do {
            try await session.run { try $0.writeSlot(layer, profile: p, slot: slot, value: bytes) }
            switch layer {
            case .base: keymaps[p]?.replaceSubrange(slot * 4..<slot * 4 + 4, with: bytes)
            case .fn(let os): fnMaps[os]?.replaceSubrange(slot * 4..<slot * 4 + 4, with: bytes)
            }
            keyStatus = "Saved: \(name) now does \(action.name(fnLayer: layer != .base)). Try it out."
        } catch {
            keyStatus = error.localizedDescription
        }
    }

    // MARK: Backup

    @discardableResult
    func backUpNow() async -> URL? {
        guard writable, let session else { return nil }
        backupProgress = ("Starting…", 0)
        defer { backupProgress = nil }
        do {
            let b = try await session.run { [weak self] s in
                try s.makeBackup { msg, f in Task { @MainActor in self?.backupProgress = (msg, f) } }
            }
            let url = try b.save()
            lastBackup = url
            backedUpThisSession = true
            return url
        } catch {
            backupError = error.localizedDescription
            return nil
        }
    }

    func restore(from url: URL) async {
        guard writable, let session else { return }
        backupProgress = ("Starting…", 0)
        do {
            let b = try Backup.load(url)
            let changed = try await session.run { [weak self] s in
                try s.restore(b) { msg, f in Task { @MainActor in self?.backupProgress = (msg, f) } }
            }
            backupProgress = nil
            restoreResult = changed == 0 ? "Restored. Keys already matched the backup; lighting and settings were reapplied."
                : "Restored \(changed) key\(changed == 1 ? "" : "s") plus lighting and settings."
            await refresh()
        } catch {
            backupProgress = nil
            backupError = error.localizedDescription
            await refresh()
        }
    }

    func setAutoOS(_ on: Bool) {
        guard writable, let session else { return }
        autoOS = on
        save = .saving
        Task {
            do {
                let got = try await session.run { try $0.setAutoOS(on) }
                autoOS = got
                save = got == on ? .saved : .failed("The keyboard didn't take the change.")
            } catch {
                save = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Bindings

    func lighting(_ isSide: Bool) -> Lighting { (isSide ? side : led) ?? .placeholder }

    func bind<T: Equatable>(_ isSide: Bool, _ kp: WritableKeyPath<Lighting, T>) -> Binding<T> {
        Binding(
            get: { self.lighting(isSide)[keyPath: kp] },
            set: { v in
                var l = self.lighting(isSide)
                guard l[keyPath: kp] != v else { return }
                l[keyPath: kp] = v
                self.setLighting(l, side: isSide)
            }
        )
    }

    func bindMode(_ isSide: Bool) -> Binding<UInt8> {
        Binding(
            get: { self.lighting(isSide).mode },
            set: { m in
                var l = self.lighting(isSide)
                guard l.mode != m else { return }
                l.mode = m
                let e = Effects.find(m, side: isSide)
                if Int(l.option) >= (e?.options.count ?? 0) { l.option = 0 }
                if let e, l.speed > e.maxSpeed { l.speed = e.maxSpeed }
                self.setLighting(l, side: isSide)
            }
        )
    }

    func bindColor(_ isSide: Bool) -> Binding<Color> {
        Binding(
            get: {
                let l = self.lighting(isSide)
                return Color(.sRGB, red: Double(l.r) / 255, green: Double(l.g) / 255, blue: Double(l.b) / 255)
            },
            set: { c in
                guard let ns = NSColor(c).usingColorSpace(.sRGB) else { return }
                func byte(_ x: CGFloat) -> UInt8 { UInt8(min(max(x * 255, 0), 255).rounded()) }
                var l = self.lighting(isSide)
                let (r, g, b) = (byte(ns.redComponent), byte(ns.greenComponent), byte(ns.blueComponent))
                guard (l.r, l.g, l.b) != (r, g, b) || l.rainbow else { return }
                (l.r, l.g, l.b) = (r, g, b)
                l.rainbow = false
                self.setLighting(l, side: isSide)
            }
        )
    }

    /// Last hue seen per light, so dragging saturation down to 0 (white)
    /// and back up returns to the same colour instead of red.
    private var hueMemory: [Bool: CGFloat] = [:]

    private func hsb(_ l: Lighting) -> (h: CGFloat, s: CGFloat, v: CGFloat) {
        let c = NSColor(srgbRed: CGFloat(l.r) / 255, green: CGFloat(l.g) / 255, blue: CGFloat(l.b) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        return (h, s, v)
    }

    func bindSaturation(_ isSide: Bool) -> Binding<Double> {
        Binding(
            get: { Double(self.hsb(self.lighting(isSide)).s) },
            set: { newS in
                var l = self.lighting(isSide)
                let cur = self.hsb(l)
                if cur.s > 0.02 { self.hueMemory[isSide] = cur.h }
                let hue = self.hueMemory[isSide] ?? cur.h
                let value = cur.v > 0.05 ? cur.v : 1
                let c = NSColor(colorSpace: .sRGB, hue: hue, saturation: CGFloat(newS), brightness: value, alpha: 1)
                func byte(_ x: CGFloat) -> UInt8 { UInt8(min(max(x * 255, 0), 255).rounded()) }
                let rgb = (byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
                guard (l.r, l.g, l.b) != rgb else { return }
                (l.r, l.g, l.b) = rgb
                l.rainbow = false
                self.setLighting(l, side: isSide)
            }
        )
    }

    func setPreset(_ rgb: (UInt8, UInt8, UInt8), side isSide: Bool) {
        var l = lighting(isSide)
        (l.r, l.g, l.b) = rgb
        l.rainbow = false
        setLighting(l, side: isSide)
    }
}
