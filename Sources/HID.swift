import Foundation
import IOKit
import IOKit.hid

// MARK: - Discovery

struct HIDInfo {
    let device: IOHIDDevice
    let vendorID: Int
    let productID: Int
    let product: String
    let transport: String
    let usagePairs: [(page: Int, usage: Int)]
    let maxFeatureReport: Int

    init(_ d: IOHIDDevice) {
        device = d
        vendorID = HIDInfo.int(d, kIOHIDVendorIDKey)
        productID = HIDInfo.int(d, kIOHIDProductIDKey)
        product = IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? "Keyboard"
        transport = IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String ?? ""
        maxFeatureReport = HIDInfo.int(d, kIOHIDMaxFeatureReportSizeKey)
        let pairs = IOHIDDeviceGetProperty(d, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Any]] ?? []
        usagePairs = pairs.map {
            (($0[kIOHIDDeviceUsagePageKey] as? Int) ?? 0, ($0[kIOHIDDeviceUsageKey] as? Int) ?? 0)
        }
    }

    private static func int(_ d: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(d, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    var isUSB: Bool { transport == "USB" }
    var isBluetooth: Bool { transport.localizedCaseInsensitiveContains("bluetooth") }

    /// The 64-byte vendor settings collection.
    var isSettingsInterface: Bool {
        isUSB && maxFeatureReport >= Proto.reportLength
            && usagePairs.contains { $0.page == 0xFFFF && ($0.usage == 1 || $0.usage == 2) }
    }

    var idString: String { String(format: "%04x:%04x", vendorID, productID) }
}

/// Watches for ROYUAN-family devices (Akko uses vendor IDs 0x3151 and 0x38EE).
/// The manager itself is never opened, so merely watching needs no permission.
final class HIDWatcher {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var onChange: (() -> Void)?

    init(scheduleOnMainRunLoop: Bool = true) {
        let matching = [[kIOHIDVendorIDKey: 0x3151], [kIOHIDVendorIDKey: 0x38EE]] as CFArray
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching)
        guard scheduleOnMainRunLoop else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOHIDDeviceCallback = { ctx, _, _, _ in
            guard let ctx else { return }
            Unmanaged<HIDWatcher>.fromOpaque(ctx).takeUnretainedValue().onChange?()
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, cb, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, cb, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    func devices() -> [HIDInfo] {
        guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
        return (set as NSSet).allObjects.map { HIDInfo($0 as! IOHIDDevice) }
    }
}

// MARK: - Session

enum HIDError: LocalizedError {
    case notPermitted
    case busy
    case open(IOReturn)
    case transfer(IOReturn)
    case noAnswer
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .notPermitted:
            return "macOS blocked access. Allow this app under System Settings → Privacy & Security → Input Monitoring."
        case .busy:
            return "Another app has the keyboard open exclusively (Akko Cloud Driver or Karabiner?). Quit it and try again."
        case .open(let r):
            return "Couldn't open the keyboard (IOReturn 0x\(String(UInt32(bitPattern: r), radix: 16)))."
        case .transfer(let r):
            return "The keyboard stopped answering (IOReturn 0x\(String(UInt32(bitPattern: r), radix: 16))). Unplug it and plug it back in."
        case .noAnswer:
            return "The keyboard didn't answer. If you're using the 2.4 GHz dongle, use the USB cable instead."
        case .unexpected(let m):
            return m
        }
    }
}

private let kReturnNotPermitted = IOReturn(bitPattern: 0xE000_02E2)
private let kReturnExclusive = IOReturn(bitPattern: 0xE000_02C5)

/// One open settings interface. All traffic goes through `queue`, one
/// exchange at a time, with the pacing the firmware needs:
///  - at least 12 ms between reports (it stalls otherwise);
///  - 1 s of silence after any SET, because settings commit to flash and
///    traffic during a commit can wedge the endpoint until replugged.
final class KeyboardSession: @unchecked Sendable {
    let info: HIDInfo
    private let queue = DispatchQueue(label: "air01.hid")
    private var lastReport = Date.distantPast
    private var quietUntil = Date.distantPast
    private var isOpen = false

