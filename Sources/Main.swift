import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--selftest") { exit(SelfTest.run() ? 0 : 1) }
        if args.contains("--probe") { Probe.run(); exit(0) }
        if args.contains("--keymaps") { Probe.keymaps(); exit(0) }
        if args.contains("--update-now") {
            // Same path as the in-app button, without the UI.
            MainActor.assumeIsolated {
                let u = Updater()
                Task {
                    await u.check(manual: false)
                    print("current \(u.currentVersion): \(u.state)")
                    if case .available = u.state { await u.install() }
                    print("\(u.state)")
                    exit(0)
                }
            }
            dispatchMain()
        }
        if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
            MainActor.assumeIsolated { Snapshotter.render(to: args[i + 1]) }
            exit(0)
        }
        Air01App.main()
    }
}

struct Air01App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = KeyboardModel()
    @StateObject private var updater = Updater()

    var body: some Scene {
        Window("Air01 Control", id: "main") {
            ContentView(model: model, updater: updater)
                .task { await updater.check(manual: false) }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await updater.check(manual: true) } }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - CLI: render UI states offscreen (for checking the layout)

@MainActor
enum Snapshotter {
    static func render(to dir: String) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let states: [(String, KeyboardModel.Link, NSAppearance.Name)] = [
            ("settings-light", .usb, .aqua),
            ("settings-dark", .usb, .darkAqua),
            ("bluetooth", .bluetoothOnly("Air01 BT2"), .aqua),
        ]
        for (name, link, look) in states {
            let model = KeyboardModel(preview: ())
            model.loadSample(link: link)
            let updater = Updater()
            if name == "settings-dark" { updater.state = .available(version: "1.2.0", notes: "", download: Updater.releasesURL) }
            let host = NSHostingView(rootView: ContentView(model: model, updater: updater))
            host.appearance = NSAppearance(named: look)
            let size = NSSize(width: 460, height: link == .usb ? 1240 : 560)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: look)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            let path = (dir as NSString).appendingPathComponent("\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }
}

// MARK: - CLI: read-only probe

enum Probe {
    static func run() {
        let watcher = HIDWatcher(scheduleOnMainRunLoop: false)
        let infos = watcher.devices()
        if infos.isEmpty { print("No Akko/ROYUAN HID devices found.") }
        for i in infos {
            let pairs = i.usagePairs.map { String(format: "%04x:%02x", $0.page, $0.usage) }.joined(separator: ",")
            print("\(i.idString)  \(i.transport.padding(toLength: 22, withPad: " ", startingAt: 0)) \(i.product)  usages[\(pairs)] feature=\(i.maxFeatureReport)\(i.isSettingsInterface ? "  <- settings" : "")")
        }
        guard let s = infos.first(where: \.isSettingsInterface) else { return }
        do {
            let session = try KeyboardSession(s)
            defer { session.close() }
            let snap = try session.readSnapshot()
            print("identify: device \(snap.deviceID) -> \(snap.kind), writable=\(snap.kind.canWrite)")
            print("firmware: \(snap.firmware ?? "-")")
            print("backlight: \(snap.led.map(describe) ?? "-")")
            print("side light: \(snap.side.map(describe) ?? "-")")
            print("profile: \(snap.profile.map { "\($0 + 1)" } ?? "-")  debounce: \(snap.debounce.map(String.init) ?? "-")  autoOS: \(snap.autoOS.map { $0 ? "on" : "off" } ?? "-")")
            if let t = snap.sleep { print("sleep (s): BT \(t.sleepBT)/deep \(t.deepBT)  2.4G \(t.sleep24)/deep \(t.deep24)") }
        } catch {
            print("error: \(error.localizedDescription)")
        }
    }

    /// Read-only: every profile's keymap, compared against profile 1.
    static func keymaps() {
        let watcher = HIDWatcher(scheduleOnMainRunLoop: false)
        guard let s = watcher.devices().first(where: \.isSettingsInterface) else { print("No USB settings interface."); return }
        do {
            let session = try KeyboardSession(s)
            defer { session.close() }
            guard BoardKind.from(id: try session.identify()).canWrite else { print("Not the confirmed Air01."); return }
            let maps = try (0..<4).map { try session.readKeymap(profile: $0) }
            for (p, m) in maps.enumerated() {
                let diff = Keymap.differingSlots(maps[0], m)
                let used = stride(from: 0, to: m.count, by: 4).filter { m[$0..<$0 + 4] != [0, 0, 0, 0] }.count
                print("profile \(p + 1): \(m.count) bytes, \(used) assigned slots, differs from P1 in \(diff.count) slots \(diff.prefix(10))")
            }
            print("P1 first 32 bytes: " + maps[0].prefix(32).map { String(format: "%02x", $0) }.joined(separator: " "))
        } catch {
            print("error: \(error.localizedDescription)")
        }
    }

