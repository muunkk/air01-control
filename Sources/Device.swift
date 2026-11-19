import Foundation

// High-level reads and writes for the confirmed Air01 (gen2, device 4010).

extension Gen2 {
    /// Base-layer slot write: `[0x0A, profile, slot, 0, 0, apply=1, layer=0]`,
    /// value at 8..<12. Hardware-confirmed on the Air01 (Caps → Esc, read back
    /// and key-press tested by an owner via sharkfin).
    static let setKey: UInt8 = 0x0A
    /// Fn layer: read `[0x90, os, profile, 0xFF, page]`, write
    /// `[0x10, os, profile, slot]` + value at 8..<12. os: 0 Windows, 1 Mac,
    /// 2 Android, 3 iOS. Firmware-documented; every write here is read back.
    static let getFn: UInt8 = 0x90
    static let setFn: UInt8 = 0x10
    static let setAutoOS: UInt8 = 0x17
    /// Options, fields "unestablished"; byte 1 tracks the keyboard's OS mode.
    static let getOptions: UInt8 = 0x89
}

/// Key writes are flash, but lighter than settings: sharkfin uses 400 ms.
private let keyQuiet: TimeInterval = 0.4

enum KeyLayer: Hashable {
    case base
    case fn(os: Int)

    static let osNames = ["Windows", "Mac", "Android", "iOS"]
    var title: String {
        switch self {
        case .base: return "Base layer"
        case .fn(let os): return "Fn layer (\(KeyLayer.osNames[os]))"
        }
    }
}

struct Snapshot {
    var deviceID: UInt32
    var kind: BoardKind
    var firmware: String?
    var led: Lighting?
    var side: Lighting?
    var profile: Int?
    var debounce: Int?
    var sleep: SleepTimes?
    var autoOS: Bool?
    var osMode: Int?
    /// Base layer per profile.
    var keymaps: [Int: [UInt8]] = [:]
    /// Fn layers of the active profile, per OS (Windows and Mac).
    var fnMaps: [Int: [UInt8]] = [:]
}

enum KeyWriteError: LocalizedError {
    case protected
    case notConfirmed(String)
    var errorDescription: String? {
        switch self {
        case .protected: return "That key can't be changed here, so you never lose access to the Fn layer."
        case .notConfirmed(let k): return "The keyboard didn't confirm the change to \(k). Nothing else was touched; try again."
        }
    }
}

extension KeyboardSession {
    /// Read everything this board is known to support. Only shared opcodes
    /// are sent until the board has identified as the confirmed gen2 Air01.
    func readSnapshot() throws -> Snapshot {
        let id = try identify()
        let kind = BoardKind.from(id: id)
        var s = Snapshot(deviceID: id, kind: kind)

        s.led = (try? roundtrip(Proto.packet(Shared.getLed))).flatMap { Lighting(reply: $0, .air01Main) }
        s.side = (try? roundtrip(Proto.packet(Shared.getSideLed))).flatMap { Lighting(reply: $0, .air01Side) }

        guard kind.canWrite else { return s }

        s.profile = (try? roundtrip(Proto.packet(Gen2.getProfile))).map { Int($0[1]) }
        s.debounce = (try? roundtrip(Proto.packet(Gen2.getDebounce))).map { Int($0[1]) }
        s.sleep = (try? roundtrip(Proto.packet(Gen2.getSleep))).flatMap { SleepTimes(reply: $0) }
        s.autoOS = (try? roundtrip(Proto.packet(Gen2.getAutoOS))).map { $0[1] == 1 }
        s.osMode = (try? roundtrip(Proto.packet(Gen2.getOptions))).map { Int($0[1]) }.flatMap { $0 < 4 ? $0 : nil }
        for p in 0..<4 { s.keymaps[p] = try? readKeymap(profile: p) }
        if let p = s.profile {
            for os in 0...1 { s.fnMaps[os] = try? readFn(profile: p, os: os) }
        }

        // gen2 answers 0x80 with zeros over the cable; the keyboard's own
        // version is then in the identify reply at bytes 7..8.
        if let rev = (try? roundtrip(Proto.packet(Gen2.getRevision))).flatMap({ Identify.revisionWord($0, at: 1) })
            ?? (try? roundtrip(Identify.request())).flatMap({ Identify.revisionWord($0, at: 7) }) {
            s.firmware = Identify.format(revision: rev)
        }
        return s
    }

    /// Switch profile, wait out the flash commit, then confirm.
    func switchProfile(_ p: Int) throws -> Int {
        try write(Proto.packet(Gen2.setProfile, [UInt8(p)]))
        let reply = try roundtrip(Proto.packet(Gen2.getProfile))
        return Int(reply[1])
    }

    func setAutoOS(_ on: Bool) throws -> Bool {
        try write(Proto.packet(Gen2.setAutoOS, [on ? 1 : 0]))
        return try roundtrip(Proto.packet(Gen2.getAutoOS))[1] == 1
    }

    // MARK: Keymaps

    private func pageRequest(_ layer: KeyLayer, profile: Int, page: Int) -> [UInt8] {
        switch layer {
        case .base: return Proto.packet(Gen2.getKeymap, [UInt8(profile), 0xFF, UInt8(page), 0])
        case .fn(let os): return Proto.packet(Gen2.getFn, [UInt8(os), UInt8(profile), 0xFF, UInt8(page)])
        }
    }

    /// Eight raw pages. They carry no echo, so the whole map is read twice
    /// and must match.
    func readLayer(_ layer: KeyLayer, profile: Int) throws -> [UInt8] {
        func once() throws -> [UInt8] {
            try (0..<8).flatMap { try readRawPage(pageRequest(layer, profile: profile, page: $0)) }
        }
        for _ in 0..<3 {
            let a = try once(), b = try once()
            if a == b { return a }
        }
        throw HIDError.unexpected("Profile \(profile + 1)'s \(layer.title.lowercased()) read back inconsistently.")
    }

    func readKeymap(profile: Int) throws -> [UInt8] { try readLayer(.base, profile: profile) }
    func readFn(profile: Int, os: Int) throws -> [UInt8] { try readLayer(.fn(os: os), profile: profile) }

    /// Write one slot, then read its page back until it shows the new value.
    func writeSlot(_ layer: KeyLayer, profile: Int, slot: Int, value: [UInt8]) throws {
        guard value.count == 4, (0..<128).contains(slot), Air01Layout.hiddenSlots[slot] == nil else {
            throw KeyWriteError.protected
        }
        if layer == .base && slot == Air01Layout.fnSlot { throw KeyWriteError.protected }

        var pkt: [UInt8]
        switch layer {
        case .base: pkt = Proto.packet(Gen2.setKey, [UInt8(profile), UInt8(slot), 0, 0, 1, 0])
        case .fn(let os): pkt = Proto.packet(Gen2.setFn, [UInt8(os), UInt8(profile), UInt8(slot)])
        }
        pkt.replaceSubrange(8..<12, with: value)
        try write(pkt, quiet: keyQuiet)

        let at = (slot % 16) * 4
        for wait in [0.0, 0.05, 0.15] {
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            let page = try readRawPage(pageRequest(layer, profile: profile, page: slot / 16))
            if Array(page[at..<at + 4]) == value { return }
        }
        throw KeyWriteError.notConfirmed(Air01Layout.key(slot)?.label ?? "slot \(slot)")
    }
}
