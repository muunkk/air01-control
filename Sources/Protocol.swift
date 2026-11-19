import Foundation

// Wire protocol for the Akko Air01 (ROYUAN "gen2" firmware, ry6602 chip).
//
// Every exchange is a 64-byte HID feature report, report ID 0, on the vendor
// collection (usage page 0xFFFF, usage 1 or 2). Byte 0 is the opcode; GET
// replies echo it. Facts here come from the open sharkfin project's
// docs/PROTOCOL.md and its hardware-confirmed registry entry for this board
// (device 4010 on 38ee:0005). Nothing in this file can erase flash or enter
// a bootloader: those opcodes are deliberately absent.

enum Proto {
    static let reportLength = 64

    enum Checksum { case bit7, bit8 }

    /// `0xFF - (sum & 0xFF)` over bytes 0..<7 (stored at 7) or 0..<8 (stored at 8).
    static func packet(_ op: UInt8, _ payload: [UInt8] = [], _ ck: Checksum = .bit7) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: reportLength)
        b[0] = op
        for (i, v) in payload.enumerated() { b[1 + i] = v }
        applyChecksum(&b, ck)
        return b
    }

    static func applyChecksum(_ b: inout [UInt8], _ ck: Checksum) {
        let n = ck == .bit7 ? 7 : 8
        let sum = b[0..<n].reduce(0) { $0 + Int($1) }
        b[n] = 0xFF &- UInt8(sum & 0xFF)
    }
}

/// Opcodes shared by every ROYUAN family (safe to send to any of them).
enum Shared {
    static let identify: UInt8 = 0x8F
    static let getLed: UInt8 = 0x87
    static let getSideLed: UInt8 = 0x88
}

/// gen2-only opcodes. Never send these to a board that has not identified
/// as a gen2 device: the same numbers mean different things on yc500.
enum Gen2 {
    static let getRevision: UInt8 = 0x80
    static let setLed: UInt8 = 0x07
    static let setSideLed: UInt8 = 0x08
    static let setProfile: UInt8 = 0x04, getProfile: UInt8 = 0x84
    static let setDebounce: UInt8 = 0x06, getDebounce: UInt8 = 0x86
    static let setSleep: UInt8 = 0x11, getSleep: UInt8 = 0x91
    static let getAutoOS: UInt8 = 0x97
    /// `[0x8A, profile, 0xFF, page 0..<8, sublayer 0]` -> one raw 64-byte page
    /// of the 512-byte keymap (4 bytes per key slot). Replies don't echo.
    static let getKeymap: UInt8 = 0x8A
}

enum Keymap {
    static let bytes = 512
    static let slotSize = 4

    static func slot(_ m: [UInt8], _ s: Int) -> ArraySlice<UInt8> { m[(s * slotSize)..<((s + 1) * slotSize)] }

    /// Key slots whose 4-byte assignment differs between two keymaps.
    static func differingSlots(_ a: [UInt8], _ b: [UInt8]) -> [Int] {
        guard a.count == bytes, b.count == bytes else { return [] }
        return (0..<(bytes / slotSize)).filter { s in
            a[(s * slotSize)..<((s + 1) * slotSize)] != b[(s * slotSize)..<((s + 1) * slotSize)]
        }
    }
}

// MARK: - Identify

enum Identify {
    static func request() -> [UInt8] { Proto.packet(Shared.identify) }

    /// `[0x8F, id: u32 LE, ...]`. Some boards answer every command with the
    /// request echoed and byte 3 = 0xFF; that is a refusal, not an ID.
    static func deviceID(from reply: [UInt8]) -> UInt32? {
        var refused = request()
        refused[3] = 0xFF
        if reply == refused { return nil }
        guard reply.count >= 5, reply[0] == Shared.identify else { return nil }
        return UInt32(reply[1]) | UInt32(reply[2]) << 8 | UInt32(reply[3]) << 16 | UInt32(reply[4]) << 24
    }

    /// `(reply[at+1] << 8) | reply[at]`, zero meaning "no answer".
    static func revisionWord(_ reply: [UInt8], at: Int) -> UInt16? {
        guard reply.count > at + 1 else { return nil }
        let v = UInt16(reply[at + 1]) << 8 | UInt16(reply[at])
        return v == 0 ? nil : v
    }

    static func format(revision v: UInt16) -> String {
        String(format: "%X.%02X", v >> 8, v & 0xFF)
    }
}

