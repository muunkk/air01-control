import Foundation

/// What one key slot does. Wire format is 4 bytes, byte 0 the kind:
///  - `00`: keyboard. Bytes 1...3 hold up to three HID usages pressed
///    together; a plain key is `[0, 0, usage, 0]`, a shortcut puts
///    modifiers in bytes 1 and 3 (the Air01's own Fn layer stores
///    Ctrl+↑ as `00 E0 52 00` and ⌘Space as `00 00 E3 2C`).
///  - `03`: media (consumer usage), `[3, 0, lo, hi]`.
///  - `09`: macro, `[9, mode, index, 0]`.
///  - `0A`: board function (`0A 01` is Fn).
///  - all zero: disabled on the base layer; "use the base key" on the Fn layer.
/// Other kinds (Bluetooth slots, lighting control, …) are the keyboard's
/// own functions; they're shown but never constructed here.
enum KeyAction: Hashable {
    case key(UInt8)
    case shortcut(mods: [UInt8], key: UInt8)
    case media(UInt16)
    case none
    case raw([UInt8])

    init(_ v: [UInt8]) {
        guard v.count == 4 else { self = .raw(v); return }
        if v == [0, 0, 0, 0] { self = .none; return }
        switch v[0] {
        case 0x00:
            let usages = [v[1], v[2], v[3]].filter { $0 != 0 }
            let mods = usages.filter(KeyCatalog.isModifier)
            let keys = usages.filter { !KeyCatalog.isModifier($0) }
            if usages.count == 1 { self = .key(usages[0]) }
            else if keys.count == 1 { self = .shortcut(mods: mods, key: keys[0]) }
            else if keys.isEmpty, let last = mods.last { self = .shortcut(mods: Array(mods.dropLast()), key: last) }
            else { self = .raw(v) }
        case 0x03:
            self = .media(UInt16(v[2]) | UInt16(v[3]) << 8)
        default:
            self = .raw(v)
        }
    }

    var bytes: [UInt8] {
        switch self {
        case .key(let u): return [0, 0, u, 0]
        case .shortcut(let mods, let key):
            let m = Array(mods.prefix(2))
            return [0, m.count > 0 ? m[0] : 0, key, m.count > 1 ? m[1] : 0]
        case .media(let u): return [3, 0, UInt8(u & 0xFF), UInt8(u >> 8)]
        case .none: return [0, 0, 0, 0]
        case .raw(let v): return v
        }
    }

    /// Board functions (Fn, Bluetooth slots, lighting keys, …).
    var isBoardFunction: Bool {
        if case .raw(let v) = self { return v.first != 0x00 && v.first != 0x03 }
        return false
    }

    func name(fnLayer: Bool = false) -> String {
        switch self {
        case .key(let u): return KeyCatalog.name(u)
        case .shortcut(let mods, let key):
            return (mods.map(KeyCatalog.symbol) + [KeyCatalog.name(key)]).joined(separator: " ")
        case .media(let u): return KeyCatalog.mediaName(u)
        case .none: return fnLayer ? "Same as base key" : "Disabled"
        case .raw(let v):
            switch v.first {
            case 0x0A where v[1] == 1: return "Fn"
            case 0x09: return "Macro \(Int(v[2]) + 1)"
            case 0x01: return "Mouse button"
            default: return "Keyboard function"
            }
        }
    }
}

enum KeyCatalog {
    static func isModifier(_ u: UInt8) -> Bool { (0xE0...0xE7).contains(u) }

    static let modifiers: [(String, UInt8)] = [
        ("⌘ Command", 0xE3), ("⌥ Option", 0xE2), ("⌃ Control", 0xE0), ("⇧ Shift", 0xE1),
    ]

    static func symbol(_ u: UInt8) -> String {
        switch u {
        case 0xE0, 0xE4: return "⌃"
        case 0xE1, 0xE5: return "⇧"
        case 0xE2, 0xE6: return "⌥"
        case 0xE3, 0xE7: return "⌘"
        default: return name(u)
        }
    }

