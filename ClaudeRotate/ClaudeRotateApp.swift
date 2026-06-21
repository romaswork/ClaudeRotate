//
//  ClaudeRotateApp.swift
//  ClaudeRotate
//

import SwiftUI

@main
struct ClaudeRotateApp: App {
    @StateObject private var store: AppStore
    @StateObject private var rotation: RotationManager

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

        MenuBarExtra("ClaudeRotate", systemImage: "key.fill") {
            MenuBarContent()
                .environmentObject(store)
                .environmentObject(rotation)
        }
        .menuBarExtraStyle(.menu)
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
