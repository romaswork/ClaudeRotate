//
//  KeyRotatorApp.swift
//  KeyRotator
//

import SwiftUI

@main
struct KeyRotatorApp: App {
    @StateObject private var store: AppStore
    @StateObject private var rotation: RotationManager
    @StateObject private var statusItem: StatusItemController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = AppStore()
        let rotation = RotationManager(store: store)
        _store = StateObject(wrappedValue: store)
        _rotation = StateObject(wrappedValue: rotation)
        _statusItem = StateObject(wrappedValue: StatusItemController(store: store, rotation: rotation))
    }

    var body: some Scene {
        Window("KeyRotator", id: "main") {
            RootView()
                .environmentObject(store)
                .environmentObject(rotation)
                .frame(minWidth: 680, minHeight: 380)
                .background(OpenWindowBridge(statusItem: statusItem))
                .onAppear {
                    applyActivationPolicy(hidden: store.hideFromDock)
                    // Restore and immediately write the last active key from the
                    // previous session, so the target file reflects it right away.
                    let restored = rotation.applyCurrentKey()
                    if store.startOnLaunch && !store.isRunning {
                        // If a key was restored, keep it for the first interval
                        // instead of immediately advancing to the next one.
                        rotation.start(immediate: !restored)
                    }
                }
                .onChange(of: store.hideFromDock) { _, hidden in
                    applyActivationPolicy(hidden: hidden)
                }
        }
        .defaultSize(width: 700, height: 450)
        .windowResizability(.contentMinSize)
        .onChange(of: scenePhase) { _, phase in
            // Safety net: flush any unsaved edits when the app is no longer active.
            if phase != .active { store.save() }
        }
    }

    /// Переключает видимость приложения в Dock. `.accessory` убирает иконку из
    /// Dock (приложение остаётся в меню-баре); `.regular` показывает её снова.
    private func applyActivationPolicy(hidden: Bool) {
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
        if !hidden {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

/// Передаёт SwiftUI-действие `openWindow` в `StatusItemController`, чтобы левый
/// клик по значку меню-бара мог заново открыть главное окно даже после его
/// закрытия (у AppKit-кода прямого доступа к `openWindow` нет).
private struct OpenWindowBridge: View {
    let statusItem: StatusItemController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear {
                statusItem.openMainWindow = { openWindow(id: "main") }
            }
    }
}