// MARK: - Lighting

struct Lighting: Equatable {
    var mode: UInt8
    var speed: Int        // 0 = slowest ... 4 = fastest (main light)
    var brightness: Int   // 0 ... 4
    var option: UInt8     // direction / variant index for effects that have one
    var rainbow: Bool
    var r: UInt8
    var g: UInt8
    var b: UInt8

    static let placeholder = Lighting(mode: 1, speed: 2, brightness: 4, option: 0, rainbow: false, r: 255, g: 255, b: 255)
}

/// How one board's firmware reads a LEDPARAM / SLEDPARAM packet.
struct LedWire {
    let setOp: UInt8
    let getOp: UInt8
    /// The Air01 reads the flags nibble the "other way round": 8 = fixed
    /// colour, 7 = rainbow (owner-tested on hardware).
    let swapped: Bool
    /// Main light: wire speed is a frame divider, `speedMax - host`.
    /// Side light: sent as-is.
    let invertSpeed: Bool
    let speedMax: Int
    let brightnessMax: Int
    let isSide: Bool

    static let air01Main = LedWire(setOp: Gen2.setLed, getOp: Shared.getLed, swapped: true,
                                   invertSpeed: true, speedMax: 4, brightnessMax: 4, isSide: false)
    static let air01Side = LedWire(setOp: Gen2.setSideLed, getOp: Shared.getSideLed, swapped: true,
                                   invertSpeed: false, speedMax: 4, brightnessMax: 4, isSide: true)

    var fixedFlag: UInt8 { swapped ? 8 : 7 }
    var rainbowFlag: UInt8 { swapped ? 7 : 8 }

    /// Firmware preset colours, reported when the flags nibble is 0...6.
    var presets: [(UInt8, UInt8, UInt8)] {
        swapped
            ? [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 0x55, 0), (255, 0, 255), (255, 0xBB, 0), (255, 255, 0xDD)]
            : [(255, 0, 0), (255, 0x80, 0), (255, 255, 0), (0, 255, 0), (0, 255, 255), (0, 0, 255), (255, 0, 255)]
    }
}

extension Lighting {
    static let sideNeonMode: UInt8 = 3

    /// `[op, mode, speed, brightness, (option << 4) | flags, R, G, B, ck8]`
    func packet(_ w: LedWire) -> [UInt8] {
        var (r, g, b) = (self.r, self.g, self.b)
        // Near-black renders as "all LEDs off"; floor it so the board looks alive.
        if max(r, g, b) < 8 { (r, g, b) = (8, 8, 8) }
        // Pure white is transmitted as 0xFAFAFA.
        if r == 0xFF && g == 0xFF && b == 0xFF { (r, g, b) = (0xFA, 0xFA, 0xFA) }

        let flags: UInt8
        if w.isSide && mode == Lighting.sideNeonMode {
            flags = w.rainbowFlag
        } else {
            flags = (option & 0x0F) << 4 | (rainbow ? w.rainbowFlag : w.fixedFlag)
        }
        let s = min(max(speed, 0), w.speedMax)
        let wireSpeed = UInt8(w.invertSpeed ? w.speedMax - s : s)
        let bright = UInt8(min(max(brightness, 0), w.brightnessMax))
        return Proto.packet(w.setOp, [mode, wireSpeed, bright, flags, r, g, b], .bit8)
    }

    init?(reply: [UInt8], _ w: LedWire) {
        guard reply.count >= 8, reply[0] == w.getOp else { return nil }
        let flags = reply[4]
        let nibble = flags & 0x0F
        var (r, g, b) = (reply[5], reply[6], reply[7])
        if r == 0xFA && g == 0xFA && b == 0xFA { (r, g, b) = (255, 255, 255) }
        let rainbow = nibble == w.rainbowFlag
        if !rainbow && nibble != w.fixedFlag && Int(nibble) < w.presets.count {
            (r, g, b) = w.presets[Int(nibble)]
        }
        let raw = Int(reply[2])
        self.init(
            mode: reply[1],
            speed: w.invertSpeed ? min(max(w.speedMax - raw, 0), 4) : min(raw, 4),
            brightness: min(Int(reply[3]), w.brightnessMax),
            option: flags >> 4,
            rainbow: rainbow,
            r: r, g: g, b: b
        )
    }
}

