//
//  RootView.swift
//  ClaudeRotate
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    var body: some View {
        TabView {
            KeysView()
                .tabItem { Label("Keys", systemImage: "key") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .padding()
    }
}

// MARK: - Keys

struct KeysView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rotation: RotationManager

    @State private var editorKey: APIKey?
    @State private var editorIsNew = false
    @State private var selection: APIKey.ID?

    var body: some View {
        VStack(spacing: 0) {
            if store.keys.isEmpty {
                emptyState
            } else {
                keyList
            }
            Divider()
            bottomBar
        }
        .sheet(item: $editorKey) { key in
            KeyEditor(key: key, isNew: editorIsNew) { edited in
                if editorIsNew {
                    store.add(edited)
                } else {
                    store.updateKey(edited)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No API Keys")
                .font(.title3.weight(.semibold))
            Text("Add a key to start rotating credentials.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                presentNew()
            } label: {
                Label("Add Key", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var keyList: some View {
        List(selection: $selection) {
            ForEach($store.keys) { $key in
                KeyRow(key: $key,
                       isActive: store.currentKeyID == key.id,
                       testState: store.testStates[key.id]) {
                    store.save()
                }
                .tag(key.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { presentEdit(key) }
                .contextMenu {
                    Button("Test") { store.test(key) }
                    Button("Set as Active Now") { rotation.apply(key) }
                        .disabled(store.currentKeyID == key.id)
                    Divider()
                    Button("Edit") { presentEdit(key) }
                    Button("Delete", role: .destructive) { store.deleteKey(key) }
                }
            }
            .onMove { store.move(from: $0, to: $1) }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {
                presentNew()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 22)
            }
            .help("Add key")

            Button {
                if let id = selection, let key = store.keys.first(where: { $0.id == id }) {
                    store.deleteKey(key)
                    selection = nil
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 22)
            }
            .help("Remove selected key")
            .disabled(selection == nil)

            Divider().frame(height: 16)

            Button {
                if let id = selection, let key = store.keys.first(where: { $0.id == id }) {
                    presentEdit(key)
                }
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 24, height: 22)
            }
            .help("Edit selected key")
            .disabled(selection == nil)

            Button {
                if let id = selection, let key = store.keys.first(where: { $0.id == id }) {
                    rotation.apply(key)
                }
            } label: {
                Image(systemName: "checkmark.circle")
                    .frame(width: 24, height: 22)
            }
            .help("Set selected key as active now")
            .disabled(selection == nil || selection == store.currentKeyID)

            Divider().frame(height: 16)

            Button {
                store.testAll()
            } label: {
                Image(systemName: "checkmark.shield")
                    .frame(width: 24, height: 22)
            }
            .help("Test all keys")
            .disabled(store.keys.isEmpty)

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func presentNew() {
        editorIsNew = true
        // Prefill base URL from the previous key (if any), otherwise leave empty.
        editorKey = APIKey(baseURL: store.keys.last?.baseURL ?? "")
    }

    private func presentEdit(_ key: APIKey) {
        editorIsNew = false
        editorKey = key
    }
}

struct KeyRow: View {
    @Binding var key: APIKey
    let isActive: Bool
    let testState: KeyTestState?
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                Text(key.name.isEmpty ? "Untitled" : key.name)
                    .fontWeight(.medium)
                Text(key.baseURL.isEmpty ? "No base URL" : key.baseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            testIndicator
            if isActive {
                Text("Active")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.15), in: Capsule())
            }
            Toggle("", isOn: $key.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: key.enabled) { _, _ in onToggle() }
        }
        .padding(.vertical, 4)
    }

    private var statusDot: some View {
        Circle()
            .fill(isActive ? Color.green : (key.enabled ? Color.secondary : Color.secondary.opacity(0.3)))
            .frame(width: 8, height: 8)
    }

    @ViewBuilder
    private var testIndicator: some View {
        switch testState {
        case .testing:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Valid")
        case .failure(let message):
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .help(message)
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Key Editor

struct KeyEditor: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: APIKey
    @State private var testState: KeyTestState?
    let isNew: Bool
    let onSave: (APIKey) -> Void

    init(key: APIKey, isNew: Bool, onSave: @escaping (APIKey) -> Void) {
        _draft = State(initialValue: key)
        self.isNew = isNew
        self.onSave = onSave
    }

    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !draft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canTest: Bool {
        !draft.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func runTest() {
        testState = .testing
        let api = draft.apiKey
        let base = draft.baseURL
        Task {
            let result = await testKey(apiKey: api, baseURL: base)
            switch result {
            case .valid: testState = .success
            case .invalid(let code): testState = .failure("HTTP \(code)")
            case .error(let message): testState = .failure(message)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "New Key" : "Edit Key")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("e.g. Personal"))
                } footer: {
                    Text("A label to recognize this key. Not written to the file.")
                }

                Section {
                    TextField("API Key", text: $draft.apiKey, prompt: Text("sk-ant-…"))
                        .font(.system(.body, design: .monospaced))
                    TextField("Base URL", text: $draft.baseURL, prompt: Text("https://api.anthropic.com"))
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Credentials")
                } footer: {
                    Text("Written to ANTHROPIC_API_KEY / ANTHROPIC_BASE_URL on rotation.")
                }

                Section {
                    Toggle("Include in rotation", isOn: $draft.enabled)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 10) {
                Button("Test") { runTest() }
                    .disabled(!canTest)
                testStatusView
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 440, height: 440)
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testState {
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Testing…").foregroundStyle(.secondary)
            }
            .font(.callout)
        case .success:
            Label("Valid", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(1)
                .help(message)
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rotation: RotationManager

    @FocusState private var filePathFocused: Bool

    var body: some View {
        Form {
            Section("Target File") {
                HStack {
                    TextField("~/.claude/settings.json", text: $store.filePath)
                        .textFieldStyle(.roundedBorder)
                        .focused($filePathFocused)
                        .onChange(of: filePathFocused) { _, focused in
                            if !focused { store.save() }
                        }
                        .onSubmit { store.save() }
                    Button("Browse…") { browse() }
                }
            }

            Section("Rotation") {
                HStack {
                    Text("Interval (minutes)")
                    Spacer()
                    TextField("", value: $store.intervalMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: store.intervalMinutes) { _, newValue in
                            if newValue < 1 { store.intervalMinutes = 1 }
                            store.save()
                            rotation.restartIfRunning()
                        }
                    Stepper("", value: $store.intervalMinutes, in: 1...1440)
                        .labelsHidden()
                }

                Toggle("Start rotation on launch", isOn: $store.startOnLaunch)
                    .onChange(of: store.startOnLaunch) { _, _ in store.save() }
            }

            Section("Status") {
                LabeledContent("State") {
                    Text(store.isRunning ? "Running" : "Stopped")
                        .foregroundStyle(store.isRunning ? .green : .secondary)
                }
                LabeledContent("Active key") {
                    Text(store.currentKeyName ?? "—")
                }
                if let last = store.lastRotation {
                    LabeledContent("Last rotation") {
                        Text(last.formatted(date: .abbreviated, time: .standard))
                    }
                }
                if let error = store.lastError {
                    LabeledContent("Error") {
                        Text(error).foregroundStyle(.red)
                    }
                }

                HStack {
                    if store.isRunning {
                        Button("Stop") { rotation.stop() }
                    } else {
                        Button("Start") { rotation.start() }
                    }
                    Button("Rotate Now") { rotation.rotateNow() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            store.filePath = url.path
            store.save()
        }
    }
}
