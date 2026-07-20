//
//  RootView.swift
//  ClaudeRotate
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var tab: Tab? = .overview
    // Раскрыта ли ветка «Ключи» (с подменю FreeModel) в боковой панели.
    @State private var keysExpanded = true

    enum Tab: Hashable, CaseIterable, Identifiable {
        case overview, keys, freeModel, proxies, settings
        var id: Self { self }

        var icon: String {
            switch self {
            case .overview: return "rectangle.on.rectangle"
            case .keys: return "key"
            case .freeModel: return "sparkles"
            case .proxies: return "network"
            case .settings: return "gearshape"
            }
        }

        func title(_ store: AppStore) -> String {
            switch self {
            case .overview: return store.tr("Обзор", "Overview")
            case .keys: return store.tr("Ключи", "Keys")
            case .freeModel: return "FreeModel"
            case .proxies: return store.tr("Прокси", "Proxies")
            case .settings: return store.tr("Настройки", "Settings")
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            // «FreeModel» — подменю пункта «Ключи»: раскрывающаяся ветка с
            // отдельной категорией ключей. Сам пункт «Ключи» остаётся кликабельным
            // и открывает обычные ключи.
            List(selection: $tab) {
                sidebarRow(.overview)
                DisclosureGroup(isExpanded: $keysExpanded) {
                    sidebarRow(.freeModel)
                } label: {
                    sidebarRow(.keys)
                }
                sidebarRow(.proxies)
                sidebarRow(.settings)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 220)
            // Логотип-бренд в шапке боковой панели — всегда виден (нативный паттрен
            // macOS), реальная иконка приложения берётся из `NSApp.applicationIconImage`,
            // поэтому логотип всегда совпадает с иконкой в Dock и App Store.
            .safeAreaInset(edge: .top, spacing: 6) {
                sidebarBrand
            }
        } detail: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle((tab ?? .overview).title(store))
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func sidebarRow(_ item: Tab) -> some View {
        Label(item.title(store), systemImage: item.icon)
            .tag(item)
    }

    // Шапка боковой панели с логотипом и названием приложения.
    private var sidebarBrand: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text("KeyRotator")
                        .font(.headline)
                        .lineLimit(1)
                    Text(store.tr("Ротация ключей", "Key rotation"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
            Divider()
        }
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        switch tab ?? .overview {
        case .overview: DashboardView(tab: $tab)
        case .keys: KeysView(category: .general)
        case .freeModel: KeysView(category: .freeModel)
        case .proxies: ProxiesView()
        case .settings: SettingsView()
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rotation: RotationManager
    @Binding var tab: RootView.Tab?

    // MARK: Derived rotation state

    private var enabled: [APIKey] { store.enabledKeys }

    private var currentIndex: Int? {
        guard let id = store.currentKeyID else { return nil }
        return enabled.firstIndex { $0.id == id }
    }

    private var nextRotationDate: Date? {
        guard store.isRunning, let last = store.lastRotation else { return nil }
        return last.addingTimeInterval(Double(store.intervalMinutes) * 60)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !store.hasAnyActiveTarget {
                    noFileBanner
                }
                heroCard
                if let key = store.currentKey, key.category == .freeModel {
                    usageCard(for: key)
                }
                statsGrid
                if let error = store.lastError {
                    errorBanner(error)
                }
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
                Text(store.tr("Нет активного целевого файла", "No active target file"))
                    .font(.headline)
                Text(store.tr("Откройте «Настройки», выберите и включите хотя бы один целевой файл — без него ротация не сможет записывать ключи.",
                              "Open Settings, choose and enable at least one target file — rotation can't write keys without it."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .dashboardCard(padding: 14, tint: .orange)
    }

    // MARK: Hero card (countdown + current key + controls)

    // Главный блок: слева крупное кольцо обратного отсчёта, справа — карточка
    // текущего ключа, снизу — единая группа управления ротацией
    // (Предыдущий · Старт/Стоп · Следующий).
    private var heroCard: some View {
        let running = store.isRunning
        return VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                countdownRing(running: running)
                keyDetails
                Spacer(minLength: 0)
            }
            controlGroup(running: running)
        }
        .dashboardCard(tint: running ? .green : nil)
    }

    // Детали текущего ключа (или приглашение выбрать ключ).
    @ViewBuilder
    private var keyDetails: some View {
        if let key = store.currentKey {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(key.name.isEmpty ? store.tr("Без названия", "Untitled") : key.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    testIndicator(for: key)
                    if let idx = currentIndex {
                        Text("\(idx + 1) / \(enabled.count)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                    statusBadge(running: store.isRunning)
                }
                infoRow(icon: "lock.fill", label: masked(key.apiKey))
                let effectiveBase = store.effectiveBaseURL(for: key)
                infoRow(icon: "link", label: effectiveBase.isEmpty
                        ? store.tr("Base URL по умолчанию", "Default base URL") : effectiveBase)
                if let proxy = store.proxy(for: key) {
                    infoRow(icon: "network", label: proxy.displayName)
                }
                if let last = store.lastRotation {
                    infoRow(icon: "checkmark.circle",
                            label: store.tr("Применён в \(last.formatted(date: .omitted, time: .standard))",
                                            "Applied at \(last.formatted(date: .omitted, time: .standard))"))
                }
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // Капсула состояния ротации рядом с именем ключа.
    private func statusBadge(running: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(running ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(running ? store.tr("активна", "active")
                         : store.tr("остановлена", "stopped"))
        }
        .tagChip(tint: running ? .green : .secondary,
                 opacity: running ? 0.18 : 0.12)
    }

    // Круговой индикатор обратного отсчёта до следующей смены. Заполняется по мере
    // приближения смены; когда ротация остановлена или время старта неизвестно —
    // показывает статическую иконку вместо прогресса.
    @ViewBuilder
    private func countdownRing(running: Bool) -> some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 7)
            if let next = nextRotationDate {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, next.timeIntervalSince(context.date))
                    let total = max(1, Double(store.intervalMinutes) * 60)
                    let progress = min(1, max(0, 1 - remaining / total))
                    ZStack {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.green,
                                    style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 1) {
                            Text(formatRemaining(remaining))
                                .font(.system(.title3, design: .rounded)
                                    .weight(.semibold).monospacedDigit())
                            Text(store.tr("осталось", "left"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Image(systemName: running ? "arrow.triangle.2.circlepath" : "pause.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 104, height: 104)
    }

    // MARK: Control group (previous · start/stop · next)

    // Единая лаконичная группа управления: компактные иконочные «Предыдущий» и
    // «Следующий» по краям, растянутая основная кнопка Запустить/Остановить в центре.
    private func controlGroup(running: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                rotation.rotatePrevious()
            } label: {
                Image(systemName: "backward.fill")
            }
            .help(store.tr("Предыдущий", "Previous"))
            .disabled(enabled.isEmpty)

            Button {
                if running { rotation.stop() } else { rotation.start() }
            } label: {
                Label(running ? store.tr("Остановить", "Stop") : store.tr("Запустить", "Start"),
                      systemImage: running ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(running ? .red : .green)
            .disabled(!running && enabled.isEmpty)

            Button {
                rotation.rotateNow()
            } label: {
                Image(systemName: "forward.fill")
            }
            .help(store.tr("Следующий", "Next"))
            .disabled(enabled.isEmpty)
        }
        .controlSize(.large)
        .buttonStyle(.bordered)
    }

    // MARK: FreeModel usage card

    // Карточка лимитов аккаунта FreeModel активного ключа — показывается только
    // когда активный ключ категории FreeModel. Два крупных индикатора окон
    // (5 ч / 7 дн): процент, растянутая полоса прогресса квартильного цвета
    // (Window.tint), суммы и обратный отсчёт до сброса (тикает раз в минуту
    // через TimelineView). В заголовке — время обновления и кнопка ручного
    // обновления; цветовой акцент карточки — по более заполненному окну.
    @ViewBuilder
    private func usageCard(for key: APIKey) -> some View {
        let state = store.usageStates[key.id]
        VStack(alignment: .leading, spacing: 12) {
            usageCardHeader(for: key, state: state)
            switch state {
            case .loaded(let usage, let fetchedAt):
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack(alignment: .top, spacing: 20) {
                        usageCardGauge(store.tr("Окно 5 часов", "5-hour window"),
                                       usage.window5h, fetchedAt: fetchedAt, now: context.date)
                        Divider()
                        usageCardGauge(store.tr("Окно 7 дней", "7-day window"),
                                       usage.windowWeek, fetchedAt: fetchedAt, now: context.date)
                    }
                }
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(store.tr("Загрузка лимитов…", "Loading limits…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .failure(let message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(store.tr("Лимиты недоступны", "Limits unavailable"))
                        .font(.callout)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .help(message)
            case nil:
                Text(hasUsageToken(key)
                     ? store.tr("Лимиты ещё не загружены — нажмите «Обновить».",
                                "Limits not loaded yet — press “Refresh”.")
                     : store.tr("Нет токена сессии — вставьте cookie bm_session с freemodel.dev в поле «Токен сессии» редактора ключа.",
                                "No session token — paste the bm_session cookie from freemodel.dev into the “Session token” field of the key editor."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .dashboardCard(tint: usageCardTint(state))
    }

    private func usageCardHeader(for key: APIKey, state: FreeModelUsageState?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.needle")
                .font(.title3)
                .foregroundStyle(usageCardTint(state) ?? .secondary)
            Text(store.tr("Лимиты FreeModel", "FreeModel limits"))
                .font(.headline)
            if case .loaded(_, let fetchedAt) = state {
                Text(store.tr("обновлено в \(fetchedAt.formatted(date: .omitted, time: .shortened))",
                              "updated at \(fetchedAt.formatted(date: .omitted, time: .shortened))"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                tab = .freeModel
            } label: {
                Image(systemName: "list.bullet")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(store.tr("Открыть раздел FreeModel", "Open the FreeModel section"))
            Button {
                store.refreshUsage(for: key)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(!hasUsageToken(key) || state == .loading)
            .help(store.tr("Обновить лимиты", "Refresh limits"))
        }
    }

    // Крупный индикатор одного окна лимитов: заголовок с процентом, полоса
    // прогресса во всю ширину колонки, суммы и обратный отсчёт до сброса.
    // Детали (точная дата сброса, время обновления) — в тултипе.
    private func usageCardGauge(_ label: String, _ window: FreeModelUsage.Window,
                                fetchedAt: Date, now: Date) -> some View {
        let fraction = window.fraction
        let color = window.tint
        let percent = Int((fraction * 100).rounded())
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(percent)%")
                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                Capsule()
                    .fill(color.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color.gradient)
                            .frame(width: max(4, geo.size.width * fraction))
                    }
            }
            .frame(height: 8)
            HStack {
                Text("\(usageMoney(window.usedCents)) / \(usageMoney(window.limitCents))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(store.tr("сброс \(usageResetCountdown(window.resetDate, now: now, store: store))",
                                  "resets \(usageResetCountdown(window.resetDate, now: now, store: store))"))
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .help(usageWindowTooltip(label, window, fetchedAt: fetchedAt, store: store))
    }

    // Акцент карточки — цвет более заполненного из двух окон; при ошибке
    // загрузки — оранжевый, пока данных нет — без акцента.
    private func usageCardTint(_ state: FreeModelUsageState?) -> Color? {
        switch state {
        case .loaded(let usage, _):
            return (usage.window5h.fraction >= usage.windowWeek.fraction
                    ? usage.window5h : usage.windowWeek).tint
        case .failure:
            return .orange
        default:
            return nil
        }
    }

    private func hasUsageToken(_ key: APIKey) -> Bool {
        !(key.usageToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Stats grid

    // Ряд компактных плиток со сводкой: включённые ключи, интервал, прокси и
    // время следующей смены — вся ключевая статистика с первого взгляда.
    private var statsGrid: some View {
        HStack(spacing: 12) {
            statTile(icon: "key.fill",
                     value: "\(enabled.count) / \(store.keys.count)",
                     label: store.tr("включено", "enabled"),
                     tint: .accentColor,
                     destination: .keys)
            statTile(icon: "timer",
                     value: store.tr("\(store.intervalMinutes) мин", "\(store.intervalMinutes) min"),
                     label: store.tr("интервал", "interval"),
                     tint: .blue,
                     destination: .settings)
            statTile(icon: store.proxiesEnabled ? "network" : "network.slash",
                     value: "\(store.proxies.count)",
                     label: store.proxiesEnabled ? store.tr("прокси", "proxies")
                                                 : store.tr("выключены", "off"),
                     tint: store.proxiesEnabled ? .purple : .secondary,
                     destination: .proxies)
            statTile(icon: "clock.arrow.circlepath",
                     value: nextRotationText,
                     label: store.tr("след. смена", "next"),
                     tint: store.isRunning ? .green : .secondary,
                     destination: .settings)
        }
    }

    private func statTile(icon: String, value: String, label: String, tint: Color, destination: RootView.Tab) -> some View {
        Button {
            tab = destination
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                Text(value)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .dashboardCard(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private var nextRotationText: String {
        guard let next = nextRotationDate else { return "—" }
        return next.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Helpers

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .dashboardCard(padding: 12, tint: .red)
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

// MARK: - Reusable list UI

/// Иконочная кнопка нижнего тулбара списков — единый размер и стиль, чтобы не
/// дублировать `Image(...).frame(...)` + `.help` + `.disabled` в каждой вкладке.
private struct ToolbarIconButton: View {
    let systemName: String
    let help: String
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 24, height: 22)
        }
        .help(help)
        .disabled(disabled)
    }
}

/// Поле поиска над списком (ключей/прокси) с кнопкой очистки.
private struct ListSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }
}

private extension View {
    /// Единый стиль бейджа-капсулы (активность, счётчики, прокси).
    func tagChip(tint: Color = .secondary, opacity: Double = 0.15) -> some View {
        self
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(opacity), in: Capsule())
    }

    /// Единый стиль карточки дашборда: материал-фон, тонкая обводка, единый радиус.
    /// Цветовой акцент карточки задаётся через `tint` (тонкая обводка + лёгкий фон),
    /// чтобы не заливать всю карточку насыщенным цветом.
    func dashboardCard(padding: CGFloat = 16, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: shape)
            .background(tint.map { $0.opacity(0.08) } ?? .clear, in: shape)
            .overlay(shape.stroke(tint?.opacity(0.35) ?? Color.primary.opacity(0.08),
                                  lineWidth: 1))
    }
}

// MARK: - Keys

struct KeysView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rotation: RotationManager

    // Категория ключей, отображаемая этим списком: обычные («Ключи») или
    // FreeModel (подменю в боковой панели). Списки независимы, но ротация идёт
    // по всем включённым ключам обеих категорий.
    let category: KeyCategory

    @State private var editorKey: APIKey?
    @State private var editorIsNew = false
    @State private var selection: APIKey.ID?
    @State private var search = ""
    @State private var keyToDelete: APIKey?

    // Ширина области списка — для адаптивной вёрстки строк: на узком окне
    // строки переходят в компактный режим (результат проверки — только
    // иконкой, без строки «сброс через…», суженные колонки), чтобы больше
    // ширины доставалось панели лимитов.
    @State private var listWidth: CGFloat = 0

    private var isCompact: Bool { listWidth > 0 && listWidth < 1000 }

    // Ключи текущей категории. Обычные — в порядке общего списка; FreeModel —
    // автосортировка по лимитам (заполнение 5-часового окна 0% → 100%, затем
    // более ранний сброс 7-дневного окна; без данных — после них, полностью
    // исчерпанные — в самом конце), а при
    // выключенной настройке `freeModelAutoSort` — ручной порядок. Тот же
    // порядок использует автопереключение с исчерпанного ключа.
    private var categoryKeys: [APIKey] {
        category == .freeModel ? store.displayedFreeModelKeys() : store.keys(in: category)
    }

    // Ключи, отфильтрованные строкой поиска (по имени, base URL и самому ключу).
    private var filteredKeys: [APIKey] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return categoryKeys }
        return categoryKeys.filter {
            $0.name.lowercased().contains(q)
                || $0.baseURL.lowercased().contains(q)
                || $0.apiKey.lowercased().contains(q)
        }
    }

    // Биндинг к элементу `store.keys` по id (нужен строкам, т.к. при фильтрации
    // ForEach идёт по значениям, а не по `$store.keys`).
    private func binding(for key: APIKey) -> Binding<APIKey> {
        Binding(
            get: { store.keys.first(where: { $0.id == key.id }) ?? key },
            set: { newValue in
                if let idx = store.keys.firstIndex(where: { $0.id == key.id }) {
                    store.keys[idx] = newValue
                }
            }
        )
    }

    // Фон строки во всю ширину (единый механизм для зебры и подсветки, чтобы они
    // совпадали по форме): выключенный ключ — приглушённая серая заливка,
    // остальные — собственная «зебра» по чётности индекса. Активный ключ фоном
    // не выделяется — его показывает увеличенный пульсирующий кружок слева.
    private func rowBackground(for key: APIKey, index: Int) -> Color {
        if !key.enabled { return Color.secondary.opacity(0.22) }
        return index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04)
    }

    var body: some View {
        VStack(spacing: 0) {
            if categoryKeys.isEmpty {
                emptyState
            } else {
                ListSearchField(placeholder: store.tr("Поиск ключей", "Search keys"),
                                text: $search)
                if filteredKeys.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    keyList
                }
            }
            Divider()
            bottomBar
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { listWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, width in listWidth = width }
            }
        )
        .onAppear {
            // Подтянуть лимиты при заходе в раздел, но не чаще раза в минуту
            // (основное обновление — фоновый таймер в AppStore).
            if category == .freeModel { store.refreshAllUsage(minInterval: 60) }
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
        .alert(store.tr("Удалить ключ?", "Delete key?"),
               isPresented: Binding(get: { keyToDelete != nil },
                                    set: { if !$0 { keyToDelete = nil } }),
               presenting: keyToDelete) { key in
            Button(store.tr("Удалить", "Delete"), role: .destructive) {
                if selection == key.id { selection = nil }
                store.deleteKey(key)
            }
            Button(store.tr("Отмена", "Cancel"), role: .cancel) { }
        } message: { key in
            let name = key.name.isEmpty ? store.tr("Без названия", "Untitled") : key.name
            Text(store.tr("«\(name)» будет удалён безвозвратно.",
                          "“\(name)” will be deleted permanently."))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(category == .freeModel
                  ? store.tr("Нет ключей FreeModel", "No FreeModel Keys")
                  : store.tr("Нет ключей", "No API Keys"),
                  systemImage: category == .freeModel ? "sparkles" : "key.horizontal")
        } description: {
            Text(category == .freeModel
                 ? store.tr("Здесь хранятся ключи, полученные через сервис FreeModel.",
                            "Keys obtained through the FreeModel service live here.")
                 : store.tr("Добавьте ключ, чтобы начать ротацию.",
                            "Add a key to start rotating credentials."))
        } actions: {
            Button {
                presentNew()
            } label: {
                Label(store.tr("Добавить ключ", "Add Key"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var keyList: some View {
        List(selection: $selection) {
            ForEach(Array(filteredKeys.enumerated()), id: \.element.id) { index, key in
                KeyRow(key: binding(for: key),
                       isActive: store.currentKeyID == key.id,
                       testState: store.testStates[key.id],
                       compact: isCompact,
                       onToggle: { store.save() },
                       onTest: { store.test(key) },
                       onEdit: { presentEdit(key) },
                       onActivate: { rotation.apply(key) },
                       onDelete: { keyToDelete = key })
                    .tag(key.id)
                    .listRowBackground(rowBackground(for: key, index: index))
                    // Прямоугольная форма хит-тестинга: без неё «пустые» участки
                    // строки (Spacer, Color.clear-колонки) не ловят двойной клик.
                    .contentShape(Rectangle())
                    // Явное выделение по одиночному клику: жест двойного клика
                    // заставляет систему ждать возможного второго клика, из-за
                    // чего штатное выделение List срабатывало не с первого раза.
                    .simultaneousGesture(TapGesture().onEnded { selection = key.id })
                    .simultaneousGesture(TapGesture(count: 2).onEnded { presentEdit(key) })
                    .contextMenu {
                        Button(store.tr("Проверить", "Test")) { store.test(key) }
                        Button(store.tr("Сделать активным", "Set as Active Now")) { rotation.apply(key) }
                            .disabled(store.currentKeyID == key.id)
                        Divider()
                        Button(store.tr("Изменить", "Edit")) { presentEdit(key) }
                        Button(store.tr("Удалить", "Delete"), role: .destructive) { keyToDelete = key }
                    }
            }
            // Перетаскивание доступно только без активного поиска (иначе индексы
            // отфильтрованного списка не совпадают со списком категории) и не в
            // FreeModel с включённой автосортировкой по лимитам — там порядок
            // автоматический.
            .onMove(perform: (search.isEmpty
                              && (category != .freeModel || !store.freeModelAutoSort))
                    ? { store.move(in: category, from: $0, to: $1) } : nil)
        }
        .listStyle(.inset)
        // Enter/Return делает выбранный ключ активным (аналог кнопки
        // «Сделать активным» в тулбаре); без выбора или на уже активном
        // ключе нажатие передаётся дальше.
        .onKeyPress(.return) {
            guard let id = selection, id != store.currentKeyID,
                  let key = store.keys.first(where: { $0.id == id }) else { return .ignored }
            rotation.apply(key)
            return .handled
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ToolbarIconButton(systemName: "plus",
                              help: store.tr("Добавить ключ", "Add key")) {
                presentNew()
            }

            ToolbarIconButton(systemName: "minus",
                              help: store.tr("Удалить выбранный ключ", "Remove selected key"),
                              disabled: selection == nil) {
                if let id = selection, let key = store.keys.first(where: { $0.id == id }) {
                    keyToDelete = key
                }
            }

            Divider().frame(height: 16)

            ToolbarIconButton(systemName: "pencil",
                              help: store.tr("Изменить выбранный ключ", "Edit selected key"),
                              disabled: selection == nil) {
                if let id = selection, let key = store.keys.first(where: { $0.id == id }) {
                    presentEdit(key)
                }
            }

            ToolbarIconButton(systemName: "checkmark.circle",
                              help: store.tr("Сделать выбранный ключ активным", "Set selected key as active now"),
                              disabled: selection == nil || selection == store.currentKeyID) {
                if let id = selection, let key = store.keys.first(where: { $0.id == id }) {
                    rotation.apply(key)
                }
            }

            Divider().frame(height: 16)

            ToolbarIconButton(systemName: "checkmark.shield",
                              help: store.tr("Проверить все ключи", "Test all keys"),
                              disabled: categoryKeys.isEmpty) {
                store.testAll(in: category)
            }

            // Последовательное обновление лимитов всех аккаунтов FreeModel:
            // запросы идут по очереди с настраиваемой паузой после каждого ответа.
            if category == .freeModel {
                ToolbarIconButton(systemName: "arrow.triangle.2.circlepath",
                                  help: store.tr("Обновить все лимиты (по очереди, с паузой \(store.freeModelSequentialPauseSeconds) с)",
                                                 "Refresh all limits (sequentially, \(store.freeModelSequentialPauseSeconds) s apart)"),
                                  disabled: !store.hasUsageTokens || store.usageRefreshingAll) {
                    store.refreshAllUsageSequentially()
                }
                if store.usageRefreshingAll {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }
            }

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func presentNew() {
        editorIsNew = true
        // Prefill base URL from the previous key of the same category. For
        // FreeModel keep it empty so the shared base URL applies by default.
        let prefill = category == .freeModel ? "" : (categoryKeys.last?.baseURL ?? "")
        editorKey = APIKey(baseURL: prefill, category: category)
    }

    private func presentEdit(_ key: APIKey) {
        editorIsNew = false
        editorKey = key
    }
}

// Пульсирующий кружок-индикатор активного ключа: светящееся ядро и два
// расходящихся затухающих кольца со сдвигом фазы (ореол читается непрерывно,
// а не «вспышками» раз в цикл). Анимация запускается в onAppear и крутится
// бесконечно (repeatForever), пока строка активна.
struct PulsingDot: View {
    let color: Color

    @State private var pulsing = false

    var body: some View {
        ZStack {
            ring(delay: 0)
            ring(delay: 0.75)
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .shadow(color: color.opacity(0.8), radius: 3)
        }
        // Пропорциональное уменьшение всего индикатора (ядро + ореол) на 20%,
        // сама анимация колец при этом не меняется.
        .scaleEffect(0.8)
        .onAppear { pulsing = true }
    }

    // Кольцо рисуется штрихом (а не заливкой), поэтому остаётся видимым и на
    // большом радиусе; delay сдвигает фазу второго кольца на полцикла.
    private func ring(delay: Double) -> some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: 12, height: 12)
            .scaleEffect(pulsing ? 2.6 : 1.0)
            .opacity(pulsing ? 0 : 0.85)
            .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false).delay(delay),
                       value: pulsing)
    }
}

// MARK: - Форматирование лимитов FreeModel

// Общие форматтеры панелей лимитов — используются и строками списка FreeModel
// (KeyRow.usagePanel), и карточкой лимитов на дашборде (DashboardView.usageCard).

// «$12» для круглых сумм, «$46.19» — для остальных.
private func usageMoney(_ cents: Int) -> String {
    cents % 100 == 0 ? "$\(cents / 100)" : String(format: "$%.2f", Double(cents) / 100)
}

// Через сколько сбросится окно: «через 32 мин», «через 1 ч 12 м»,
// «через 2 дн 3 ч». `now` приходит из TimelineView, чтобы подпись тикала.
private func usageResetCountdown(_ date: Date, now: Date, store: AppStore) -> String {
    let seconds = date.timeIntervalSince(now)
    guard seconds > 0 else { return store.tr("сейчас", "now") }
    let totalMinutes = max(1, Int((seconds / 60).rounded(.up)))
    if totalMinutes < 60 {
        return store.tr("через \(totalMinutes) мин", "in \(totalMinutes) min")
    }
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours < 24 {
        return minutes == 0
            ? store.tr("через \(hours) ч", "in \(hours) h")
            : store.tr("через \(hours) ч \(minutes) м", "in \(hours) h \(minutes) m")
    }
    let days = hours / 24
    let remHours = hours % 24
    return remHours == 0
        ? store.tr("через \(days) дн", "in \(days) d")
        : store.tr("через \(days) дн \(remHours) ч", "in \(days) d \(remHours) h")
}

private func usageWindowTooltip(_ label: String, _ window: FreeModelUsage.Window,
                                fetchedAt: Date, store: AppStore) -> String {
    let used = String(format: "$%.2f", Double(window.usedCents) / 100)
    let limit = String(format: "$%.2f", Double(window.limitCents) / 100)
    let reset = window.resetDate.formatted(date: .abbreviated, time: .shortened)
    let updated = fetchedAt.formatted(date: .omitted, time: .shortened)
    return store.tr("Окно \(label): \(used) из \(limit) · сброс: \(reset) · обновлено в \(updated)",
                    "\(label) window: \(used) of \(limit) · resets: \(reset) · updated at \(updated)")
}

struct KeyRow: View {
    @EnvironmentObject private var store: AppStore
    @Binding var key: APIKey
    let isActive: Bool
    let testState: KeyTestState?
    // Компактный режим на узком окне (< 1000 pt, измеряет KeysView): результат
    // проверки — только иконкой, без обратного отсчёта «сброс через…»,
    // суженные колонки и отступы.
    let compact: Bool
    let onToggle: () -> Void
    let onTest: () -> Void
    let onEdit: () -> Void
    let onActivate: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var copiedKey = false
    @State private var copiedProxy = false

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            statusDot
            if key.category == .freeModel {
                // У FreeModel-ключей base URL в строке не показывается (обычно
                // это общий URL категории): имя — фиксированная колонка, а всю
                // свободную ширину занимает панель лимитов аккаунта.
                Text(displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
                usagePanel
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .fontWeight(.medium)
                    Text(baseURLLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            // Две «колонки»-капсулы с фиксированной шириной: у всех строк
            // капсула ключа и капсула прокси выровнены по общим вертикалям.
            Group {
                if let suffix = keySuffix {
                    keySuffixChip(suffix)
                } else {
                    Color.clear
                }
            }
            .frame(width: 70, alignment: .leading)
            Group {
                if let proxy = store.assignedProxy(for: key) {
                    proxyChip(proxy)
                } else {
                    noProxyChip
                }
            }
            .frame(width: 140, alignment: .leading)
            // На узком окне всё между прокси и тумблером (результат проверки и
            // кнопки действий) скрывается, чтобы освободить ширину; на широком —
            // результат проверки в фиксированной колонке 80 pt (место
            // зарезервировано всегда, чтобы текст «Валиден»/«HTTP …» не сдвигал
            // капсулы) и кнопки действий при наведении.
            if !compact {
                testIndicator
                    .frame(width: 80, alignment: .leading)
                hoverActions
            }
            Toggle("", isOn: $key.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: key.enabled) { _, _ in onToggle() }
        }
        .padding(.vertical, 4)
        .onHover { hovering = $0 }
    }

    // Индикатор состояния слева: у активного ключа — увеличенный зелёный кружок
    // с пульсирующим ореолом (именно он выделяет активную строку — фон строки
    // не меняется), у следующего по ротации (`store.nextKeyID`) — синяя точка,
    // у остальных — маленькая серая. Контейнер фиксированного размера, чтобы
    // смена активного ключа не сдвигала вёрстку строк.
    private var statusDot: some View {
        ZStack {
            if isActive {
                PulsingDot(color: .green)
            } else if store.nextKeyID == key.id {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 9, height: 9)
                    .help(store.tr("Следующий ключ", "Next key"))
            } else {
                Circle()
                    .fill(key.enabled ? Color.secondary : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 14, height: 14)
    }

    // Имя ключа, обрезанное до 20 символов (длинные имена не растягивают строку).
    private var displayName: String {
        let name = key.name.isEmpty ? store.tr("Без названия", "Untitled") : key.name
        return name.count > 20 ? String(name.prefix(20)) + "…" : name
    }

    // Подпись base URL: собственный URL ключа, для FreeModel-ключа без своего —
    // общий URL категории с пометкой «Общий», иначе «Нет base URL».
    private var baseURLLabel: String {
        if !key.baseURL.isEmpty { return key.baseURL }
        let effective = store.effectiveBaseURL(for: key)
        if !effective.isEmpty {
            return store.tr("Общий: \(effective)", "Shared: \(effective)")
        }
        return store.tr("Нет base URL", "No base URL")
    }

    // Последние 3 символа самого API-ключа (`..Jj4`) для быстрой идентификации.
    private var keySuffix: String? {
        let trimmed = key.apiKey.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }
        return ".." + trimmed.suffix(3)
    }

    // Панель лимитов аккаунта FreeModel — занимает всю свободную ширину строки.
    // Два индикатора окон (5 ч / 7 дн): полоса прогресса на «резиновой» ширине,
    // проценты, суммы и обратный отсчёт до сброса; справа — кнопка ручного
    // обновления. Отсчёт тикает раз в минуту (TimelineView).
    @ViewBuilder
    private var usagePanel: some View {
        Group {
            switch store.usageStates[key.id] {
            case .loaded(let usage, let fetchedAt):
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack(spacing: compact ? 10 : 14) {
                        usageGauge(store.tr("5 ч", "5 h"), usage.window5h,
                                   fetchedAt: fetchedAt, now: context.date)
                        usageGauge(store.tr("7 дн", "7 d"), usage.windowWeek,
                                   fetchedAt: fetchedAt, now: context.date)
                        usageRefreshButton
                    }
                }
            case .loading:
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(store.tr("Загрузка лимитов…", "Loading limits…"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            case .failure(let message):
                HStack(spacing: 6) {
                    Label(store.tr("Лимиты недоступны", "Limits unavailable"),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .help(message)
                    usageRefreshButton
                }
            case nil:
                if hasUsageToken {
                    HStack(spacing: 6) {
                        Text(store.tr("Лимиты не загружены", "Limits not loaded"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        usageRefreshButton
                    }
                } else {
                    Text(store.tr("Нет токена сессии — лимиты недоступны",
                                  "No session token — limits unavailable"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help(store.tr("Вставьте cookie bm_session с freemodel.dev в поле «Токен сессии» редактора ключа.",
                                       "Paste the bm_session cookie from freemodel.dev into the “Session token” field of the key editor."))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasUsageToken: Bool {
        !(key.usageToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Ручное обновление лимитов этого ключа (и всех ключей того же аккаунта —
    // запрос группируется по токену сессии в AppStore).
    private var usageRefreshButton: some View {
        Button {
            store.refreshUsage(for: key)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .disabled(!hasUsageToken)
        .help(store.tr("Обновить лимиты", "Refresh limits"))
    }

    // Один индикатор окна: заголовок (подпись, процент, суммы «$46.19 / $66»),
    // полоса прогресса во всю доступную ширину (цвет по степени заполнения)
    // и обратный отсчёт до сброса. Точная дата сброса и время обновления —
    // в тултипе.
    private func usageGauge(_ label: String, _ window: FreeModelUsage.Window,
                            fetchedAt: Date, now: Date) -> some View {
        let fraction = window.fraction
        let color = window.tint
        let percent = Int((fraction * 100).rounded())
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(percent)%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
                Spacer(minLength: 6)
                Text("\(usageMoney(window.usedCents)) / \(usageMoney(window.limitCents))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                Capsule()
                    .fill(color.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color.gradient)
                            .frame(width: max(3, geo.size.width * fraction))
                    }
            }
            .frame(height: 5)
            HStack(spacing: 2) {
                Image(systemName: "clock.arrow.circlepath")
                Text(store.tr("сброс \(usageResetCountdown(window.resetDate, now: now, store: store))",
                              "resets \(usageResetCountdown(window.resetDate, now: now, store: store))"))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .help(usageWindowTooltip(label, window, fetchedAt: fetchedAt, store: store))
    }

    // Кнопки действий, проявляющиеся при наведении на строку. Пространство
    // зарезервировано всегда (opacity), чтобы остальные элементы не «прыгали».
    private var hoverActions: some View {
        HStack(spacing: 2) {
            rowAction("checkmark.shield", store.tr("Проверить", "Test"), action: onTest)
            rowAction("pencil", store.tr("Изменить", "Edit"), action: onEdit)
            rowAction("checkmark.circle", store.tr("Сделать активным", "Set as active"),
                      disabled: isActive, action: onActivate)
            rowAction("trash", store.tr("Удалить", "Delete"), tint: .red, action: onDelete)
        }
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }

    private func rowAction(_ icon: String, _ help: String, tint: Color = .secondary,
                           disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
        .disabled(disabled)
        .help(help)
    }

    // Бейдж с названием привязанного прокси. Когда прокси отключены глобально,
    // показывается приглушённо с подсказкой, что он не применяется. Клик копирует
    // полную строку прокси (`логин:пароль@host:port`) в буфер обмена.
    private func proxyChip(_ proxy: Proxy) -> some View {
        let active = store.proxiesEnabled
        let canCopy = proxy.copyString != nil
        return Button {
            if let s = proxy.copyString { copy(s, flag: $copiedProxy) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: copiedProxy ? "checkmark" : "network")
                Text(proxy.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .tagChip(tint: active ? Color.secondary : Color.secondary.opacity(0.5),
                     opacity: active ? 0.15 : 0.08)
        }
        .buttonStyle(.plain)
        .disabled(!canCopy)
        .help(copiedProxy
              ? store.tr("Скопировано", "Copied")
              : store.tr("Копировать прокси: \(proxy.displayName)", "Copy proxy: \(proxy.displayName)"))
    }

    // Плейсхолдер на месте капсулы прокси, когда ключу не назначен прокси.
    // Делает строку визуально однородной с остальными (та же высота/положение
    // капсулы), но приглушённо и без действия по клику.
    private var noProxyChip: some View {
        HStack(spacing: 3) {
            Image(systemName: "network.slash")
            Text(store.tr("Нет", "None"))
                .lineLimit(1)
        }
        .tagChip(tint: Color.secondary.opacity(0.5), opacity: 0.08)
        .foregroundStyle(.secondary)
        .help(store.tr("Прокси не назначен", "No proxy assigned"))
    }

    // Капсула с последними 3 символами API-ключа (`..Jj4`) с иконкой ключа —
    // в стиле колонки прокси. Клик копирует полный API-ключ в буфер обмена.
    private func keySuffixChip(_ suffix: String) -> some View {
        Button {
            copy(key.apiKey, flag: $copiedKey)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: copiedKey ? "checkmark" : "key")
                Text(suffix)
                    .font(.caption.monospaced())
            }
            .tagChip(tint: Color.secondary, opacity: 0.15)
        }
        .buttonStyle(.plain)
        .help(copiedKey
              ? store.tr("Скопировано", "Copied")
              : store.tr("Копировать API-ключ", "Copy API key"))
    }

    // Копирует строку в буфер обмена и кратко подсвечивает капсулу галочкой.
    private func copy(_ string: String, flag: Binding<Bool>) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        flag.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            flag.wrappedValue = false
        }
    }

    @ViewBuilder
    private var testIndicator: some View {
        switch testState {
        case .testing:
            ProgressView()
                .controlSize(.small)
        case .success:
            Label(store.tr("Валиден", "Valid"), systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .foregroundStyle(.green)
                .help(store.tr("Валиден", "Valid"))
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
                .help(message)
        case nil:
            // Не EmptyView: у EmptyView модификатор .frame не создаёт места,
            // и колонка результата схлопнулась бы, сдвинув соседние колонки.
            Color.clear
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

    // Плейсхолдер поля Base URL: для FreeModel-ключа показывает общий URL
    // категории (он и применится, если поле оставить пустым).
    private var baseURLPrompt: String {
        if draft.category == .freeModel {
            let shared = store.freeModelBaseURL.trimmingCharacters(in: .whitespaces)
            if !shared.isEmpty { return shared }
        }
        return "https://api.anthropic.com"
    }

    private func runTest() {
        testState = .testing
        let api = draft.apiKey
        // Как при ротации: пустой Base URL у FreeModel-ключа заменяется общим.
        let base = store.effectiveBaseURL(for: draft)
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
                    Picker(store.tr("Категория", "Category"), selection: $draft.category) {
                        Text(store.tr("Обычный", "General")).tag(KeyCategory.general)
                        Text("FreeModel").tag(KeyCategory.freeModel)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(store.tr("Ключи FreeModel хранятся в подменю «FreeModel» вкладки «Ключи».",
                                  "FreeModel keys live in the “FreeModel” submenu of the Keys tab."))
                }

                Section {
                    TextField("API Key", text: $draft.apiKey, prompt: Text("sk-ant-…"))
                        .font(.system(.body, design: .monospaced))
                    TextField("Base URL", text: $draft.baseURL, prompt: Text(baseURLPrompt))
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text(store.tr("Учётные данные", "Credentials"))
                } footer: {
                    if draft.category == .freeModel {
                        Text(store.tr("Записывается в ANTHROPIC_API_KEY / ANTHROPIC_BASE_URL при ротации. Пустой Base URL — используется общий URL категории FreeModel.",
                                      "Written to ANTHROPIC_API_KEY / ANTHROPIC_BASE_URL on rotation. Leave Base URL empty to use the shared FreeModel URL."))
                    } else {
                        Text(store.tr("Записывается в ANTHROPIC_API_KEY / ANTHROPIC_BASE_URL при ротации.",
                                      "Written to ANTHROPIC_API_KEY / ANTHROPIC_BASE_URL on rotation."))
                    }
                }

                // Токен сессии дашборда FreeModel — только для показа лимитов
                // аккаунта (окна 5 ч / 7 дн) в списке; в файл не записывается.
                if draft.category == .freeModel {
                    Section {
                        TextField(store.tr("Токен сессии", "Session token"),
                                  text: Binding(
                                      get: { draft.usageToken ?? "" },
                                      set: {
                                          let t = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                          draft.usageToken = t.isEmpty ? nil : t
                                      }),
                                  prompt: Text("bm_session…"))
                            .font(.system(.body, design: .monospaced))
                    } header: {
                        Text(store.tr("Лимиты аккаунта", "Account limits"))
                    } footer: {
                        Text(store.tr("Значение cookie bm_session с сайта freemodel.dev (DevTools → Application → Cookies). Включает показ окон лимитов 5 ч / 7 дн в списке. Токен живёт ~30 дней; в целевой файл не записывается.",
                                      "The bm_session cookie value from freemodel.dev (DevTools → Application → Cookies). Enables the 5 h / 7 d limit windows in the list. The token lives ~30 days; it is never written to the target file."))
                    }
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
        .frame(width: 440, height: 530)
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

    // Вкладки настроек: «Общие» — цели, ротация, прокси, интерфейс, данные;
    // «FreeModel» — все настройки одноимённой категории ключей.
    private enum SettingsTab: Hashable {
        case general
        case freeModel
    }

    @State private var tab: SettingsTab = .general
    @State private var showResetConfirm = false

    // Системные звуки macOS, доступные через NSSound(named:) — выбор звука
    // уведомления об исчерпании лимитов.
    private static let systemSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk",
                                       "Glass", "Hero", "Morse", "Ping", "Pop",
                                       "Purr", "Sosumi", "Submarine", "Tink"]

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(store.tr("Общие", "General")).tag(SettingsTab.general)
                Text("FreeModel").tag(SettingsTab.freeModel)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .padding(.top, 10)

            switch tab {
            case .general: generalForm
            case .freeModel: freeModelForm
            }
        }
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

    // MARK: Вкладка «Общие»

    private var generalForm: some View {
        Form {
            Section {
                targetFileRow(title: store.tr("Claude Code (settings.json)", "Claude Code (settings.json)"),
                              isOn: $store.claudeEnabled,
                              hasFile: store.hasTargetFile,
                              path: store.filePath,
                              choose: { browse() })
            } header: {
                Label(store.tr("Claude Code", "Claude Code"), systemImage: "doc.text")
            } footer: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.tr("Обычно файл находится по адресу:",
                                  "The file is usually located at:"))
                    Text("\(defaultSettingsURL.path)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(store.tr("Чтобы Claude Code начал использовать новый ключ, обычно не требуется перезагрузка Claude Code.",
                                  "To make Claude Code use the new key, you usually don't need to restart Claude Code."))
                }
            }

            Section {
                targetFileRow(title: store.tr("Codex (auth.json)", "Codex (auth.json)"),
                              isOn: $store.codexEnabled,
                              hasFile: store.hasCodexFile,
                              path: store.codexFilePath,
                              choose: { browseCodex() })
            } header: {
                Label(store.tr("Codex", "Codex"), systemImage: "doc.text")
            } footer: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.tr("Обычно файл находится по адресу:",
                                  "The file is usually located at:"))
                    Text("\(defaultCodexURL.path)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(store.tr("Чтобы Codex начал использовать новый ключ, обычно требуется перезагрузка плагина Codex.",
                                  "To make Codex use the new key, you usually need to reload the Codex plugin."))
                }
            }

            Section {
                LabeledContent(store.tr("Интервал", "Interval")) {
                    HStack(spacing: 8) {
                        TextField("", value: $store.intervalMinutes, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)
                            .multilineTextAlignment(.trailing)
                        Text(store.tr("мин", "min"))
                            .foregroundStyle(.secondary)
                        Stepper("", value: $store.intervalMinutes, in: 1...1440)
                            .labelsHidden()
                    }
                }
                .onChange(of: store.intervalMinutes) { _, newValue in
                    if newValue < 1 { store.intervalMinutes = 1 }
                    store.save()
                    rotation.restartIfRunning()
                }

                Picker(store.tr("Быстрый выбор", "Quick set"), selection: $store.intervalMinutes) {
                    Text("15").tag(15)
                    Text("30").tag(30)
                    Text("60").tag(60)
                    Text("120").tag(120)
                }
                .pickerStyle(.segmented)

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

                Toggle(store.tr("Скрывать из Dock", "Hide from Dock"),
                       isOn: $store.hideFromDock)
                    .onChange(of: store.hideFromDock) { _, _ in store.save() }
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
                }
            } header: {
                Label(store.tr("Данные", "Data"), systemImage: "externaldrive")
            } footer: {
                Text(store.tr("Экспорт сохраняет ключи, прокси и настройки в файл. Выбранный целевой файл не переносится.",
                              "Export saves keys, proxies and settings to a file. The selected target file is not included."))
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label(store.tr("Сбросить всё…", "Reset all…"), systemImage: "trash")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text(store.tr("Удаляет все ключи, прокси и настройки без возможности восстановления. Сам settings.json не трогается.",
                              "Removes all keys, proxies and settings permanently. Your settings.json is left untouched."))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Вкладка «FreeModel»

    private var freeModelForm: some View {
        Form {
            Section {
                TextField(store.tr("Общий Base URL", "Shared base URL"),
                          text: $store.freeModelBaseURL,
                          prompt: Text("https://…"))
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: store.freeModelBaseURL) { _, _ in store.save() }
            } header: {
                Label("Base URL", systemImage: "link")
            } footer: {
                Text(store.tr("Применяется к FreeModel-ключам, у которых не задан собственный Base URL. Ключ с собственным Base URL использует свой.",
                              "Applies to FreeModel keys without their own base URL. A key with its own base URL uses that instead."))
            }

            Section {
                Toggle(store.tr("Автообновление лимитов", "Auto-refresh limits"),
                       isOn: $store.freeModelAutoRefresh)
                    .onChange(of: store.freeModelAutoRefresh) { _, _ in store.save() }

                numberRow(store.tr("Активный аккаунт", "Active account"),
                          value: $store.freeModelActiveRefreshMinutes,
                          range: 1...60,
                          unit: store.tr("мин", "min"))
                    .disabled(!store.freeModelAutoRefresh)

                numberRow(store.tr("Остальные аккаунты", "Other accounts"),
                          value: $store.freeModelOthersRefreshMinutes,
                          range: 1...180,
                          unit: store.tr("мин", "min"))
                    .disabled(!store.freeModelAutoRefresh)

                numberRow(store.tr("Пауза «Обновить все»", "“Refresh all” pause"),
                          value: $store.freeModelSequentialPauseSeconds,
                          range: 0...60,
                          unit: store.tr("с", "s"))
            } header: {
                Label(store.tr("Обновление лимитов", "Limits refresh"),
                      systemImage: "clock.arrow.circlepath")
            } footer: {
                Text(store.tr("Лимиты аккаунтов запрашиваются в фоне: аккаунт активного ключа — чаще, остальные — реже. Когда автообновление выключено, лимиты обновляются только вручную и при входе в раздел FreeModel. Пауза — интервал между аккаунтами при последовательном «Обновить все».",
                              "Account limits are fetched in the background: the active key's account more often, the rest less often. When auto-refresh is off, limits update only manually and when opening the FreeModel section. The pause is the delay between accounts during the sequential “Refresh all”."))
            }

            Section {
                Toggle(store.tr("Переключать ключ автоматически", "Switch key automatically"),
                       isOn: $store.freeModelAutoSwitch)
                    .onChange(of: store.freeModelAutoSwitch) { _, _ in store.save() }

                numberRow(store.tr("Порог исчерпания", "Exhaustion threshold"),
                          value: $store.freeModelSwitchThresholdPercent,
                          range: 50...100,
                          unit: "%")

                Toggle(store.tr("Звук при исчерпании", "Play sound on exhaustion"),
                       isOn: $store.freeModelSoundEnabled)
                    .onChange(of: store.freeModelSoundEnabled) { _, _ in store.save() }

                Picker(store.tr("Звук", "Sound"), selection: $store.freeModelSoundName) {
                    ForEach(Self.systemSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .disabled(!store.freeModelSoundEnabled)
                .onChange(of: store.freeModelSoundName) { _, _ in
                    store.save()
                    // Прослушивание: выбранный звук сразу проигрывается.
                    store.playExhaustSound()
                }
            } header: {
                Label(store.tr("Исчерпание лимитов", "Limit exhaustion"),
                      systemImage: "bolt.badge.clock")
            } footer: {
                Text(store.tr("Когда любое окно лимитов (5 ч или 7 дн) активного FreeModel-ключа доходит до порога, играет звук и активным становится верхний ключ таблицы FreeModel (кроме исчерпанного). Если других включённых FreeModel-ключей нет, смена не происходит.",
                              "When either usage window (5 h or 7 d) of the active FreeModel key reaches the threshold, a sound plays and the top key of the FreeModel table (other than the exhausted one) becomes active. If there are no other enabled FreeModel keys, no switch happens."))
            }

            Section {
                Toggle(store.tr("Лимиты в меню-баре", "Limits in the menu bar"),
                       isOn: $store.freeModelMenuBarIcon)
                    .onChange(of: store.freeModelMenuBarIcon) { _, _ in store.save() }

                Toggle(store.tr("Автосортировка списка по лимитам", "Auto-sort list by limits"),
                       isOn: $store.freeModelAutoSort)
                    .onChange(of: store.freeModelAutoSort) { _, _ in store.save() }
            } header: {
                Label(store.tr("Отображение", "Appearance"), systemImage: "eye")
            } footer: {
                Text(store.tr("«Лимиты в меню-баре» — вместо значка приложения показывается процент 5-часового окна активного FreeModel-ключа с цветной полоской. Автосортировка упорядочивает список FreeModel по заполнению 5-часового окна; когда она выключена, порядок ручной (перетаскиванием), как у обычных ключей. Этот же порядок использует автопереключение.",
                              "“Limits in the menu bar” replaces the app icon with the active FreeModel key's 5-hour window percentage and a colored bar. Auto-sort orders the FreeModel list by 5-hour window usage; when off, the order is manual (drag and drop), like regular keys. Auto-switching uses the same order."))
            }
        }
        .formStyle(.grouped)
    }

    /// Строка числовой настройки: подпись, текстовое поле, единица измерения и
    /// степпер. Значение зажимается в `range` и сохраняется при каждом изменении.
    @ViewBuilder
    private func numberRow(_ title: String,
                           value: Binding<Int>,
                           range: ClosedRange<Int>,
                           unit: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField("", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .multilineTextAlignment(.trailing)
                Text(unit)
                    .foregroundStyle(.secondary)
                Stepper("", value: value, in: range)
                    .labelsHidden()
            }
        }
        .onChange(of: value.wrappedValue) { _, newValue in
            let clamped = min(max(newValue, range.lowerBound), range.upperBound)
            if clamped != newValue { value.wrappedValue = clamped }
            store.save()
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

    /// Typical location of the Codex auth file for the current user.
    private var defaultCodexURL: URL {
        realHomeDirectory.appendingPathComponent(".codex/auth.json")
    }

    /// Одна строка целевого файла: переключатель включения, индикатор/путь и
    /// кнопка выбора файла. При смене переключателя сохраняем и сразу применяем
    /// текущий ключ, чтобы включённая цель получила его без ожидания ротации.
    @ViewBuilder
    private func targetFileRow(title: String,
                               isOn: Binding<Bool>,
                               hasFile: Bool,
                               path: String,
                               choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: isOn) { Text(title) }
                .onChange(of: isOn.wrappedValue) { _, _ in
                    store.save()
                    if let key = store.currentKey { rotation.apply(key) }
                }
            HStack(spacing: 8) {
                Image(systemName: hasFile ? "doc.text.fill" : "doc.text")
                    .foregroundStyle(hasFile ? .green : .secondary)
                Text(path.isEmpty
                     ? store.tr("Файл не выбран", "No file selected")
                     : path)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button(store.tr("Выбрать…", "Choose…")) { choose() }
            }
        }
    }

    private func browse() {
        pickJSON(near: defaultSettingsURL) { store.setTargetFile($0) }
    }

    private func browseCodex() {
        pickJSON(near: defaultCodexURL) { store.setCodexFile($0) }
    }

    /// Открывает `NSOpenPanel` для выбора JSON-файла, пред-навигируя к `suggested`
    /// (скрытые папки `.claude`/`.codex` делаются видимыми). При подтверждении
    /// вызывает `onPick` с выбранным URL. Песочница требует явного подтверждения
    /// для предоставления доступа.
    private func pickJSON(near suggested: URL, onPick: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.showsHiddenFiles = true
        if FileManager.default.fileExists(atPath: suggested.path) {
            panel.directoryURL = suggested.deletingLastPathComponent()
            panel.nameFieldStringValue = suggested.lastPathComponent
        } else {
            panel.directoryURL = realHomeDirectory
        }
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }
}

// MARK: - Proxies

struct ProxiesView: View {
    @EnvironmentObject private var store: AppStore

    @State private var editorProxy: Proxy?
    @State private var editorIsNew = false
    @State private var selection: Proxy.ID?
    @State private var search = ""
    @State private var proxyToDelete: Proxy?

    // Прокси, отфильтрованные строкой поиска (по имени и хосту).
    private var filteredProxies: [Proxy] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.proxies }
        return store.proxies.filter {
            $0.name.lowercased().contains(q) || $0.host.lowercased().contains(q)
        }
    }

    // Биндинг к элементу `store.proxies` по id (нужен строкам при фильтрации).
    private func binding(for proxy: Proxy) -> Binding<Proxy> {
        Binding(
            get: { store.proxies.first(where: { $0.id == proxy.id }) ?? proxy },
            set: { newValue in
                if let idx = store.proxies.firstIndex(where: { $0.id == proxy.id }) {
                    store.proxies[idx] = newValue
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.proxies.isEmpty {
                emptyState
            } else {
                ListSearchField(placeholder: store.tr("Поиск прокси", "Search proxies"),
                                text: $search)
                if filteredProxies.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    proxyList
                }
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
        .alert(store.tr("Удалить прокси?", "Delete proxy?"),
               isPresented: Binding(get: { proxyToDelete != nil },
                                    set: { if !$0 { proxyToDelete = nil } }),
               presenting: proxyToDelete) { proxy in
            Button(store.tr("Удалить", "Delete"), role: .destructive) {
                if selection == proxy.id { selection = nil }
                store.deleteProxy(proxy)
            }
            Button(store.tr("Отмена", "Cancel"), role: .cancel) { }
        } message: { proxy in
            let name = proxy.name.isEmpty ? store.tr("Без названия", "Untitled") : proxy.name
            let used = usageCount(of: proxy.id)
            let suffix = used > 0
                ? store.tr(" Он будет отвязан от ключей: \(used).",
                           " It will be detached from \(used) key(s).")
                : ""
            Text(store.tr("«\(name)» будет удалён безвозвратно.\(suffix)",
                          "“\(name)” will be deleted permanently.\(suffix)"))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(store.tr("Нет прокси", "No Proxies"), systemImage: "network")
        } description: {
            Text(store.tr("Добавьте прокси, чтобы привязывать его к ключам.",
                          "Add a proxy to assign it to your keys."))
        } actions: {
            Button {
                presentNew()
            } label: {
                Label(store.tr("Добавить прокси", "Add Proxy"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var proxyList: some View {
        List(selection: $selection) {
            ForEach(Array(filteredProxies.enumerated()), id: \.element.id) { index, proxy in
                ProxyRow(proxy: binding(for: proxy),
                         usageCount: usageCount(of: proxy.id),
                         testState: store.proxyTestStates[proxy.id],
                         onTest: { store.testProxy(proxy) },
                         onEdit: { presentEdit(proxy) },
                         onDelete: { proxyToDelete = proxy })
                    .tag(proxy.id)
                    .listRowBackground(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04))
                    // См. keyList: contentShape нужен, чтобы двойной клик ловился
                    // по всей строке, а не только по непрозрачным элементам;
                    // одиночный тап — явное выделение с первого клика.
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { selection = proxy.id })
                    .simultaneousGesture(TapGesture(count: 2).onEnded { presentEdit(proxy) })
                    .contextMenu {
                        Button(store.tr("Проверить", "Test")) { store.testProxy(proxy) }
                        Divider()
                        Button(store.tr("Изменить", "Edit")) { presentEdit(proxy) }
                        Button(store.tr("Удалить", "Delete"), role: .destructive) { proxyToDelete = proxy }
                    }
            }
            // Перетаскивание — только без активного поиска (см. KeysView).
            .onMove(perform: search.isEmpty ? { store.moveProxy(from: $0, to: $1) } : nil)
        }
        .listStyle(.inset)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ToolbarIconButton(systemName: "plus",
                              help: store.tr("Добавить прокси", "Add proxy")) {
                presentNew()
            }

            ToolbarIconButton(systemName: "minus",
                              help: store.tr("Удалить выбранный прокси", "Remove selected proxy"),
                              disabled: selection == nil) {
                if let id = selection, let proxy = store.proxies.first(where: { $0.id == id }) {
                    proxyToDelete = proxy
                }
            }

            Divider().frame(height: 16)

            ToolbarIconButton(systemName: "pencil",
                              help: store.tr("Изменить выбранный прокси", "Edit selected proxy"),
                              disabled: selection == nil) {
                if let id = selection, let proxy = store.proxies.first(where: { $0.id == id }) {
                    presentEdit(proxy)
                }
            }

            ToolbarIconButton(systemName: "checkmark.shield",
                              help: store.tr("Проверить выбранный прокси", "Test selected proxy"),
                              disabled: selection == nil) {
                if let id = selection, let proxy = store.proxies.first(where: { $0.id == id }) {
                    store.testProxy(proxy)
                }
            }

            Divider().frame(height: 16)

            ToolbarIconButton(systemName: "checkmark.shield.fill",
                              help: store.tr("Проверить все прокси", "Test all proxies"),
                              disabled: store.proxies.isEmpty) {
                store.testAllProxies()
            }

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
    let onTest: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
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
            hoverActions
            if usageCount > 0 {
                Text(store.tr("\(usageCount) ключ.", "\(usageCount) key(s)"))
                    .tagChip()
                    .help(store.tr("Используется ключами: \(usageCount)",
                                   "Used by \(usageCount) key(s)"))
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering = $0 }
    }

    // Кнопки действий, проявляющиеся при наведении (см. KeyRow.hoverActions).
    private var hoverActions: some View {
        HStack(spacing: 2) {
            rowAction("checkmark.shield", store.tr("Проверить", "Test"), action: onTest)
            rowAction("pencil", store.tr("Изменить", "Edit"), action: onEdit)
            rowAction("trash", store.tr("Удалить", "Delete"), tint: .red, action: onDelete)
        }
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }

    private func rowAction(_ icon: String, _ help: String, tint: Color = .secondary,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(tint)
        .help(help)
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
