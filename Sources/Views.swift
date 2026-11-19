import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: KeyboardModel
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(spacing: 0) {
            Header(model: model)
            Divider()
            if model.link == .usb {
                SettingsForm(model: model)
            } else {
                StatusPanel(model: model)
            }
            Divider()
            UpdateFooter(updater: updater)
        }
        .frame(width: 460)
        .frame(minHeight: 520, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(alertTitle, isPresented: $updater.showResult) {
            if case .available = updater.state {
                Button("Install and Relaunch") { Task { await updater.install() } }
                Button("Later", role: .cancel) {}
            } else if case .failed = updater.state {
                Button("Open Releases Page") { NSWorkspace.shared.open(Updater.releasesURL) }
                Button("OK", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(alertMessage)
        }
    }

    private var alertTitle: String {
        switch updater.state {
        case .available(let v, _): return "Air01 Control \(v) is available"
        case .failed: return "Couldn't check for updates"
        default: return "You're up to date"
        }
    }

    private var alertMessage: String {
        switch updater.state {
        case .available(_, let notes): return notes.isEmpty ? "You have \(updater.currentVersion)." : notes
        case .failed(let msg): return msg
        default: return "Air01 Control \(updater.currentVersion) is the latest version."
        }
    }
}

private struct UpdateFooter: View {
    @ObservedObject var updater: Updater

    var body: some View {
        HStack(spacing: 8) {
            Text("Version \(updater.currentVersion)")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            switch updater.state {
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking…").font(.caption).foregroundStyle(.secondary)
            case .installing:
                ProgressView().controlSize(.small)
                Text("Installing update…").font(.caption).foregroundStyle(.secondary)
            case .available(let v, _):
                Button("Update to \(v)") { Task { await updater.install() } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            default:
                Button("Check for Updates") { Task { await updater.check(manual: true) } }
                    .buttonStyle(.link).font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Header

private struct Header: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            SaveBadge(state: model.save)
            if model.link == .usb {
                Button {
                    Task { await model.refresh() }
                } label: {
                    if model.refreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .help("Read settings from the keyboard again")
                .disabled(model.refreshing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var title: String {
        switch model.kind {
        case .air01Gen2: return "Akko Air01"
        case .air01Unverified(let name): return "Akko \(name)"
        case .unknown: return model.deviceID == nil ? "Akko Air01" : "Unknown keyboard"
        }
    }

    private var subtitle: String {
        switch model.link {
        case .searching: return "Not connected"
        case .bluetoothOnly: return "Bluetooth · settings need the cable"
        case .connecting: return "Connecting…"
        case .needsPermission: return "Waiting for permission"
        case .failed: return "Problem talking to the keyboard"
        case .usb:
            var parts = ["USB"]
            if let f = model.firmware { parts.append("firmware \(f)") }
            if let id = model.deviceID { parts.append("ID \(id)") }
            return parts.joined(separator: " · ")
        }
    }
}

private struct SaveBadge: View {
    let state: KeyboardModel.SaveState

    var body: some View {
        switch state {
        case .idle: EmptyView()
        case .saving:
            Label("Saving", systemImage: "arrow.down.circle").labelStyle(.titleAndIcon)
                .font(.caption).foregroundStyle(.secondary)
        case .saved:
            Label("Saved", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
        case .failed(let msg):
            Label("Not saved", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                .help(msg)
        }
    }
}

// MARK: - Not-connected states

private struct StatusPanel: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(heading).font(.title3.weight(.semibold))
            Text(detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
            actions
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: String {
        switch model.link {
        case .bluetoothOnly: return "cable.connector"
        case .needsPermission: return "lock.shield"
        case .failed: return "exclamationmark.triangle"
        default: return "cable.connector.horizontal"
        }
    }

    private var heading: String {
        switch model.link {
        case .bluetoothOnly(let name): return "\(name) is on Bluetooth"
        case .connecting: return "Connecting…"
        case .needsPermission: return "Allow keyboard access"
        case .failed: return "Couldn't read the keyboard"
        default: return "Plug in your Air01"
        }
    }

    private var detail: String {
        switch model.link {
        case .bluetoothOnly:
            return "Bluetooth doesn't carry the keyboard's settings channel. Connect the USB-C cable and settings will appear here. If nothing happens, slide the mode switch to wired."
        case .needsPermission:
            return "macOS needs you to allow Air01 Control under Input Monitoring before it can talk to the keyboard. After allowing it, quit and reopen the app."
        case .failed(let msg):
            return msg
        case .connecting:
            return "Reading settings from the keyboard."
        default:
            return "Connect the keyboard with its USB-C cable. Bluetooth and the 2.4 GHz dongle can't change settings."
        }
    }

    @ViewBuilder private var actions: some View {
        switch model.link {
        case .needsPermission:
            HStack {
                Button("Open Input Monitoring") { model.requestPermission() }
                Button("Try Again") { model.retry() }
            }
        case .failed:
            Button("Try Again") { model.retry() }
        default:
            EmptyView()
        }
    }
}

// MARK: - Settings

private struct SettingsForm: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            if !model.writable {
                Section {
                    Label {
                        Text("This is a different Air01 hardware revision that hasn't been confirmed to work with this app, so it only reads settings and won't change anything.")
                    } icon: {
                        Image(systemName: "lock")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            if let p = model.profile {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(0..<4) { i in
                            ProfileCard(number: i + 1, active: i == p, summary: model.keymapSummary(i)) {
                                model.setProfile(i)
                            }
                        }
                    }
                    HStack {
                        Text("Remap keys, add shortcuts and media keys, edit the Fn layer.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Edit Keys…") { openWindow(id: "keys") }
                    }
                } header: {
                    Text("Profiles")
                } footer: {
                    Text("Click a profile to switch to it. Profiles hold separate key layouts; lighting, colours and effects are shared by all four.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if model.led != nil {
                LightSection(model: model, isSide: false)
            }
            if model.side != nil {
                LightSection(model: model, isSide: true)
            }

            if model.debounce != nil || model.sleep != nil || model.autoOS != nil {
                DeviceSection(model: model)
            }

            if model.writable {
                BackupSection(model: model)
            }
        }
        .formStyle(.grouped)
        .disabled(!model.writable)
    }
}

private struct BackupSection: View {
    @ObservedObject var model: KeyboardModel
    @State private var confirmRestore: URL?

    var body: some View {
        Section {
            if let (msg, f) = model.backupProgress {
                VStack(alignment: .leading, spacing: 6) {
                    Text(msg).font(.callout)
                    ProgressView(value: f)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Back up everything")
                        Text(model.lastBackup.map { "Last backup: \($0.deletingPathExtension().lastPathComponent)" }
                             ?? "Lighting, settings and all key layouts, saved to a file. One is made automatically before your first key change.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Back Up Now") { Task { await model.backUpNow() } }
                }
                HStack {
                    Button("Restore…") { pickBackup() }
                    Button("Show Backups") { NSWorkspace.shared.open(Backup.folder) }
                    Spacer()
                }
            }
        } header: {
            Text("Backup")
        }
        .alert("Restore this backup?", isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } })) {
            Button("Restore") {
                if let url = confirmRestore { Task { await model.restore(from: url) } }
                confirmRestore = nil
            }
            Button("Cancel", role: .cancel) { confirmRestore = nil }
        } message: {
            Text("Keys, lighting and settings on the keyboard will be changed back to \(confirmRestore?.deletingPathExtension().lastPathComponent ?? "the backup"). Only keys that differ are rewritten.")
        }
        .alert(model.backupError ?? model.restoreResult ?? "",
               isPresented: Binding(get: { model.backupError != nil || model.restoreResult != nil },
                                    set: { if !$0 { model.backupError = nil; model.restoreResult = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private func pickBackup() {
        let panel = NSOpenPanel()
        panel.directoryURL = Backup.folder
        panel.allowedContentTypes = [.json]
        panel.message = "Choose an Air01 backup to restore"
        if panel.runModal() == .OK, let url = panel.url { confirmRestore = url }
    }
}

private struct ProfileCard: View {
    let number: Int
    let active: Bool
    let summary: String?
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Profile \(number)").font(.headline)
                    Spacer()
                    if active {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                    }
                }
                Text(active ? "Active" : "Click to switch")
                    .font(.caption.weight(active ? .semibold : .regular))
                    .foregroundStyle(active ? Color.accentColor : .secondary)
                Text(summary ?? "Key layout not read")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(active ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(active ? "This profile is active" : "Switch to profile \(number)")
    }
}

private struct LightSection: View {
    @ObservedObject var model: KeyboardModel
    let isSide: Bool

    var body: some View {
        let l = model.lighting(isSide)
        let effects = isSide ? Effects.side : Effects.main
        let effect = Effects.find(l.mode, side: isSide)

        Section(isSide ? "Side light" : "Backlight") {
            Picker("Effect", selection: model.bindMode(isSide)) {
                ForEach(effects) { Text($0.name).tag($0.mode) }
                if effect == nil { Text("Custom (mode \(l.mode))").tag(l.mode) }
            }

            if let effect, !effect.options.isEmpty {
                Picker("Direction", selection: model.bind(isSide, \.option)) {
                    ForEach(Array(effect.options.enumerated()), id: \.offset) { i, name in
                        Text(name).tag(UInt8(i))
                    }
                }
            }

            if effect?.hasColor ?? true {
                Toggle("Rainbow colours", isOn: model.bind(isSide, \.rainbow))
                if !l.rainbow {
                    ColorPicker("Colour", selection: model.bindColor(isSide), supportsOpacity: false)
                    Swatches { model.setPreset($0, side: isSide) }
                }
                LabeledContent {
                    HStack(spacing: 8) {
                        Image(systemName: "circle").foregroundStyle(.secondary).font(.caption)
                        if l.rainbow {
                            Slider(value: .constant(1.0), in: 0...1).disabled(true)
                            Image(systemName: "rainbow").symbolRenderingMode(.multicolor).font(.caption)
                        } else {
                            Slider(value: model.bindSaturation(isSide), in: 0...1)
                            Image(systemName: "circle.fill").foregroundStyle(model.bindColor(isSide).wrappedValue).font(.caption)
                        }
                    }
                    .frame(width: 220)
                } label: {
                    Text("Saturation")
                    if l.rainbow {
                        Text("Rainbow colours are fixed by the keyboard.")
                    }
                }
            }

            if effect?.mode != 0 {
                StepSlider(title: "Brightness", value: model.bind(isSide, \.brightness), max: 4,
                           low: "sun.min", high: "sun.max")
            }
            if effect?.hasSpeed ?? true {
                StepSlider(title: "Speed", value: model.bind(isSide, \.speed), max: effect?.maxSpeed ?? 4,
                           low: "tortoise", high: "hare")
            }
        }
    }
}

private struct StepSlider: View {
    let title: String
    @Binding var value: Int
    let max: Int
    let low: String
    let high: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Image(systemName: low).foregroundStyle(.secondary).font(.caption)
                Slider(
                    value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                    in: 0...Double(max), step: 1
                )
                Image(systemName: high).foregroundStyle(.secondary).font(.caption)
            }
            .frame(width: 220)
        }
    }
}

private struct Swatches: View {
    let pick: ((UInt8, UInt8, UInt8)) -> Void

    private let colors: [(UInt8, UInt8, UInt8)] = [
        (255, 0, 0), (255, 96, 0), (255, 200, 0), (0, 255, 0), (0, 255, 200),
        (0, 120, 255), (120, 0, 255), (255, 0, 160), (255, 255, 255),
    ]

    var body: some View {
        LabeledContent("Presets") {
            HStack(spacing: 6) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                    Button { pick(c) } label: {
                        Circle()
                            .fill(Color(.sRGB, red: Double(c.0) / 255, green: Double(c.1) / 255, blue: Double(c.2) / 255))
                            .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct DeviceSection: View {
    @ObservedObject var model: KeyboardModel

    var body: some View {
        Section("Keyboard") {
            if let d = model.debounce {
                Stepper(value: Binding(get: { d }, set: { model.setDebounce($0) }), in: 1...10) {
                    LabeledContent("Debounce", value: "\(d)")
                }
            }
            if let s = model.sleep {
                SleepPicker(title: "Sleep on Bluetooth", seconds: s.sleepBT, choices: Self.lightChoices) {
                    var t = s; t.sleepBT = $0; model.setSleep(t)
                }
                SleepPicker(title: "Deep sleep on Bluetooth", seconds: s.deepBT, choices: Self.deepChoices) {
                    var t = s; t.deepBT = $0; model.setSleep(t)
                }
                SleepPicker(title: "Sleep on 2.4 GHz", seconds: s.sleep24, choices: Self.lightChoices) {
                    var t = s; t.sleep24 = $0; model.setSleep(t)
                }
                SleepPicker(title: "Deep sleep on 2.4 GHz", seconds: s.deep24, choices: Self.deepChoices) {
                    var t = s; t.deep24 = $0; model.setSleep(t)
                }
            }
            if let a = model.autoOS {
                Toggle(isOn: Binding(get: { a }, set: { model.setAutoOS($0) })) {
                    Text("Auto-detect Mac / Windows")
                    Text("Switches the keyboard's Mac or Windows mode to match the computer it's plugged into.")
                }
            }
        }
    }

    static let lightChoices: [UInt16] = [60, 120, 180, 300, 600, 900, 1800]
    static let deepChoices: [UInt16] = [300, 600, 900, 1800, 3600, 7200]
}

private struct SleepPicker: View {
    let title: String
    let seconds: UInt16
    let choices: [UInt16]
    let set: (UInt16) -> Void

    var body: some View {
        let all = choices.contains(seconds) ? choices : (choices + [seconds]).sorted()
        Picker(title, selection: Binding(get: { seconds }, set: set)) {
            ForEach(all, id: \.self) { Text(Self.label($0)).tag($0) }
        }
    }

    static func label(_ s: UInt16) -> String {
        if s == 0 { return "Off" }
        if s % 3600 == 0 { return "\(s / 3600) hr" }
        if s % 60 == 0 { return "\(s / 60) min" }
        return "\(s) s"
    }
}