    static func describe(_ l: Lighting) -> String {
        let name = Effects.find(l.mode, side: false)?.name ?? "mode \(l.mode)"
        let colour = l.rainbow ? "rainbow" : String(format: "#%02X%02X%02X", l.r, l.g, l.b)
        return "mode \(l.mode) (\(name)) speed \(l.speed) brightness \(l.brightness) option \(l.option) \(colour)"
    }
}

// MARK: - CLI: protocol self-test

enum SelfTest {
    static func run() -> Bool {
        var ok = true
        func check(_ cond: Bool, _ name: String) {
            print((cond ? "PASS " : "FAIL ") + name)
            ok = ok && cond
        }
        func hex(_ b: ArraySlice<UInt8>) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

        let ident = Identify.request()
        check(ident[0] == 0x8F && ident[7] == 0x70 && ident.count == 64, "identify packet + bit7 checksum")

        // Static, fixed red, speed 2, brightness 4 on the swapped Air01 wire:
        // flags nibble 8 = fixed colour, speed 4-2 = 2.
        let red = Lighting(mode: 1, speed: 2, brightness: 4, option: 0, rainbow: false, r: 255, g: 0, b: 0)
        let p = red.packet(.air01Main)
        check(Array(p[0...8]) == [0x07, 0x01, 0x02, 0x04, 0x08, 0xFF, 0x00, 0x00, 0xEA],
              "static red LEDPARAM = \(hex(p[0...8]))")

        let wave = Lighting(mode: 4, speed: 4, brightness: 3, option: 2, rainbow: true, r: 0, g: 0, b: 255)
        let w = wave.packet(.air01Main)
        check(w[2] == 0 && w[4] == 0x27, "wave down rainbow: speed 0 on wire, flags 0x27 (\(hex(w[0...8])))")

        let white = Lighting(mode: 1, speed: 0, brightness: 4, option: 0, rainbow: false, r: 255, g: 255, b: 255).packet(.air01Main)
        check(Array(white[5...7]) == [0xFA, 0xFA, 0xFA], "white sent as FAFAFA")
        let black = Lighting(mode: 1, speed: 0, brightness: 4, option: 0, rainbow: false, r: 0, g: 0, b: 0).packet(.air01Main)
        check(Array(black[5...7]) == [8, 8, 8], "near-black floored to 080808")

        // Round-trip: a GET reply has the same layout with the GET opcode.
        var allRoundTrip = true
        for wire in [LedWire.air01Main, LedWire.air01Side] {
            for mode: UInt8 in [1, 2, 4, 7] {
                for speed in 0...4 {
                    for rainbow in [false, true] {
                        let l = Lighting(mode: mode, speed: speed, brightness: 3, option: 1, rainbow: rainbow, r: 10, g: 200, b: 90)
                        var reply = l.packet(wire)
                        reply[0] = wire.getOp
                        if Lighting(reply: reply, wire) != l { allRoundTrip = false }
                    }
                }
            }
        }
        check(allRoundTrip, "lighting encode/decode round-trips")

        // GET nibble 0..6 = firmware preset colour (swapped table).
        var preset = Proto.packet(0x87, [1, 2, 4, 0x01, 0, 0, 0], .bit8)
        preset[4] = 0x01
        let pl = Lighting(reply: preset, .air01Main)
        check(pl.map { ($0.r, $0.g, $0.b) == (0, 255, 0) && !$0.rainbow } ?? false, "preset nibble 1 decodes to green")

        let sleep = SleepTimes(sleepBT: 300, sleep24: 600, deepBT: 1800, deep24: 3600).packet()
        check(sleep[0] == 0x11 && sleep[7] == 0xEE && Array(sleep[8...15]) == [0x2C, 0x01, 0x58, 0x02, 0x08, 0x07, 0x10, 0x0E],
              "sleep packet \(hex(sleep[0...15]))")
        var sreply = sleep; sreply[0] = 0x91
        check(SleepTimes(reply: sreply) == SleepTimes(sleepBT: 300, sleep24: 600, deepBT: 1800, deep24: 3600), "sleep reply decodes at 8..16")

        var refused = Identify.request(); refused[3] = 0xFF
        check(Identify.deviceID(from: refused) == nil, "refusal reply is not a device id")
        var idReply = [UInt8](repeating: 0, count: 64); idReply[0] = 0x8F; idReply[1] = 0xAA; idReply[2] = 0x0F
        check(Identify.deviceID(from: idReply) == 4010, "identify 0x0FAA = 4010")
        check(BoardKind.from(id: 4010).canWrite && !BoardKind.from(id: 3013).canWrite && !BoardKind.from(id: 1).canWrite,
              "writes only on confirmed device 4010")
        check(Identify.format(revision: 0x0309) == "3.09", "revision formatting")

        print(ok ? "All protocol checks passed." : "Some checks FAILED.")
        return ok
    }
}
