//
//  StatusItemController.swift
//  KeyRotator
//

import AppKit
import Combine
import SwiftUI

/// Значок в меню-баре на базе `NSStatusItem` (вместо SwiftUI `MenuBarExtra`):
/// левый клик открывает главное окно приложения, правый клик (или Ctrl+клик) —
/// контекстное меню. `MenuBarExtra` не различает кнопки мыши, поэтому значок
/// управляется вручную через AppKit.
final class StatusItemController: NSObject, ObservableObject {
    private let store: AppStore
    private let rotation: RotationManager
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?

    /// Открытие главного окна через SwiftUI `openWindow(id: "main")`;
    /// проставляется из `OpenWindowBridge` при первом показе окна.
    /// Фолбэк — поиск существующего NSWindow по идентификатору.
    var openMainWindow: (() -> Void)?

    init(store: AppStore, rotation: RotationManager) {
        self.store = store
        self.rotation = rotation
        super.init()
        // Значок создаём после завершения запуска приложения, а не в App.init.
        DispatchQueue.main.async { [weak self] in self?.install() }
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(statusButtonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateAppearance()
        // objectWillChange срабатывает до изменения значений, поэтому
        // перечитываем состояние асинхронно на главном потоке.
        cancellable = store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateAppearance() }
    }

    // MARK: - Клики

    @objc private func statusButtonClicked() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            showMenu()
        } else {
            openApp()
        }
    }

    /// Показ меню по требованию: временно назначаем `menu` и эмулируем клик,
    /// после закрытия меню снимаем назначение — иначе меню перехватывало бы
    /// и левый клик.
    private func showMenu() {
        guard let item = statusItem else { return }
        item.menu = buildMenu()
        item.button?.performClick(nil)
        item.menu = nil
    }

    func openApp() {
        if let openMainWindow {
            openMainWindow()
        } else if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Меню

    /// Меню собирается заново при каждом правом клике — так все строки
    /// (активный ключ, время, ошибки, язык) всегда актуальны.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(actionItem(store.tr("Показать приложение", "Show App"), #selector(openAppAction)))
        menu.addItem(.separator())

        if let name = store.currentKeyName {
            menu.addItem(infoItem(store.tr("Активен: \(name)", "Active: \(name)")))
        } else {
            menu.addItem(infoItem(store.tr("Нет активного ключа", "No active key")))
        }

        if let last = store.lastRotation {
            let time = last.formatted(date: .omitted, time: .standard)
            menu.addItem(infoItem(store.tr("Последняя: \(time)", "Last: \(time)")))
        }

        if let error = store.lastError {
            menu.addItem(infoItem(store.tr("Ошибка: \(error)", "Error: \(error)")))
        }

        menu.addItem(.separator())

        if store.isRunning {
            menu.addItem(actionItem(store.tr("Остановить ротацию", "Stop Rotation"), #selector(stopRotation)))
        } else {
            menu.addItem(actionItem(store.tr("Запустить ротацию", "Start Rotation"), #selector(startRotation)))
        }
        menu.addItem(actionItem(store.tr("Сменить сейчас", "Rotate Now"), #selector(rotateNow)))

        menu.addItem(.separator())

        menu.addItem(actionItem(store.tr("Настройки…", "Settings…"), #selector(openAppAction)))
        menu.addItem(actionItem(store.tr("Выйти", "Quit KeyRotator"), #selector(quit)))

        return menu
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Информационная строка: пункт без action автоматически неактивен (серый),
    /// как `Text` в прежнем `MenuBarExtra`.
    private func infoItem(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    @objc private func openAppAction() { openApp() }
    @objc private func startRotation() { rotation.start() }
    @objc private func stopRotation() { rotation.stop() }
    @objc private func rotateNow() { rotation.rotateNow() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Внешний вид

    private func updateAppearance() {
        guard let button = statusItem?.button else { return }
        button.image = icon
        button.toolTip = tooltip
    }

    // 5-часовое окно лимитов активного FreeModel-ключа; nil, если активный
    // ключ не FreeModel или лимиты ещё не загружены (тогда иконка системная).
    private var activeUsageWindow: FreeModelUsage.Window? {
        guard let key = store.currentKey, key.category == .freeModel,
              let usage = store.usageStates[key.id]?.usage else { return nil }
        return usage.window5h
    }

    // Значок меню-бара: обычно системный template (сам подстраивается под
    // светлую/тёмную панель), но при наличии данных лимитов активного
    // FreeModel-ключа (и включённой настройке «Лимиты в меню-баре» —
    // `freeModelMenuBarIcon`) рисуется кастомная иконка: сверху полоска
    // квартильного цвета его 5-часового окна, под ней процент использования.
    private var icon: NSImage {
        if store.freeModelMenuBarIcon, let window = activeUsageWindow {
            return usageIcon(for: window)
        }
        let name = store.isRunning ? "key.fill" : "pause.circle"
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        base.isTemplate = true
        return base
    }

    /// Иконка лимитов: полоска цвета `Window.tint` во всю ширину сверху и
    /// процент заполнения окна под ней. Рисуется через drawingHandler — он
    /// выполняется при каждом отображении, поэтому `labelColor` текста
    /// резолвится под актуальную светлую/тёмную панель без перерисовки вручную.
    private func usageIcon(for window: FreeModelUsage.Window) -> NSImage {
        let text = "\(Int((window.fraction * 100).rounded()))%" as NSString
        // Размер и насыщенность текста — как у крупной цифровой строки соседних
        // индикаторов в меню-баре (нижняя строка «24%» у виджетов вида «CPU 24%»).
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]
        let textSize = text.size(withAttributes: attributes)
        let barHeight: CGFloat = 3
        let gap: CGFloat = 2
        let size = NSSize(width: max(ceil(textSize.width), 18),
                          height: barHeight + gap + ceil(textSize.height))
        let tint = NSColor(window.tint)

        let image = NSImage(size: size, flipped: false) { rect in
            tint.setFill()
            let bar = NSRect(x: 0, y: rect.height - barHeight, width: rect.width, height: barHeight)
            NSBezierPath(roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
            text.draw(at: NSPoint(x: (rect.width - textSize.width) / 2, y: 0),
                      withAttributes: attributes)
            return true
        }
        image.isTemplate = false // иконка цветная, монохромная маска не нужна
        return image
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
