//
//  RootView.swift
//  ClaudeRotate
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label(store.tr("Обзор", "Overview"), systemImage: "rectangle.on.rectangle") }
            KeysView()
                .tabItem { Label(store.tr("Ключи", "Keys"), systemImage: "key") }
            SettingsView()
                .tabItem { Label(store.tr("Настройки", "Settings"), systemImage: "gearshape") }
        }
        .padding()
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
                .contentShape(Rectangle())
                // Use a simultaneous gesture so double-click-to-edit doesn't
                // swallow the List's drag-to-reorder gesture.
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

    @FocusState private var filePathFocused: Bool

    var body: some View {
        Form {
            Section(store.tr("Целевой файл", "Target File")) {
                HStack {
                    TextField("~/.claude/settings.json", text: $store.filePath)
                        .textFieldStyle(.roundedBorder)
                        .focused($filePathFocused)
                        .onChange(of: filePathFocused) { _, focused in
                            if !focused { store.save() }
                        }
                        .onSubmit { store.save() }
                    Button(store.tr("Обзор…", "Browse…")) { browse() }
                }
            }

            Section(store.tr("Ротация", "Rotation")) {
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
            }

            Section(store.tr("Интерфейс", "Interface")) {
                Picker(store.tr("Язык", "Language"), selection: $store.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .onChange(of: store.language) { _, _ in store.save() }
            }

            Section(store.tr("Статус", "Status")) {
                LabeledContent(store.tr("Состояние", "State")) {
                    Text(store.isRunning ? store.tr("Запущена", "Running")
                                         : store.tr("Остановлена", "Stopped"))
                        .foregroundStyle(store.isRunning ? .green : .secondary)
                }
                LabeledContent(store.tr("Активный ключ", "Active key")) {
                    Text(store.currentKeyName ?? "—")
                }
                if let last = store.lastRotation {
                    LabeledContent(store.tr("Последняя смена", "Last rotation")) {
                        Text(last.formatted(date: .abbreviated, time: .standard))
                    }
                }
                if let error = store.lastError {
                    LabeledContent(store.tr("Ошибка", "Error")) {
                        Text(error).foregroundStyle(.red)
                    }
                }

                HStack {
                    if store.isRunning {
                        Button(store.tr("Остановить", "Stop")) { rotation.stop() }
                    } else {
                        Button(store.tr("Запустить", "Start")) { rotation.start() }
                    }
                    Button(store.tr("Сменить сейчас", "Rotate Now")) { rotation.rotateNow() }
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