struct Effect: Identifiable {
    let mode: UInt8
    let name: String
    var hasSpeed = true
    var hasColor = true
    var options: [String] = []
    var maxSpeed = 4
    var id: UInt8 { mode }
}

enum Effects {
    /// The Air01's main-light catalogue (Akko light layout "v").
    static let main: [Effect] = [
        Effect(mode: 1, name: "Static", hasSpeed: false),
        Effect(mode: 2, name: "Breathing"),
        Effect(mode: 3, name: "Spectrum", hasColor: false),
        Effect(mode: 4, name: "Wave", options: ["Right", "Left", "Down", "Up"]),
        Effect(mode: 5, name: "Ripple"),
        Effect(mode: 6, name: "Star Dots"),
        Effect(mode: 7, name: "Flow", options: ["Zigzag", "Spiral"]),
        Effect(mode: 8, name: "Key Shadow"),
        Effect(mode: 9, name: "Layers"),
        Effect(mode: 10, name: "Sine"),
        Effect(mode: 11, name: "Spring", options: ["Outward", "Inward"]),
        Effect(mode: 12, name: "Neon", options: ["Right", "Left"]),
        Effect(mode: 14, name: "Radiant"),
        Effect(mode: 15, name: "Loop", options: ["Counter-clockwise", "Clockwise"]),
        Effect(mode: 16, name: "Colour Grid"),
        Effect(mode: 17, name: "Snowfall"),
        Effect(mode: 18, name: "Meteor"),
        Effect(mode: 19, name: "Silent Snow"),
    ]

    /// Side (edge) light, Akko layout "Y" intersected with the documented
    /// side-light mode table.
    static let side: [Effect] = [
        Effect(mode: 0, name: "Off", hasSpeed: false, hasColor: false),
        Effect(mode: 1, name: "Static", hasSpeed: false),
        Effect(mode: 2, name: "Breathing", maxSpeed: 3),
        Effect(mode: 3, name: "Neon", hasColor: false, maxSpeed: 3),
        Effect(mode: 4, name: "Wave", maxSpeed: 3),
    ]

    static func find(_ mode: UInt8, side: Bool) -> Effect? {
        (side ? Effects.side : Effects.main).first { $0.mode == mode }
    }
}

// MARK: - Device settings

/// Seconds. Order on the wire: sleep BT, sleep 2.4G, deep BT, deep 2.4G,
/// as u16 LE at bytes 8..<16 for both SET and (on gen2) GET.
struct SleepTimes: Equatable {
    var sleepBT: UInt16
    var sleep24: UInt16
    var deepBT: UInt16
    var deep24: UInt16

    func packet() -> [UInt8] {
        var p = Proto.packet(Gen2.setSleep)
        for (i, v) in [sleepBT, sleep24, deepBT, deep24].enumerated() {
            p[8 + i * 2] = UInt8(v & 0xFF)
            p[9 + i * 2] = UInt8(v >> 8)
        }
        return p
    }

    init(sleepBT: UInt16, sleep24: UInt16, deepBT: UInt16, deep24: UInt16) {
        self.sleepBT = sleepBT; self.sleep24 = sleep24; self.deepBT = deepBT; self.deep24 = deep24
    }

    init?(reply: [UInt8]) {
        guard reply.count >= 16, reply[0] == Gen2.getSleep else { return nil }
        func at(_ i: Int) -> UInt16 { UInt16(reply[8 + i]) | UInt16(reply[9 + i]) << 8 }
        self.init(sleepBT: at(0), sleep24: at(2), deepBT: at(4), deep24: at(6))
    }
}

/// Which board answered the identify handshake.
enum BoardKind {
    /// Confirmed on hardware: gen2 command set, flags nibble swapped.
    case air01Gen2
    /// Another Air01 hardware revision whose command set is unconfirmed.
    case air01Unverified(String)
    case unknown

    static func from(id: UInt32) -> BoardKind {
        switch id {
        case 4010: return .air01Gen2
        case 3013: return .air01Unverified("Air01 (yc3123)")
        case 3452: return .air01Unverified("Air01 UK (yc3123)")
        case 3658: return .air01Unverified("Air01 UK (ry6602)")
        case 3818: return .air01Unverified("Air01 / xG Air 3 (yc3123)")
        default: return .unknown
        }
    }

    var canWrite: Bool { if case .air01Gen2 = self { return true }; return false }
}
