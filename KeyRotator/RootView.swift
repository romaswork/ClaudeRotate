//
//  RootView.swift
//  ClaudeRotate
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var tab: Tab = .overview

    enum Tab: Hashable { case overview, keys, proxies, settings }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // Кастомная панель вкладок: на macOS обычный TabView не показывает иконки
    // из `.tabItem`, поэтому рисуем переключатель сами (иконка + подпись).
    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(.overview, store.tr("Обзор", "Overview"), "rectangle.on.rectangle")
            tabButton(.keys, store.tr("Ключи", "Keys"), "key")
            tabButton(.proxies, store.tr("Прокси", "Proxies"), "network")
            tabButton(.settings, store.tr("Настройки", "Settings"), "gearshape")
        }
        .padding(8)
    }

    private func tabButton(_ value: Tab, _ title: String, _ icon: String) -> some View {
        let selected = tab == value
        return Button {
            tab = value
        } label: {
            Label(title, systemImage: icon)
                .font(.callout.weight(selected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor.opacity(0.18) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview: DashboardView()
        case .keys: KeysView()
        case .proxies: ProxiesView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rotation: RotationManager

    // MARK: Derived rotation state

    private var enabled: [APIKey] { store.enabledKeys }

    private var currentIndex: Int? {
        guard let id = store.currentKeyID else { return nil }
        return enabled.firstIndex { $0.id == id }
    }

    private var nextKey: APIKey? {
        guard !enabled.isEmpty else { return nil }
        if let idx = currentIndex { return enabled[(idx + 1) % enabled.count] }
        return enabled.first
    }

    private var previousKey: APIKey? {
        guard !enabled.isEmpty else { return nil }
        if let idx = currentIndex {
            return enabled[(idx - 1 + enabled.count) % enabled.count]
        }
        return enabled.last
    }

    private var nextRotationDate: Date? {
        guard store.isRunning, let last = store.lastRotation else { return nil }
        return last.addingTimeInterval(Double(store.intervalMinutes) * 60)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !store.hasTargetFile {
                    noFileBanner
                }
                statusBanner
                currentKeyCard
                HStack(spacing: 14) {
                    previousKeyCard
                    nextKeyCard
                }
                if let error = store.lastError {
                    errorBanner(error)
                }
                controls
            }
            .padding(18)
        }
    }

    // MARK: No-file banner

    // Shown when no target file is selected. Under App Sandbox the file must be
    // picked manually (e.g. after upgrading from a non-sandboxed version), so make
    // the requirement obvious right on the dashboard.
    private var noFileBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.tr("Целевой файл не выбран", "No target file selected"))
                    .font(.headline)
                Text(store.tr("Откройте «Настройки» и выберите файл settings.json — без него ротация не сможет записывать ключи.",
                              "Open Settings and choose your settings.json — rotation can't write keys without it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Status banner

    private var statusBanner: some View {
        let running = store.isRunning
        return HStack(spacing: 12) {
            Image(systemName: running ? "arrow.triangle.2.circlepath" : "pause.circle.fill")
                .font(.title2)
                .foregroundStyle(running ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(running ? store.tr("Ротация активна", "Rotation active")
                             : store.tr("Ротация остановлена", "Rotation stopped"))
                    .font(.headline)
                Text(running
                     ? store.tr("Смена каждые \(store.intervalMinutes) мин · \(enabled.count) из \(store.keys.count) включено",
                                "Every \(store.intervalMinutes) min · \(enabled.count) of \(store.keys.count) enabled")
                     : store.tr("\(enabled.count) из \(store.keys.count) ключей включено",
                                "\(enabled.count) of \(store.keys.count) keys enabled"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let next = nextRotationDate {
                VStack(alignment: .trailing, spacing: 1) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = next.timeIntervalSince(context.date)
                        Text(formatRemaining(remaining))
                            .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    Text(store.tr("до смены", "until switch"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                if running { rotation.stop() } else { rotation.start() }
            } label: {
                Label(running ? store.tr("Остановить", "Stop") : store.tr("Запустить", "Start"),
                      systemImage: running ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(running ? .red : .green)
            .disabled(!running && enabled.isEmpty)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background((running ? Color.green : Color.secondary).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Current key card

    private var currentKeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.tint)
                Text(store.tr("Текущий ключ", "Current key"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let idx = currentIndex {
                    Text("\(idx + 1) / \(enabled.count)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }

            if let key = store.currentKey {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(key.name.isEmpty ? store.tr("Без названия", "Untitled") : key.name)
                        .font(.title.weight(.bold))
                    testIndicator(for: key)
                }

                infoRow(icon: "lock.fill", label: masked(key.apiKey))
                infoRow(icon: "link", label: key.baseURL.isEmpty ? store.tr("Base URL по умолчанию", "Default base URL") : key.baseURL)
                if let proxy = store.proxy(for: key) {
                    infoRow(icon: "network", label: proxy.displayName)
                }
                if let last = store.lastRotation {
                    infoRow(icon: "clock.arrow.circlepath",
                            label: store.tr("Применён в \(last.formatted(date: .omitted, time: .standard))",
                                            "Applied at \(last.formatted(date: .omitted, time: .standard))"))
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.tr("Активный ключ не выбран", "No active key"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(store.tr("Запустите ротацию или выберите ключ вручную на вкладке «Ключи».",
                                  "Start rotation or pick a key manually on the Keys tab."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Previous key card

    private var previousKeyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.tr("Предыдущий ключ", "Previous key"), systemImage: "arrow.left.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let prev = previousKey {
                Text(prev.name.isEmpty ? store.tr("Без названия", "Untitled") : prev.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(prev.baseURL.isEmpty ? store.tr("Base URL по умолчанию", "Default base URL") : prev.baseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("—")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(store.tr("Нет включённых ключей", "No enabled keys"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Next key card

    private var nextKeyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(store.tr("Следующий ключ", "Next key"), systemImage: "arrow.right.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let next = nextKey {
                Text(next.name.isEmpty ? store.tr("Без названия", "Untitled") : next.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(next.baseURL.isEmpty ? store.tr("Base URL по умолчанию", "Default base URL") : next.baseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("—")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(store.tr("Нет включённых ключей", "No enabled keys"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                rotation.rotatePrevious()
            } label: {
                Label(store.tr("Предыдущий", "Previous"), systemImage: "backward.fill")
                    .frame(maxWidth: .infinity)
            }
            .disabled(enabled.isEmpty)

            Button {
                rotation.rotateNow()
            } label: {
                Label(store.tr("Следующий", "Next"), systemImage: "forward.fill")
                    .frame(maxWidth: .infinity)
            }
            .disabled(enabled.isEmpty)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
    }

    // MARK: Helpers

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private func infoRow(icon: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func testIndicator(for key: APIKey) -> some View {
        switch store.testStates[key.id] {
        case .testing:
            ProgressView().controlSize(.small)
        case .success:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .help(store.tr("Ключ валиден", "Key is valid"))
        case .failure(let message):
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .help(message)
        case nil:
            EmptyView()
        }
    }

    private func masked(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 12 else {
            return String(repeating: "•", count: max(trimmed.count, 4))
        }
        return "\(trimmed.prefix(8))…\(trimmed.suffix(4))"
    }

    private func formatRemaining(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
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
            Text(store.tr("Нет ключей", "No API Keys"))
                .font(.title3.weight(.semibold))
            Text(store.tr("Добавьте ключ, чтобы начать ротацию.",
                          "Add a key to start rotating credentials."))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                presentNew()
            } label: {
                Label(store.tr("Добавить ключ", "Add Key"), systemImage: "plus")
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
                .simultaneousGesture(TapGesture(count: 2).onEnded { presentEdit(key) })
                .contextMenu {
                    Button(store.tr("Проверить", "Test")) { store.test(key) }
                    Button(store.tr("Сделать активным", "Set as Active Now")) { rotation.apply(key) }
                        .disabled(store.currentKeyID == key.id)
                    Divider()
                    Button(store.tr("Изменить", "Edit")) { presentEdit(key) }
                    Button(store.tr("Удалить", "Delete"), role: .destructive) { store.deleteKey(key) }
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
            .help(store.tr("Добавить ключ", "Add key"))

            Button {
                if let id = selection, let key = store.keys.first(where: { $0.id == id }) {
                    store.deleteKey(key)
                    selection = nil
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 22)
            }
            .help(store.tr("Удалить выбранный ключ", "Remove selected key"))
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
            .help(store.tr("Изменить выбранный ключ", "Edit selected key"))
            .disabled(selection == nil)

            Button {
                if let id = selection, let key = store.keys.first(where: { $0.id == id }) {
                    rotation.apply(key)
                }
            } label: {
                Image(systemName: "checkmark.circle")
                    .frame(width: 24, height: 22)
            }
            .help(store.tr("Сделать выбранный ключ активным", "Set selected key as active now"))
            .disabled(selection == nil || selection == store.currentKeyID)

            Divider().frame(height: 16)

            Button {
                store.testAll()
            } label: {
                Image(systemName: "checkmark.shield")
                    .frame(width: 24, height: 22)
            }
            .help(store.tr("Проверить все ключи", "Test all keys"))
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
    @EnvironmentObject private var store: AppStore
    @Binding var key: APIKey
    let isActive: Bool
    let testState: KeyTestState?
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.body)
                .foregroundStyle(.tertiary)
                .help(store.tr("Перетащите, чтобы изменить порядок", "Drag to reorder"))
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                Text(key.name.isEmpty ? store.tr("Без названия", "Untitled") : key.name)
                    .fontWeight(.medium)
                Text(key.baseURL.isEmpty ? store.tr("Нет base URL", "No base URL") : key.baseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let proxy = store.assignedProxy(for: key) {
                proxyChip(proxy)
            }
            testIndicator
            if isActive {
                Text(store.tr("Активен", "Active"))
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

    // Бейдж с названием привязанного прокси. Когда прокси отключены глобально,
    // показывается приглушённо с подсказкой, что он не применяется.
    private func proxyChip(_ proxy: Proxy) -> some View {
        let active = store.proxiesEnabled
        return Label(proxy.displayName, systemImage: "network")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(active ? Color.secondary : Color.secondary.opacity(0.5))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.secondary.opacity(active ? 0.15 : 0.08), in: Capsule())
            .help(active
                  ? store.tr("Прокси: \(proxy.displayName)", "Proxy: \(proxy.displayName)")
                  : store.tr("Прокси отключены глобально в настройках", "Proxies are disabled globally in Settings"))
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
                .help(store.tr("Валиден", "Valid"))
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
    @EnvironmentObject private var store: AppStore
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
            Text(isNew ? store.tr("Новый ключ", "New Key") : store.tr("Изменить ключ", "Edit Key"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

            Form {
                Section {
                    TextField(store.tr("Название", "Name"), text: $draft.name,
                              prompt: Text(store.tr("напр. Личный", "e.g. Personal")))
                } footer: {
                    Text(store.tr("Метка для распознавания ключа. В файл не записывается.",
                                  "A label to recognize this key. Not written to the file."))
                }

                Section {
                    TextField("API Key", text: $draft.apiKey, prompt: Text("sk-ant-…"))
                        .font(.system(.body, design: .monospaced))
                    TextField("Base URL", text: $draft.baseURL, prompt: Text("https://api.anthropic.com"))
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text(store.tr("Учётные данные", "Credentials"))
                } footer: {
                    Text(store.tr("Записывается в ANTHROPIC_API_KEY / ANTHROPIC_BASE_URL при ротации.",
                                  "Written to ANTHROPIC_API_KEY / ANTHROPIC_BASE_URL on rotation."))
                }

                Section {
                    Picker(store.tr("Прокси", "Proxy"), selection: $draft.proxyID) {
                        Text(store.tr("Без прокси", "No proxy")).tag(UUID?.none)
                        ForEach(store.proxies) { proxy in
                            Text(proxy.displayName).tag(UUID?.some(proxy.id))
                        }
                    }
                } header: {
                    Text(store.tr("Прокси", "Proxy"))
                } footer: {
                    Text(store.tr("Если назначен, его URL пишется в HTTPS_PROXY / HTTP_PROXY при ротации этого ключа.",
                                  "If assigned, its URL is written to HTTPS_PROXY / HTTP_PROXY when this key is rotated in."))
                }

                Section {
                    Toggle(store.tr("Участвует в ротации", "Include in rotation"), isOn: $draft.enabled)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 10) {
                Button(store.tr("Проверить", "Test")) { runTest() }
                    .disabled(!canTest)
                testStatusView
                Spacer()
                Button(store.tr("Отмена", "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(store.tr("Сохранить", "Save")) {
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
                Text(store.tr("Проверка…", "Testing…")).foregroundStyle(.secondary)
            }
            .font(.callout)
        case .success:
            Label(store.tr("Валиден", "Valid"), systemImage: "checkmark.circle.fill")
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

    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: store.hasTargetFile ? "doc.text.fill" : "doc.text")
                        .foregroundStyle(store.hasTargetFile ? .green : .secondary)
                    Text(store.filePath.isEmpty
                         ? store.tr("Файл не выбран", "No file selected")
                         : store.filePath)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(store.filePath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    Button(store.tr("Выбрать…", "Choose…")) { browse() }
                }
            } header: {
                Label(store.tr("Целевой файл", "Target File"), systemImage: "doc.text")
            } footer: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.tr("Выберите файл settings.json. Доступ к нему сохраняется между запусками.",
                                  "Pick your settings.json. Access to it is preserved across launches."))
                    Text(store.tr("Обычно файл настроек Claude Code лежит здесь: \(defaultSettingsURL.path)",
                                  "Claude Code usually keeps its settings here: \(defaultSettingsURL.path)"))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section {
                HStack {
                    Text(store.tr("Интервал (минуты)", "Interval (minutes)"))
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

                Toggle(store.tr("Запускать ротацию при старте", "Start rotation on launch"),
                       isOn: $store.startOnLaunch)
                    .onChange(of: store.startOnLaunch) { _, _ in store.save() }
            } header: {
                Label(store.tr("Ротация", "Rotation"), systemImage: "arrow.triangle.2.circlepath")
            }

            Section {
                Toggle(store.tr("Использовать прокси", "Use proxies"),
                       isOn: $store.proxiesEnabled)
                    .onChange(of: store.proxiesEnabled) { _, _ in
                        store.save()
                        // Перезаписываем текущий ключ, чтобы переменные прокси в
                        // целевом файле сразу отразили новое состояние.
                        if let key = store.currentKey {
                            rotation.apply(key)
                        }
                    }
            } header: {
                Label(store.tr("Прокси", "Proxies"), systemImage: "network")
            } footer: {
                Text(store.tr("Глобально включает или выключает применение прокси при ротации. Привязки прокси к ключам сохраняются. Когда выключено, переменные HTTPS_PROXY/HTTP_PROXY удаляются из целевого файла.",
                              "Globally enables or disables proxy usage during rotation. Per-key proxy assignments are kept. When off, HTTPS_PROXY/HTTP_PROXY are removed from the target file."))
            }

            Section {
                Picker(store.tr("Язык", "Language"), selection: $store.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .onChange(of: store.language) { _, _ in store.save() }
            } header: {
                Label(store.tr("Интерфейс", "Interface"), systemImage: "globe")
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        exportSettings()
                    } label: {
                        Label(store.tr("Экспорт…", "Export…"), systemImage: "square.and.arrow.up")
                    }
                    Button {
                        importSettings()
                    } label: {
                        Label(store.tr("Импорт…", "Import…"), systemImage: "square.and.arrow.down")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label(store.tr("Сбросить всё…", "Reset all…"), systemImage: "trash")
                    }
                }
            } header: {
                Label(store.tr("Данные", "Data"), systemImage: "externaldrive")
            } footer: {
                Text(store.tr("Экспорт сохраняет ключи, прокси и настройки в файл. Выбранный целевой файл не переносится. Сброс удаляет все ключи, прокси и настройки (сам settings.json не трогается).",
                              "Export saves keys, proxies and settings to a file. The selected target file is not included. Reset removes all keys, proxies and settings (your settings.json is left untouched)."))
            }
        }
        .formStyle(.grouped)
        .alert(store.tr("Сбросить все настройки?", "Reset all settings?"), isPresented: $showResetConfirm) {
            Button(store.tr("Отмена", "Cancel"), role: .cancel) { }
            Button(store.tr("Сбросить", "Reset"), role: .destructive) {
                rotation.stop()
                store.resetAll()
            }
        } message: {
            Text(store.tr("Все ключи, прокси и настройки будут удалены без возможности восстановления. Целевой файл settings.json не изменится.",
                          "All keys, proxies and settings will be permanently deleted. Your target settings.json won't be changed."))
        }
    }

    private func exportSettings() {
        guard let data = store.exportData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ClaudeRotate-settings.json"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
            } catch {
                store.lastError = error.localizedDescription
            }
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                rotation.stop()
                store.importData(data)
            } catch {
                store.lastError = error.localizedDescription
            }
        }
    }

    /// Real home directory of the current user. Under App Sandbox `~` /
    /// `NSHomeDirectory()` point inside the app container, so resolve the actual
    /// home via the password database instead.
    private var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Typical location of the Claude Code settings file for the current user.
    private var defaultSettingsURL: URL {
        realHomeDirectory.appendingPathComponent(".claude/settings.json")
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        // `.claude` is a hidden folder — make it visible and pre-navigate the panel
        // to the default settings file so the user only has to confirm. The sandbox
        // still requires this explicit confirmation to grant access.
        panel.showsHiddenFiles = true
        let def = defaultSettingsURL
        if FileManager.default.fileExists(atPath: def.path) {
            panel.directoryURL = def.deletingLastPathComponent()
            panel.nameFieldStringValue = def.lastPathComponent
        } else {
            panel.directoryURL = realHomeDirectory
        }
        if panel.runModal() == .OK, let url = panel.url {
            store.setTargetFile(url)
        }
    }
}

// MARK: - Proxies

struct ProxiesView: View {
    @EnvironmentObject private var store: AppStore

    @State private var editorProxy: Proxy?
    @State private var editorIsNew = false
    @State private var selection: Proxy.ID?

    var body: some View {
        VStack(spacing: 0) {
            if store.proxies.isEmpty {
                emptyState
            } else {
                proxyList
            }
            Divider()
            bottomBar
        }
        .sheet(item: $editorProxy) { proxy in
            ProxyEditor(proxy: proxy, isNew: editorIsNew) { edited in
                if editorIsNew {
                    store.proxies.append(edited)
                    store.save()
                } else {
                    store.updateProxy(edited)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(store.tr("Нет прокси", "No Proxies"))
                .font(.title3.weight(.semibold))
            Text(store.tr("Добавьте прокси, чтобы привязывать его к ключам.",
                          "Add a proxy to assign it to your keys."))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                presentNew()
            } label: {
                Label(store.tr("Добавить прокси", "Add Proxy"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var proxyList: some View {
        List(selection: $selection) {
            ForEach($store.proxies) { $proxy in
                ProxyRow(proxy: $proxy,
                         usageCount: usageCount(of: proxy.id),
                         testState: store.proxyTestStates[proxy.id])
                    .tag(proxy.id)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { presentEdit(proxy) })
                    .contextMenu {
                        Button(store.tr("Проверить", "Test")) { store.testProxy(proxy) }
                        Divider()
                        Button(store.tr("Изменить", "Edit")) { presentEdit(proxy) }
                        Button(store.tr("Удалить", "Delete"), role: .destructive) { store.deleteProxy(proxy) }
                    }
            }
            .onMove { store.moveProxy(from: $0, to: $1) }
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
            .help(store.tr("Добавить прокси", "Add proxy"))

            Button {
                if let id = selection, let proxy = store.proxies.first(where: { $0.id == id }) {
                    store.deleteProxy(proxy)
                    selection = nil
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 22)
            }
            .help(store.tr("Удалить выбранный прокси", "Remove selected proxy"))
            .disabled(selection == nil)

            Divider().frame(height: 16)

            Button {
                if let id = selection, let proxy = store.proxies.first(where: { $0.id == id }) {
                    presentEdit(proxy)
                }
            } label: {
                Image(systemName: "pencil")
                    .frame(width: 24, height: 22)
            }
            .help(store.tr("Изменить выбранный прокси", "Edit selected proxy"))
            .disabled(selection == nil)

            Button {
                if let id = selection, let proxy = store.proxies.first(where: { $0.id == id }) {
                    store.testProxy(proxy)
                }
            } label: {
                Image(systemName: "checkmark.shield")
                    .frame(width: 24, height: 22)
            }
            .help(store.tr("Проверить выбранный прокси", "Test selected proxy"))
            .disabled(selection == nil)

            Divider().frame(height: 16)

            Button {
                store.testAllProxies()
            } label: {
                Image(systemName: "checkmark.shield.fill")
                    .frame(width: 24, height: 22)
            }
            .help(store.tr("Проверить все прокси", "Test all proxies"))
            .disabled(store.proxies.isEmpty)

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func usageCount(of id: UUID) -> Int {
        store.keys.filter { $0.proxyID == id }.count
    }

    private func presentNew() {
        editorIsNew = true
        editorProxy = Proxy()
    }

    private func presentEdit(_ proxy: Proxy) {
        editorIsNew = false
        editorProxy = proxy
    }
}

struct ProxyRow: View {
    @EnvironmentObject private var store: AppStore
    @Binding var proxy: Proxy
    let usageCount: Int
    let testState: ProxyTestState?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.body)
                .foregroundStyle(.tertiary)
                .help(store.tr("Перетащите, чтобы изменить порядок", "Drag to reorder"))
            Image(systemName: "network")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(proxy.name.isEmpty ? store.tr("Без названия", "Untitled") : proxy.name)
                    .fontWeight(.medium)
                Text(endpoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            testIndicator
            if !proxy.username.trimmingCharacters(in: .whitespaces).isEmpty {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(store.tr("С авторизацией", "With authentication"))
            }
            if usageCount > 0 {
                Text(store.tr("\(usageCount) ключ.", "\(usageCount) key(s)"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private var endpoint: String {
        let h = proxy.host.trimmingCharacters(in: .whitespaces)
        let p = proxy.port.trimmingCharacters(in: .whitespaces)
        if h.isEmpty { return store.tr("Не задан хост", "No host") }
        return p.isEmpty ? h : "\(h):\(p)"
    }

    @ViewBuilder
    private var testIndicator: some View {
        switch testState {
        case .testing:
            ProgressView()
                .controlSize(.small)
        case .success(let check):
            HStack(spacing: 6) {
                if let flag = check.flag {
                    Text(flag)
                        .help(check.countryName ?? check.countryCode ?? "")
                }
                Text("\(check.latencyMs) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(latencyColor(check.latencyMs))
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help(store.tr("Доступен", "Reachable"))
            }
        case .failure(let message):
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .help(message)
        case nil:
            EmptyView()
        }
    }

    private func latencyColor(_ ms: Int) -> Color {
        switch ms {
        case ..<300: return .green
        case ..<800: return .orange
        default: return .red
        }
    }
}

// MARK: - Proxy Editor

struct ProxyEditor: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Proxy
    @State private var testState: ProxyTestState?
    let isNew: Bool
    let onSave: (Proxy) -> Void

    init(proxy: Proxy, isNew: Bool, onSave: @escaping (Proxy) -> Void) {
        _draft = State(initialValue: proxy)
        self.isNew = isNew
        self.onSave = onSave
    }

    private var isValid: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !draft.host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canTest: Bool {
        !draft.host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func runTest() {
        testState = .testing
        let proxy = draft
        Task {
            let result = await testProxy(proxy)
            switch result {
            case .ok(let check): testState = .success(check)
            case .authFailed:
                testState = .failure(store.tr("Ошибка авторизации (407)", "Auth failed (407)"))
            case .httpError(let code): testState = .failure("HTTP \(code)")
            case .error(let message): testState = .failure(message)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? store.tr("Новый прокси", "New Proxy") : store.tr("Изменить прокси", "Edit Proxy"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

            Form {
                Section {
                    TextField(store.tr("Название", "Name"), text: $draft.name,
                              prompt: Text(store.tr("напр. Домашний", "e.g. Home")))
                } footer: {
                    Text(store.tr("Метка для распознавания прокси.",
                                  "A label to recognize this proxy."))
                }

                Section {
                    TextField(store.tr("Хост", "Host"), text: $draft.host,
                              prompt: Text("127.0.0.1"))
                        .font(.system(.body, design: .monospaced))
                    TextField(store.tr("Порт", "Port"), text: $draft.port,
                              prompt: Text("8080"))
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text(store.tr("Адрес", "Endpoint"))
                }

                Section {
                    TextField(store.tr("Логин", "Username"), text: $draft.username)
                    SecureField(store.tr("Пароль", "Password"), text: $draft.password)
                } header: {
                    Text(store.tr("Авторизация (необязательно)", "Authentication (optional)"))
                } footer: {
                    Text(store.tr("Оставьте пустым для прокси без авторизации.",
                                  "Leave empty for a proxy without authentication."))
                }

                if let url = draft.url {
                    Section {
                        Text(maskedURL(url))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } header: {
                        Text(store.tr("Итоговый URL", "Resulting URL"))
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 10) {
                Button(store.tr("Проверить", "Test")) { runTest() }
                    .disabled(!canTest)
                testStatusView
                Spacer()
                Button(store.tr("Отмена", "Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(store.tr("Сохранить", "Save")) {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 440, height: 470)
    }

    @ViewBuilder
    private var testStatusView: some View {
        switch testState {
        case .testing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(store.tr("Проверка…", "Testing…")).foregroundStyle(.secondary)
            }
            .font(.callout)
        case .success(let check):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(successSummary(check))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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

    private func successSummary(_ check: ProxyCheck) -> String {
        var parts: [String] = [store.tr("Доступен", "Reachable"), "\(check.latencyMs) \(store.tr("мс", "ms"))"]
        let country = [check.flag, check.countryName ?? check.countryCode]
            .compactMap { $0 }
            .joined(separator: " ")
        if !country.isEmpty { parts.append(country) }
        return parts.joined(separator: " · ")
    }

    /// Маскирует пароль в превью URL, чтобы он не отображался открытым текстом.
    private func maskedURL(_ url: String) -> String {
        let pass = draft.password.trimmingCharacters(in: .whitespaces)
        guard !pass.isEmpty,
              let encPass = pass.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) else {
            return url
        }
        return url.replacingOccurrences(of: ":\(encPass)@", with: ":••••@")
    }
}