    static let reportGap: TimeInterval = 0.012
    static let flashQuiet: TimeInterval = 1.0

    init(_ info: HIDInfo) throws {
        self.info = info
        let r = IOHIDDeviceOpen(info.device, IOOptionBits(kIOHIDOptionsTypeNone))
        switch r {
        case kIOReturnSuccess: isOpen = true
        case kReturnNotPermitted: throw HIDError.notPermitted
        case kReturnExclusive: throw HIDError.busy
        default: throw HIDError.open(r)
        }
    }

    func close() {
        queue.sync {
            if isOpen { IOHIDDeviceClose(info.device, IOOptionBits(kIOHIDOptionsTypeNone)) }
            isOpen = false
        }
    }

    deinit { if isOpen { IOHIDDeviceClose(info.device, IOOptionBits(kIOHIDOptionsTypeNone)) } }

    /// Run `body` on the HID queue.
    func run<T>(_ body: @escaping (KeyboardSession) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async { cont.resume(with: Result { try body(self) }) }
        }
    }

    // Raw transfers ------------------------------------------------------

    private func pace() {
        let wait = max(quietUntil.timeIntervalSinceNow, KeyboardSession.reportGap + lastReport.timeIntervalSinceNow)
        if wait > 0 { Thread.sleep(forTimeInterval: wait) }
    }

    private func send(_ pkt: [UInt8]) throws {
        pace()
        let r = pkt.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(info.device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, $0.count)
        }
        lastReport = Date()
        guard r == kIOReturnSuccess else { throw HIDError.transfer(r) }
    }

    private func read() throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: Proto.reportLength + 1)
        var len = CFIndex(buf.count)
        let r = IOHIDDeviceGetReport(info.device, kIOHIDReportTypeFeature, 0, &buf, &len)
        guard r == kIOReturnSuccess else { throw HIDError.transfer(r) }
        guard len >= 8 else { throw HIDError.unexpected("Short reply from keyboard (\(len) bytes).") }
        // Tolerate a leading report-ID byte if the stack keeps it.
        if len == Proto.reportLength + 1 && buf[0] == 0 { return Array(buf[1...Proto.reportLength]) }
        return Array(buf[0..<Proto.reportLength])
    }

    // Exchanges --------------------------------------------------------

    /// Send a GET and wait for the reply that echoes its opcode. An
    /// unsupported command returns the *previous* reply, so the echo check
    /// is what tells the two apart.
    func roundtrip(_ pkt: [UInt8]) throws -> [UInt8] {
        try send(pkt)
        for attempt in 1...5 {
            Thread.sleep(forTimeInterval: 0.010 * Double(attempt))
            let reply = try read()
            if reply[0] == pkt[0] { return reply }
        }
        throw HIDError.noAnswer
    }

    /// Send a SET (lands in flash) and enforce the quiet period after it.
    func write(_ pkt: [UInt8]) throws {
        try send(pkt)
        quietUntil = Date().addingTimeInterval(KeyboardSession.flashQuiet)
    }

    func identify() throws -> UInt32 {
        for _ in 0..<3 {
            if let reply = try? roundtrip(Identify.request()), let id = Identify.deviceID(from: reply) {
                return id
            }
        }
        throw HIDError.noAnswer
    }
}

// MARK: - High-level reads/writes

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
    var keymaps: [Int: [UInt8]] = [:]
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
        for p in 0..<4 { s.keymaps[p] = try? readKeymap(profile: p) }

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

    /// Read-only, works for any profile without switching. Raw pages carry
    /// no echo, so the whole map is read twice and must match.
    func readKeymap(profile: Int) throws -> [UInt8] {
        func once() throws -> [UInt8] {
            var m: [UInt8] = []
            for page in 0..<8 {
                try send(Proto.packet(Gen2.getKeymap, [UInt8(profile), 0xFF, UInt8(page), 0]))
                Thread.sleep(forTimeInterval: 0.010)
                m += try read()
            }
            return m
        }
        for _ in 0..<3 {
            let a = try once(), b = try once()
            if a == b { return a }
        }
        throw HIDError.unexpected("Profile \(profile + 1)'s key layout read back inconsistently.")
    }
}
