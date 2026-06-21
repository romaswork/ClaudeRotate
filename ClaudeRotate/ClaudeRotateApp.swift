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
                    // Restore and immediately write the last active key from the
                    // previous session, so the target file reflects it right away.
                    let restored = rotation.applyCurrentKey()
                    if store.startOnLaunch && !store.isRunning {
                        // If a key was restored, keep it for the first interval
                        // instead of immediately advancing to the next one.
                        rotation.start(immediate: !restored)
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
                return store.tr("Запущена · \(name)", "Running · \(name)")
            }
            return store.tr("Запущена", "Running")
        }
        return store.tr("На паузе", "Paused")
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rotation: RotationManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let name = store.currentKeyName {
            Text(store.tr("Активен: \(name)", "Active: \(name)"))
        } else {
            Text(store.tr("Нет активного ключа", "No active key"))
        }

        if let last = store.lastRotation {
            Text(store.tr("Последняя: \(last.formatted(date: .omitted, time: .standard))",
                          "Last: \(last.formatted(date: .omitted, time: .standard))"))
        }

        if let error = store.lastError {
            Text(store.tr("Ошибка: \(error)", "Error: \(error)"))
        }

        Divider()

        if store.isRunning {
            Button(store.tr("Остановить ротацию", "Stop Rotation")) { rotation.stop() }
        } else {
            Button(store.tr("Запустить ротацию", "Start Rotation")) { rotation.start() }
        }

        Button(store.tr("Сменить сейчас", "Rotate Now")) { rotation.rotateNow() }

        Divider()

        Button(store.tr("Настройки…", "Settings…")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button(store.tr("Выйти", "Quit ClaudeRotate")) { NSApp.terminate(nil) }
    }
}
