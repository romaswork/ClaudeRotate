//
//  ClaudeRotateApp.swift
//  ClaudeRotate
//

import SwiftUI

@main
struct ClaudeRotateApp: App {
    @StateObject private var store: AppStore
    @StateObject private var rotation: RotationManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = AppStore()
        _store = StateObject(wrappedValue: store)
        _rotation = StateObject(wrappedValue: RotationManager(store: store))
    }

    var body: some Scene {
        Window("ClaudeRotate", id: "main") {
            RootView()
                .environmentObject(store)
                .environmentObject(rotation)
                .frame(minWidth: 480, minHeight: 360)
                .onAppear {
                    if store.startOnLaunch && !store.isRunning {
                        rotation.start()
                    }
                }
        }
        .windowResizability(.contentMinSize)
        .onChange(of: scenePhase) { _, phase in
            // Safety net: flush any unsaved edits when the app is no longer active.
            if phase != .active { store.save() }
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(store)
                .environmentObject(rotation)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: AppStore

    var body: some View {
        Image(systemName: store.isRunning ? "key.fill" : "pause.circle")
            .help(tooltip)
    }

    private var tooltip: String {
        if store.isRunning {
            if let name = store.currentKeyName {
                return "Running · \(name)"
            }
            return "Running"
        }
        return "Paused"
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rotation: RotationManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let name = store.currentKeyName {
            Text("Active: \(name)")
        } else {
            Text("No active key")
        }

        if let last = store.lastRotation {
            Text("Last: \(last.formatted(date: .omitted, time: .standard))")
        }

        if let error = store.lastError {
            Text("Error: \(error)")
        }

        Divider()

        if store.isRunning {
            Button("Stop Rotation") { rotation.stop() }
        } else {
            Button("Start Rotation") { rotation.start() }
        }

        Button("Rotate Now") { rotation.rotateNow() }

        Divider()

        Button("Settings…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Quit ClaudeRotate") { NSApp.terminate(nil) }
    }
}
