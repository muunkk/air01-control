import AppKit
import Foundation

/// Checks GitHub Releases for a newer build and installs it in place.
/// Uses the public GitHub API, so no login is needed.
@MainActor
final class Updater: ObservableObject {
    static let repo = "muunkk/air01-control"
    static let releasesURL = URL(string: "https://github.com/\(repo)/releases")!
    static let latestAPI = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let body: String?
        let assets: [Asset]
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, notes: String, download: URL)
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
            let release = try await Self.latestRelease()
            let tag = release.tag_name.trimmingCharacters(in: .whitespaces)
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let notes = (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !latest.isEmpty else { throw UpdateError("GitHub returned no release.") }
            if Self.isNewer(latest, than: currentVersion) {
                guard let zip = release.assets.first(where: { $0.name.hasPrefix("Air01-Control-") && $0.name.hasSuffix(".zip") }) else {
                    throw UpdateError("The release has no app download.")
                }
                state = .available(version: latest, notes: notes, download: zip.browser_download_url)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
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
        guard case .available(let version, _, let download) = state else { return }
        state = .installing
        let fm = FileManager.default
        let tag = UUID().uuidString
        let work = fm.temporaryDirectory.appendingPathComponent("air01-update-\(tag)")
        let dest = Bundle.main.bundlePath
        let parent = (dest as NSString).deletingLastPathComponent
        // Staged next to the installed app so the final swap is a same-volume rename.
        let staged = URL(fileURLWithPath: parent).appendingPathComponent(".Air01 Control-update-\(tag).app")
        var handedOff = false
        defer {
            if !handedOff {
                try? fm.removeItem(at: work)
                try? fm.removeItem(at: staged)
            }
        }
        do {
            guard dest.hasSuffix(".app") else { throw UpdateError("This copy isn't running from an app bundle.") }
            guard !dest.contains("/AppTranslocation/"), fm.isWritableFile(atPath: parent) else {
                throw UpdateError("Move Air01 Control to your Applications folder, reopen it, then update.")
            }

            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let (tmp, response) = try await URLSession.shared.download(from: download)
            let zip = work.appendingPathComponent("update.zip")
            try fm.moveItem(at: tmp, to: zip)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw UpdateError("The download failed (HTTP \(status)).") }
            let unpacked = work.appendingPathComponent("unpacked")
            _ = try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])

            let newApp = unpacked.appendingPathComponent("Air01 Control.app")
            let plist = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist"))
            guard plist?["CFBundleShortVersionString"] as? String == version else {
                throw UpdateError("The downloaded app isn't version \(version).")
            }
            guard Self.runsHere(newApp) else {
                throw UpdateError("Version \(version) doesn't support this Mac's processor.")
            }

            try fm.moveItem(at: newApp, to: staged)

            let pid = ProcessInfo.processInfo.processIdentifier
            let old = "\(parent)/.Air01 Control-old-\(tag).app"
            // Runs after we quit: wait for exit, swap bundles with same-volume
            // renames (putting the old one back if the swap fails), clean up, relaunch.
            let script = """
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            if mv "$1" "$4"; then
              if mv "$2" "$1"; then rm -rf "$4"; else mv "$4" "$1"; fi
            fi
            rm -rf "$2" "$3"
            open "$1"
            """
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", script, "sh", dest, staged.path, work.path, old]
            try p.run()
            handedOff = true
            if NSApp != nil { NSApp.terminate(nil) } else { exit(0) }
        } catch {
            state = .failed(error.localizedDescription)
            showResult = true
        }
    }

    // MARK: Network and processes

    private static func latestRelease() async throws -> Release {
        var req = URLRequest(url: latestAPI)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw UpdateError("No release has been published yet.") }
        guard status == 200 else { throw UpdateError("GitHub returned HTTP \(status).") }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    /// True if the app's executable has a slice for this Mac's CPU.
    static func runsHere(_ app: URL) -> Bool {
        #if arch(arm64)
        let native = NSBundleExecutableArchitectureARM64
        #else
        let native = NSBundleExecutableArchitectureX86_64
        #endif
        let archs = Bundle(url: app)?.executableArchitectures?.map(\.intValue) ?? []
        return archs.contains(native)
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
