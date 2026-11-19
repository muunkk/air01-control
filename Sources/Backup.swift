import Foundation

/// Everything the app can change, as one JSON file.
struct Backup: Codable {
    var format = 1
    var created: Date
    var deviceID: UInt32
    var firmware: String?
    /// GET replies for the lights (decoded with `Lighting(reply:)` on restore).
    var backlight: String?
    var sideLight: String?
    var profile: Int?
    var debounce: Int?
    var sleep: [UInt16]?
    var autoOS: Bool?
    /// "1".."4" -> 512-byte base layer, hex.
    var base: [String: String]
    /// "1-Mac", "3-Windows", … -> 512-byte Fn layer, hex.
    var fn: [String: String]

    static let folder: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Air01 Control/Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func fnKey(profile: Int, os: Int) -> String { "\(profile + 1)-\(KeyLayer.osNames[os])" }

    func save() throws -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = Backup.folder.appendingPathComponent("Air01 backup \(f.string(from: created)).json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(self).write(to: url)
        return url
    }

    static func load(_ url: URL) throws -> Backup {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(Backup.self, from: Data(contentsOf: url))
    }
}

extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        self = out
    }
}

typealias Progress = @Sendable (String, Double) -> Void

extension KeyboardSession {
    /// Read-only. About 10 seconds: every layer is read twice.
    func makeBackup(progress: Progress) throws -> Backup {
        progress("Reading settings…", 0)
        let id = try identify()
        guard BoardKind.from(id: id).canWrite else { throw HIDError.unexpected("Backups are only for the confirmed Air01.") }
        let led = try roundtrip(Proto.packet(Shared.getLed))
        let side = try roundtrip(Proto.packet(Shared.getSideLed))
        let sleep = SleepTimes(reply: try roundtrip(Proto.packet(Gen2.getSleep)))
        var b = Backup(
            created: Date(), deviceID: id, firmware: nil,
            backlight: Array(led[0..<9]).hex, sideLight: Array(side[0..<9]).hex,
            profile: Int(try roundtrip(Proto.packet(Gen2.getProfile))[1]),
            debounce: Int(try roundtrip(Proto.packet(Gen2.getDebounce))[1]),
            sleep: sleep.map { [$0.sleepBT, $0.sleep24, $0.deepBT, $0.deep24] },
            autoOS: try roundtrip(Proto.packet(Gen2.getAutoOS))[1] == 1,
            base: [:], fn: [:]
        )
        let steps = 4 * 5
        var done = 0
        for p in 0..<4 {
            progress("Reading profile \(p + 1) keys…", Double(done) / Double(steps))
            b.base["\(p + 1)"] = try readKeymap(profile: p).hex
            done += 1
            for os in 0..<4 {
                b.fn[Backup.fnKey(profile: p, os: os)] = try readFn(profile: p, os: os).hex
                done += 1
                progress("Reading profile \(p + 1) Fn layers…", Double(done) / Double(steps))
            }
        }
        return b
    }

    /// Put the keyboard back to `b`, writing only what differs.
    /// Returns the number of key slots changed.
    func restore(_ b: Backup, progress: Progress) throws -> Int {
        guard try identify() == b.deviceID else {
            throw HIDError.unexpected("That backup is from a different keyboard model.")
        }
        progress("Comparing with the keyboard…", 0)
        typealias Job = (layer: KeyLayer, slot: Int, value: [UInt8])
        var jobs: [Int: [Job]] = [:]
        for p in 0..<4 {
            var list: [Job] = []
            if let want = b.base["\(p + 1)"].flatMap([UInt8].init(hex:)), want.count == Keymap.bytes {
                let have = try readKeymap(profile: p)
                for s in Keymap.differingSlots(have, want)
                where s != Air01Layout.fnSlot && Air01Layout.hiddenSlots[s] == nil {
                    list.append((.base, s, Array(Keymap.slot(want, s))))
                }
            }
            for os in 0..<4 {
                guard let want = b.fn[Backup.fnKey(profile: p, os: os)].flatMap([UInt8].init(hex:)),
                      want.count == Keymap.bytes else { continue }
                let have = try readFn(profile: p, os: os)
                for s in Keymap.differingSlots(have, want) where Air01Layout.hiddenSlots[s] == nil {
                    list.append((.fn(os: os), s, Array(Keymap.slot(want, s))))
                }
            }
            if !list.isEmpty { jobs[p] = list }
        }

        let total = jobs.values.reduce(0) { $0 + $1.count }
        var done = 0
        let original = Int(try roundtrip(Proto.packet(Gen2.getProfile))[1])
        for p in jobs.keys.sorted() {
            // Write a profile's keymap while it's the active one.
            if try roundtrip(Proto.packet(Gen2.getProfile))[1] != UInt8(p) { _ = try switchProfile(p) }
            for job in jobs[p]! {
                progress("Restoring profile \(p + 1) keys (\(done + 1) of \(total))…", Double(done) / Double(max(total, 1)))
                try writeSlot(job.layer, profile: p, slot: job.slot, value: job.value)
                done += 1
            }
        }

        progress("Restoring lighting and settings…", 1)
        let target = b.profile ?? original
        if try roundtrip(Proto.packet(Gen2.getProfile))[1] != UInt8(target) { _ = try switchProfile(target) }
        if let h = b.backlight.flatMap([UInt8].init(hex:)), let l = Lighting(reply: h, .air01Main) {
            try write(l.packet(.air01Main))
        }
        if let h = b.sideLight.flatMap([UInt8].init(hex:)), let l = Lighting(reply: h, .air01Side) {
            try write(l.packet(.air01Side))
        }
        if let d = b.debounce { try write(Proto.packet(Gen2.setDebounce, [UInt8(min(max(d, 1), 10))])) }
        if let s = b.sleep, s.count == 4 {
            try write(SleepTimes(sleepBT: s[0], sleep24: s[1], deepBT: s[2], deep24: s[3]).packet())
        }
        if let a = b.autoOS { _ = try setAutoOS(a) }
        return total
    }
}
