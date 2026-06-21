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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.keys.isEmpty {
                Spacer()
                Text("No keys yet. Add one to get started.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                List {
                    ForEach($store.keys) { $key in
                        KeyRow(key: $key)
                    }
                    .onDelete { store.deleteKeys(at: $0) }
                    .onMove { store.move(from: $0, to: $1) }
                }
            }

            HStack {
                Button {
                    store.addKey()
                } label: {
                    Label("Add Key", systemImage: "plus")
                }
                Spacer()
            }
        }
    }
}

struct KeyRow: View {
    @Binding var key: APIKey
    @EnvironmentObject private var store: AppStore

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Name") {
                    TextField("Name", text: $key.name)
                }
                LabeledContent("ANTHROPIC_API_KEY") {
                    SecureField("sk-...", text: $key.apiKey)
                }
                LabeledContent("ANTHROPIC_BASE_URL") {
                    TextField("https://...", text: $key.baseURL)
                }
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        store.deleteKey(key)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.vertical, 4)
        } label: {
            HStack {
                Toggle("", isOn: $key.enabled)
                    .labelsHidden()
                VStack(alignment: .leading) {
                    Text(key.name.isEmpty ? "Untitled" : key.name)
                        .fontWeight(.medium)
                    if !key.baseURL.isEmpty {
                        Text(key.baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if store.currentKeyID == key.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rotation: RotationManager

    var body: some View {
        Form {
            Section("Target File") {
                HStack {
                    TextField("/path/to/settings.json", text: $store.filePath)
                        .textFieldStyle(.roundedBorder)
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
                            rotation.restartIfRunning()
                        }
                    Stepper("", value: $store.intervalMinutes, in: 1...1440)
                        .labelsHidden()
                }

                Toggle("Start rotation on launch", isOn: $store.startOnLaunch)
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
        }
    }
}
