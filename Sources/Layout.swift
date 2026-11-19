// Akko Air01 (device 4010) physical layout: key positions and factory slot values.
// Data from sharkfin's Local83_Akko_Air01.json (GPL-3.0-or-later, owner-confirmed);
// all 84 slots were checked against a real board's keymap read before use.
import CoreGraphics

struct PhysicalKey: Identifiable {
    let slot: Int
    let label: String
    let frame: CGRect
    let factory: [UInt8]
    var id: Int { slot }
}

enum Air01Layout {
    static let size = CGSize(width: 732, height: 284)
    static let fnSlot = 5
    /// Slot 89 holds a board action with no physical key; never shown or edited.
    static let hiddenSlots: [Int: [UInt8]] = [89: [10, 9, 0, 0]]
    static let keys: [PhysicalKey] = [
        PhysicalKey(slot: 0, label: "Esc", frame: CGRect(x: 1, y: 1, width: 40, height: 40), factory: [0, 0, 41, 0]),
        PhysicalKey(slot: 1, label: "` ~", frame: CGRect(x: 1, y: 59, width: 40, height: 40), factory: [0, 0, 53, 0]),
        PhysicalKey(slot: 2, label: "Tab", frame: CGRect(x: 1, y: 105, width: 63, height: 40), factory: [0, 0, 43, 0]),
        PhysicalKey(slot: 3, label: "Caps", frame: CGRect(x: 1, y: 151, width: 75, height: 40), factory: [0, 0, 57, 0]),
        PhysicalKey(slot: 4, label: "L-Shift", frame: CGRect(x: 1, y: 197, width: 98, height: 40), factory: [0, 0, 225, 0]),
        PhysicalKey(slot: 5, label: "Fn", frame: CGRect(x: 1, y: 243, width: 40, height: 40), factory: [10, 1, 0, 0]),
        PhysicalKey(slot: 6, label: "F1", frame: CGRect(x: 47, y: 1, width: 40, height: 40), factory: [0, 0, 58, 0]),
        PhysicalKey(slot: 7, label: "1", frame: CGRect(x: 47, y: 59, width: 40, height: 40), factory: [0, 0, 30, 0]),
        PhysicalKey(slot: 8, label: "Q", frame: CGRect(x: 70, y: 105, width: 40, height: 40), factory: [0, 0, 20, 0]),
        PhysicalKey(slot: 9, label: "A", frame: CGRect(x: 82, y: 151, width: 40, height: 40), factory: [0, 0, 4, 0]),
        PhysicalKey(slot: 11, label: "L-Ctrl", frame: CGRect(x: 47, y: 243, width: 40, height: 40), factory: [0, 0, 224, 0]),
        PhysicalKey(slot: 12, label: "F2", frame: CGRect(x: 93, y: 1, width: 40, height: 40), factory: [0, 0, 59, 0]),
        PhysicalKey(slot: 13, label: "2", frame: CGRect(x: 93, y: 59, width: 40, height: 40), factory: [0, 0, 31, 0]),
        PhysicalKey(slot: 14, label: "W", frame: CGRect(x: 116, y: 105, width: 40, height: 40), factory: [0, 0, 26, 0]),
        PhysicalKey(slot: 15, label: "S", frame: CGRect(x: 128, y: 151, width: 40, height: 40), factory: [0, 0, 22, 0]),
        PhysicalKey(slot: 16, label: "Z", frame: CGRect(x: 105, y: 197, width: 40, height: 40), factory: [0, 0, 29, 0]),
        PhysicalKey(slot: 17, label: "L-Win", frame: CGRect(x: 139, y: 243, width: 52, height: 40), factory: [0, 0, 227, 0]),
        PhysicalKey(slot: 18, label: "F3", frame: CGRect(x: 139, y: 1, width: 40, height: 40), factory: [0, 0, 60, 0]),
        PhysicalKey(slot: 19, label: "3", frame: CGRect(x: 139, y: 59, width: 40, height: 40), factory: [0, 0, 32, 0]),
        PhysicalKey(slot: 20, label: "E", frame: CGRect(x: 162, y: 105, width: 40, height: 40), factory: [0, 0, 8, 0]),
        PhysicalKey(slot: 21, label: "D", frame: CGRect(x: 174, y: 151, width: 40, height: 40), factory: [0, 0, 7, 0]),
        PhysicalKey(slot: 22, label: "X", frame: CGRect(x: 151, y: 197, width: 40, height: 40), factory: [0, 0, 27, 0]),
        PhysicalKey(slot: 23, label: "L-Alt", frame: CGRect(x: 93, y: 243, width: 40, height: 40), factory: [0, 0, 226, 0]),
        PhysicalKey(slot: 24, label: "F4", frame: CGRect(x: 185, y: 1, width: 40, height: 40), factory: [0, 0, 61, 0]),
        PhysicalKey(slot: 25, label: "4", frame: CGRect(x: 185, y: 59, width: 40, height: 40), factory: [0, 0, 33, 0]),
        PhysicalKey(slot: 26, label: "R", frame: CGRect(x: 208, y: 105, width: 40, height: 40), factory: [0, 0, 21, 0]),
        PhysicalKey(slot: 27, label: "F", frame: CGRect(x: 220, y: 151, width: 40, height: 40), factory: [0, 0, 9, 0]),
        PhysicalKey(slot: 28, label: "C", frame: CGRect(x: 197, y: 197, width: 40, height: 40), factory: [0, 0, 6, 0]),
        PhysicalKey(slot: 30, label: "F5", frame: CGRect(x: 231, y: 1, width: 40, height: 40), factory: [0, 0, 62, 0]),
        PhysicalKey(slot: 31, label: "5", frame: CGRect(x: 231, y: 59, width: 40, height: 40), factory: [0, 0, 34, 0]),
        PhysicalKey(slot: 32, label: "T", frame: CGRect(x: 254, y: 105, width: 40, height: 40), factory: [0, 0, 23, 0]),
        PhysicalKey(slot: 33, label: "G", frame: CGRect(x: 266, y: 151, width: 40, height: 40), factory: [0, 0, 10, 0]),
        PhysicalKey(slot: 34, label: "V", frame: CGRect(x: 243, y: 197, width: 40, height: 40), factory: [0, 0, 25, 0]),
        PhysicalKey(slot: 36, label: "F6", frame: CGRect(x: 277, y: 1, width: 40, height: 40), factory: [0, 0, 63, 0]),
        PhysicalKey(slot: 37, label: "6", frame: CGRect(x: 277, y: 59, width: 40, height: 40), factory: [0, 0, 35, 0]),
        PhysicalKey(slot: 38, label: "Y", frame: CGRect(x: 300, y: 105, width: 40, height: 40), factory: [0, 0, 28, 0]),
        PhysicalKey(slot: 39, label: "H", frame: CGRect(x: 312, y: 151, width: 40, height: 40), factory: [0, 0, 11, 0]),
        PhysicalKey(slot: 40, label: "B", frame: CGRect(x: 289, y: 197, width: 40, height: 40), factory: [0, 0, 5, 0]),
        PhysicalKey(slot: 41, label: "Space", frame: CGRect(x: 197, y: 243, width: 282, height: 40), factory: [0, 0, 44, 0]),
        PhysicalKey(slot: 42, label: "F7", frame: CGRect(x: 323, y: 1, width: 40, height: 40), factory: [0, 0, 64, 0]),
        PhysicalKey(slot: 43, label: "7", frame: CGRect(x: 323, y: 59, width: 40, height: 40), factory: [0, 0, 36, 0]),
        PhysicalKey(slot: 44, label: "U", frame: CGRect(x: 346, y: 105, width: 40, height: 40), factory: [0, 0, 24, 0]),
        PhysicalKey(slot: 45, label: "J", frame: CGRect(x: 358, y: 151, width: 40, height: 40), factory: [0, 0, 13, 0]),
        PhysicalKey(slot: 46, label: "N", frame: CGRect(x: 335, y: 197, width: 40, height: 40), factory: [0, 0, 17, 0]),
        PhysicalKey(slot: 48, label: "F8", frame: CGRect(x: 369, y: 1, width: 40, height: 40), factory: [0, 0, 65, 0]),
        PhysicalKey(slot: 49, label: "8", frame: CGRect(x: 369, y: 59, width: 40, height: 40), factory: [0, 0, 37, 0]),
        PhysicalKey(slot: 50, label: "I", frame: CGRect(x: 392, y: 105, width: 40, height: 40), factory: [0, 0, 12, 0]),
        PhysicalKey(slot: 51, label: "K", frame: CGRect(x: 404, y: 151, width: 40, height: 40), factory: [0, 0, 14, 0]),
        PhysicalKey(slot: 52, label: "M", frame: CGRect(x: 381, y: 197, width: 40, height: 40), factory: [0, 0, 16, 0]),
        PhysicalKey(slot: 54, label: "F9", frame: CGRect(x: 415, y: 1, width: 40, height: 40), factory: [0, 0, 66, 0]),
        PhysicalKey(slot: 55, label: "9", frame: CGRect(x: 415, y: 59, width: 40, height: 40), factory: [0, 0, 38, 0]),
        PhysicalKey(slot: 56, label: "O", frame: CGRect(x: 438, y: 105, width: 40, height: 40), factory: [0, 0, 18, 0]),
        PhysicalKey(slot: 57, label: "L", frame: CGRect(x: 450, y: 151, width: 40, height: 40), factory: [0, 0, 15, 0]),
        PhysicalKey(slot: 58, label: ", <", frame: CGRect(x: 427, y: 197, width: 40, height: 40), factory: [0, 0, 54, 0]),
        PhysicalKey(slot: 59, label: "R-Alt", frame: CGRect(x: 484, y: 243, width: 52, height: 40), factory: [0, 0, 230, 0]),
        PhysicalKey(slot: 60, label: "F10", frame: CGRect(x: 461, y: 1, width: 40, height: 40), factory: [0, 0, 67, 0]),
        PhysicalKey(slot: 61, label: "0", frame: CGRect(x: 461, y: 59, width: 40, height: 40), factory: [0, 0, 39, 0]),
        PhysicalKey(slot: 62, label: "P", frame: CGRect(x: 484, y: 105, width: 40, height: 40), factory: [0, 0, 19, 0]),
        PhysicalKey(slot: 63, label: "; :", frame: CGRect(x: 496, y: 151, width: 40, height: 40), factory: [0, 0, 51, 0]),
        PhysicalKey(slot: 64, label: ". >", frame: CGRect(x: 473, y: 197, width: 40, height: 40), factory: [0, 0, 55, 0]),
        PhysicalKey(slot: 65, label: "R-Ctrl", frame: CGRect(x: 542, y: 243, width: 52, height: 40), factory: [0, 0, 228, 0]),
        PhysicalKey(slot: 66, label: "F11", frame: CGRect(x: 507, y: 1, width: 40, height: 40), factory: [0, 0, 68, 0]),
        PhysicalKey(slot: 67, label: "- _", frame: CGRect(x: 507, y: 59, width: 40, height: 40), factory: [0, 0, 45, 0]),
        PhysicalKey(slot: 68, label: "[ {", frame: CGRect(x: 530, y: 105, width: 40, height: 40), factory: [0, 0, 47, 0]),
        PhysicalKey(slot: 69, label: "' \"", frame: CGRect(x: 542, y: 151, width: 40, height: 40), factory: [0, 0, 52, 0]),
        PhysicalKey(slot: 70, label: "/ ?", frame: CGRect(x: 519, y: 197, width: 40, height: 40), factory: [0, 0, 56, 0]),
        PhysicalKey(slot: 71, label: "←", frame: CGRect(x: 599, y: 243, width: 40, height: 40), factory: [0, 0, 80, 0]),
        PhysicalKey(slot: 72, label: "F12", frame: CGRect(x: 553, y: 1, width: 40, height: 40), factory: [0, 0, 69, 0]),
        PhysicalKey(slot: 73, label: "= +", frame: CGRect(x: 553, y: 59, width: 40, height: 40), factory: [0, 0, 46, 0]),
        PhysicalKey(slot: 74, label: "] }", frame: CGRect(x: 576, y: 105, width: 40, height: 40), factory: [0, 0, 48, 0]),
        PhysicalKey(slot: 76, label: "R-Shift", frame: CGRect(x: 565, y: 197, width: 75, height: 40), factory: [0, 0, 229, 0]),
        PhysicalKey(slot: 77, label: "↓", frame: CGRect(x: 645, y: 243, width: 40, height: 40), factory: [0, 0, 81, 0]),
        PhysicalKey(slot: 78, label: "PrtSc", frame: CGRect(x: 599, y: 1, width: 40, height: 40), factory: [0, 0, 70, 0]),
        PhysicalKey(slot: 79, label: "Backspace", frame: CGRect(x: 599, y: 59, width: 86, height: 40), factory: [0, 0, 42, 0]),
        PhysicalKey(slot: 80, label: "\\ |", frame: CGRect(x: 622, y: 105, width: 63, height: 40), factory: [0, 0, 49, 0]),
        PhysicalKey(slot: 81, label: "Enter", frame: CGRect(x: 588, y: 151, width: 98, height: 40), factory: [0, 0, 40, 0]),
        PhysicalKey(slot: 82, label: "↑", frame: CGRect(x: 645, y: 197, width: 40, height: 40), factory: [0, 0, 82, 0]),
        PhysicalKey(slot: 83, label: "→", frame: CGRect(x: 691, y: 243, width: 40, height: 40), factory: [0, 0, 79, 0]),
        PhysicalKey(slot: 84, label: "Insert", frame: CGRect(x: 645, y: 1, width: 40, height: 40), factory: [0, 0, 73, 0]),
        PhysicalKey(slot: 85, label: "Home", frame: CGRect(x: 691, y: 59, width: 40, height: 40), factory: [0, 0, 74, 0]),
        PhysicalKey(slot: 86, label: "End", frame: CGRect(x: 691, y: 105, width: 40, height: 40), factory: [0, 0, 77, 0]),
        PhysicalKey(slot: 87, label: "PgUp", frame: CGRect(x: 691, y: 151, width: 40, height: 40), factory: [0, 0, 75, 0]),
        PhysicalKey(slot: 88, label: "PgDn", frame: CGRect(x: 691, y: 197, width: 40, height: 40), factory: [0, 0, 78, 0]),
    ]
    static func key(_ slot: Int) -> PhysicalKey? { keys.first { $0.slot == slot } }
}
