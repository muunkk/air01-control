import AppKit
import Foundation

/// Checks GitHub Releases for a newer build and installs it in place.
///
/// The repo is private, so anonymous API calls can't see it. Instead this
/// goes through the GitHub CLI (`gh`), which is already signed in on this
/// Mac, for both the check and the download.
@MainActor
final class Updater: ObservableObject {
    static let repo = "muunkk/air01-control"
    static let releasesURL = URL(string: "https://github.com/\(repo)/releases")!

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, notes: String)
        case installing
        case failed(String)
    }

    @Published var state: State = .idle
    /// Set after a manual check, to show the result in an alert.
    @Published var showResult = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: Check

    func check(manual: Bool) async {
        guard state != .checking, state != .installing else { return }
        state = .checking
        do {
            let out = try await Self.gh(["api", "repos/\(Self.repo)/releases/latest", "--jq", ".tag_name, .body"])
            let lines = out.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let tag = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let notes = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            guard !latest.isEmpty else { throw UpdateError("GitHub returned no release.") }
            state = Self.isNewer(latest, than: currentVersion) ? .available(version: latest, notes: notes) : .upToDate
        } catch {
            let msg = error.localizedDescription
            state = .failed(msg.contains("HTTP 404") ? "No release has been published yet." : msg)
        }
        if manual { showResult = true }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Install

    /// Download the release zip, check it, swap it in for the running app
    /// once this process has quit, and relaunch.
    func install() async {
        guard case .available(let version, _) = state else { return }
        state = .installing
        do {
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("air01-update-\(UUID().uuidString)")
            try fm.createDirectory(at: work, withIntermediateDirectories: true)

            _ = try await Self.gh(["release", "download", "v\(version)", "-R", Self.repo,
                                   "-p", "Air01-Control-*.zip", "-D", work.path])
            guard let zip = try fm.contentsOfDirectory(atPath: work.path).first(where: { $0.hasSuffix(".zip") }) else {
                throw UpdateError("The release has no app download.")
            }
            let unpacked = work.appendingPathComponent("unpacked")
            _ = try await Self.run("/usr/bin/ditto", ["-x", "-k", work.appendingPathComponent(zip).path, unpacked.path])

            let newApp = unpacked.appendingPathComponent("Air01 Control.app")
            let plist = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
            guard plist?["CFBundleShortVersionString"] as? String == version else {
                throw UpdateError("The downloaded app isn't version \(version).")
            }

            let dest = Bundle.main.bundlePath
            guard dest.hasSuffix(".app") else { throw UpdateError("This copy isn't running from an app bundle.") }
            let pid = ProcessInfo.processInfo.processIdentifier
            // Runs after we quit: wait for exit, swap bundles, relaunch.
            let script = """
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            rm -rf "$1.old" && mv "$1" "$1.old" && mv "$2" "$1" && rm -rf "$1.old" "$3"
            open "$1"
            """
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", script, "sh", dest, newApp.path, work.path]
            try p.run()
            if NSApp != nil { NSApp.terminate(nil) } else { exit(0) }
        } catch {
            state = .failed(error.localizedDescription)
            showResult = true
        }
    }

    // MARK: Processes

    static func ghPath() -> String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func gh(_ args: [String]) async throws -> String {
        guard let path = ghPath() else {
            throw UpdateError("Updates need the GitHub CLI. Install it with `brew install gh`, then run `gh auth login`.")
        }
        return try await run(path, args)
    }

    static func run(_ exe: String, _ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do {
                    try p.run()
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    let edata = err.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    if p.terminationStatus == 0 {
                        cont.resume(returning: String(decoding: data, as: UTF8.self))
                    } else {
                        let msg = String(decoding: edata, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        cont.resume(throwing: UpdateError(msg.isEmpty ? "\(exe) failed (\(p.terminationStatus))." : msg))
                    }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}
