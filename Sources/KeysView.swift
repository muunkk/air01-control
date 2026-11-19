import SwiftUI

/// Key remapping: a drawn Air01, a layer picker and an editor for the selected key.
struct KeysView: View {
    @ObservedObject var model: KeyboardModel
    @State private var layerChoice = 0          // 0 base, 1 Fn
    @State private var fnOS = 1                 // 1 Mac, 0 Windows
    @State private var selected: Int?

    init(model: KeyboardModel, initialSelection: Int? = nil) {
        self.model = model
        _selected = State(initialValue: initialSelection)
    }

    private var layer: KeyLayer { layerChoice == 0 ? .base : .fn(os: fnOS) }

    var body: some View {
        Group {
            if model.writable, let p = model.profile {
                VStack(alignment: .leading, spacing: 14) {
                    toolbar(p)
                    KeyboardCanvas(model: model, layer: layer, selected: $selected)
                    Divider()
                    if let slot = selected, let key = Air01Layout.key(slot) {
                        KeyEditor(model: model, key: key, layer: layer)
                            .id("\(slot)-\(layer)")
                    } else {
                        Text("Click a key to change what it does.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
                    }
                    if let s = model.keyStatus {
                        Label(s, systemImage: model.keyBusy ? "arrow.triangle.2.circlepath" : "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "cable.connector").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("Connect your Air01 with the USB-C cable to edit keys.")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 780, height: 420)
            }
        }
        .frame(width: 780)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { if let os = model.osMode, os <= 1 { fnOS = os } }
    }

    private func toolbar(_ p: Int) -> some View {
        HStack(spacing: 16) {
            Picker("Profile", selection: Binding(get: { p }, set: { model.setProfile($0) })) {
                ForEach(0..<4) { Text("\($0 + 1)").tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
            .help("Edits apply to the active profile")

            Picker("Layer", selection: $layerChoice) {
                Text("Base").tag(0)
                Text("Fn layer").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 190)

            if layerChoice == 1 {
                Picker("", selection: $fnOS) {
                    Text("Mac").tag(1)
                    Text("Windows").tag(0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .help("The keyboard keeps a separate Fn layer for Mac and Windows mode")
            }
            Spacer()
        }
    }
}

// MARK: - Keyboard drawing

private struct KeyboardCanvas: View {
    @ObservedObject var model: KeyboardModel
    let layer: KeyLayer
    @Binding var selected: Int?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Air01Layout.keys) { key in
                KeyCap(key: key, value: model.value(layer, slot: key.slot), layer: layer, isSelected: selected == key.slot)
                    .frame(width: key.frame.width, height: key.frame.height)
                    .offset(x: key.frame.minX + 4, y: key.frame.minY + 4)
                    .onTapGesture { selected = key.slot }
            }
        }
        .frame(width: Air01Layout.size.width + 8, height: Air01Layout.size.height + 8, alignment: .topLeading)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .frame(maxWidth: .infinity)
    }
}

private struct KeyCap: View {
    let key: PhysicalKey
    let value: [UInt8]?
    let layer: KeyLayer
    let isSelected: Bool

    /// What to show under the legend: the new function, if it isn't the default.
    private var note: String? {
        guard let v = value else { return nil }
        switch layer {
        case .base: return v == key.factory ? nil : KeyAction(v).name()
        case .fn: return v == [0, 0, 0, 0] ? nil : KeyAction(v).name(fnLayer: true)
        }
    }

    var body: some View {
        let changed = note != nil
        VStack(alignment: .leading, spacing: 1) {
            Text(key.label).font(.system(size: 10, weight: .medium))
            if let note {
                Text(note).font(.system(size: 8)).foregroundStyle(Color.accentColor)
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(changed ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .help(note.map { "\(key.label): \($0)" } ?? key.label)
    }
}

// MARK: - Editor

private struct KeyEditor: View {
    @ObservedObject var model: KeyboardModel
    let key: PhysicalKey
    let layer: KeyLayer

    enum Kind: String, CaseIterable, Identifiable {
        case key = "Key", shortcut = "Shortcut", mac = "Mac action", media = "Media", none = "Off"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .key
    @State private var usage: UInt8 = 0x29
    @State private var mods: Set<UInt8> = []
    @State private var shortcutKey: UInt8 = 0x2C
    @State private var media: UInt16 = 0x00CD
    @State private var macIndex = 0

    private var isFn: Bool { layer != .base }
    private var current: KeyAction? { model.value(layer, slot: key.slot).map(KeyAction.init) }

    private var draft: KeyAction {
        switch kind {
        case .key: return .key(usage)
        case .shortcut:
            let order: [UInt8] = [0xE3, 0xE2, 0xE0, 0xE1]
            return .shortcut(mods: order.filter(mods.contains), key: shortcutKey)
        case .mac: return KeyCatalog.macShortcuts[macIndex].1
        case .media: return .media(media)
        case .none: return .none
        }
    }

    var body: some View {
        if !isFn && key.slot == Air01Layout.fnSlot {
            Label("The Fn key can't be remapped here, so you never lose access to the Fn layer.", systemImage: "lock")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(key.label) key").font(.title3.weight(.semibold))
                    Text("\(isFn ? "With Fn: " : "Does: ")\(current?.name(fnLayer: isFn) ?? "–")")
                        .foregroundStyle(.secondary)
                    if !isFn, let c = current, c.bytes == key.factory {
                        Text("Factory default").font(.caption).foregroundStyle(.tertiary)
                    }
                    if current?.isBoardFunction == true {
                        Label("This is one of the keyboard's built-in functions. Replacing it removes that until you restore a backup.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 230, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    Picker("Make it", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0 == .none && isFn ? "Base key" : $0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    editorFields

                    HStack {
                        if !isFn, current?.bytes != key.factory {
                            Button("Reset to Default") {
                                Task { await model.assign(KeyAction(key.factory), to: key.slot, on: layer) }
                            }
                        }
                        Spacer()
                        Button("Apply") { Task { await model.assign(draft, to: key.slot, on: layer) } }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(model.keyBusy || draft == current)
                    }
                }
            }
            .frame(minHeight: 150, alignment: .top)
            .disabled(model.keyBusy)
            .onAppear(perform: loadFromCurrent)
        }
    }

    @ViewBuilder private var editorFields: some View {
        switch kind {
        case .key:
            keyPicker("Sends", selection: $usage)
        case .shortcut:
            HStack(spacing: 6) {
                ForEach(KeyCatalog.modifiers, id: \.1) { name, u in
                    Toggle(name, isOn: Binding(
                        get: { mods.contains(u) },
                        set: { on in
                            if on { if mods.count < 2 { mods.insert(u) } } else { mods.remove(u) }
                        }))
                    .toggleStyle(.button)
                }
            }
            keyPicker("plus", selection: $shortcutKey)
            Text("Up to two modifiers.").font(.caption).foregroundStyle(.secondary)
        case .mac:
            Picker("Action", selection: $macIndex) {
                ForEach(KeyCatalog.macShortcuts.indices, id: \.self) { Text(KeyCatalog.macShortcuts[$0].0).tag($0) }
            }
        case .media:
            Picker("Action", selection: $media) {
                ForEach(KeyCatalog.media, id: \.1) { Text($0.0).tag($0.1) }
            }
        case .none:
            Text(isFn ? "With Fn held, this key does the same as without it."
                      : "The key does nothing. You can turn it back on any time.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func keyPicker(_ title: String, selection: Binding<UInt8>) -> some View {
        Picker(title, selection: selection) {
            ForEach(KeyCatalog.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.keys, id: \.self) { Text(KeyCatalog.name($0)).tag($0) }
                }
            }
        }
    }

    private func loadFromCurrent() {
        guard let c = current else { return }
        switch c {
        case .key(let u): kind = .key; usage = u
        case .shortcut(let m, let k):
            if let i = KeyCatalog.macShortcuts.firstIndex(where: { $0.1 == c }) { kind = .mac; macIndex = i }
            else { kind = .shortcut; mods = Set(m.prefix(2)); shortcutKey = k }
        case .media(let u):
            kind = .media
            media = KeyCatalog.media.contains { $0.1 == u } ? u : 0x00CD
        case .none: kind = .none
        case .raw: kind = .key
        }
    }
}