    static let groups: [(title: String, keys: [UInt8])] = [
        ("Letters", Array(0x04...0x1D)),
        ("Numbers", Array(0x1E...0x27)),
        ("Function keys", Array(0x3A...0x45) + Array(0x68...0x73)),
        ("Modifiers", [0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7]),
        ("Editing", [0x29, 0x2B, 0x2C, 0x28, 0x2A, 0x4C, 0x39, 0x49, 0x65]),
        ("Navigation", [0x50, 0x4F, 0x52, 0x51, 0x4A, 0x4D, 0x4B, 0x4E]),
        ("Symbols", [0x35, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x33, 0x34, 0x36, 0x37, 0x38]),
        ("Other", [0x46, 0x47, 0x48]),
    ]

    static func name(_ u: UInt8) -> String {
        switch u {
        case 0x04...0x1D: return String(UnicodeScalar(UInt8(ascii: "A") + (u - 0x04)))
        case 0x1E...0x26: return String(u - 0x1D)
        case 0x27: return "0"
        case 0x3A...0x45: return "F\(u - 0x39)"
        case 0x68...0x73: return "F\(u - 0x68 + 13)"
        default: break
        }
        let names: [UInt8: String] = [
            0x28: "Return", 0x29: "Esc", 0x2A: "Delete (Backspace)", 0x2B: "Tab", 0x2C: "Space", 0x2D: "-", 0x2E: "=",
            0x2F: "[", 0x30: "]", 0x31: "\\", 0x33: ";", 0x34: "'", 0x35: "`", 0x36: ",", 0x37: ".", 0x38: "/",
            0x39: "Caps Lock", 0x46: "Print Screen", 0x47: "Scroll Lock", 0x48: "Pause", 0x49: "Insert",
            0x4A: "Home", 0x4B: "Page Up", 0x4C: "Forward Delete", 0x4D: "End", 0x4E: "Page Down",
            0x4F: "→", 0x50: "←", 0x51: "↓", 0x52: "↑", 0x65: "Menu",
            0xE0: "Left ⌃ Control", 0xE1: "Left ⇧ Shift", 0xE2: "Left ⌥ Option", 0xE3: "Left ⌘ Command",
            0xE4: "Right ⌃ Control", 0xE5: "Right ⇧ Shift", 0xE6: "Right ⌥ Option", 0xE7: "Right ⌘ Command",
        ]
        return names[u] ?? String(format: "Key 0x%02X", u)
    }

    static let media: [(String, UInt16)] = [
        ("Play / Pause", 0x00CD), ("Next track", 0x00B5), ("Previous track", 0x00B6),
        ("Mute", 0x00E2), ("Volume up", 0x00E9), ("Volume down", 0x00EA),
        ("Screen brightness up", 0x006F), ("Screen brightness down", 0x0070),
        ("Dictation", 0x00CF), ("Calculator", 0x0192), ("Mail", 0x018A),
        ("Search", 0x0221), ("Browser home", 0x0223), ("My Computer", 0x0194), ("Media player", 0x0183),
    ]

    static func mediaName(_ u: UInt16) -> String {
        media.first { $0.1 == u }?.0 ?? String(format: "Media 0x%03X", u)
    }

    /// Ready-made Mac shortcuts.
    static let macShortcuts: [(String, KeyAction)] = [
        ("Spotlight (⌘ Space)", .shortcut(mods: [0xE3], key: 0x2C)),
        ("Mission Control (⌃ ↑)", .shortcut(mods: [0xE0], key: 0x52)),
        ("App windows (⌃ ↓)", .shortcut(mods: [0xE0], key: 0x51)),
        ("Screenshot area (⌘ ⇧ 4)", .shortcut(mods: [0xE3, 0xE1], key: 0x21)),
        ("Screenshot tool (⌘ ⇧ 5)", .shortcut(mods: [0xE3, 0xE1], key: 0x22)),
        ("Lock screen (⌃ ⌘ Q)", .shortcut(mods: [0xE0, 0xE3], key: 0x14)),
        ("Switch app (⌘ Tab)", .shortcut(mods: [0xE3], key: 0x2B)),
        ("Copy (⌘ C)", .shortcut(mods: [0xE3], key: 0x06)),
        ("Paste (⌘ V)", .shortcut(mods: [0xE3], key: 0x19)),
        ("Undo (⌘ Z)", .shortcut(mods: [0xE3], key: 0x1D)),
    ]
}
