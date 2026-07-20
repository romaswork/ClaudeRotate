//
//  AppStore.swift
//  ClaudeRotate
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    // Persisted configuration.
    // NOTE: these are updated in-memory immediately by UI bindings, but are NOT
    // written to disk on every change. Persistence happens explicitly via save()
    // on focus change, discrete actions, the "Save" button, and app backgrounding.
    @Published var keys: [APIKey] = []
    // Общий Base URL для ключей категории FreeModel. Применяется к ключу этой
    // категории, если у него не задан собственный baseURL (см. effectiveBaseURL).
    @Published var freeModelBaseURL: String = ""
    @Published var proxies: [Proxy] = []
    // Глобальный переключатель прокси. Когда выключен, ротация игнорирует прокси,
    // привязанные к ключам (переменные HTTPS_PROXY/HTTP_PROXY удаляются из файла),
    // но сами привязки ключей сохраняются.
    @Published var proxiesEnabled: Bool = true
    // Display-only path of the selected Claude target file (resolved from the
    // bookmark). Under App Sandbox actual file access goes through `fileBookmark`.
    @Published var filePath: String = ""
    // Включена ли запись в Claude-цель (settings.json) при ротации.
    @Published var claudeEnabled: Bool = true
    // Display-only path of the selected Codex target file (auth.json).
    @Published var codexFilePath: String = ""
    // Включена ли запись в Codex-цель (auth.json) при ротации.
    @Published var codexEnabled: Bool = false
    @Published var intervalMinutes: Int = 30
    @Published var startOnLaunch: Bool = false
    @Published var language: AppLanguage = .systemDefault
    // Скрывать иконку приложения из Dock. Когда включено, приложение работает
    // как accessory (только значок в меню-баре); окно настроек открывается из меню.
    @Published var hideFromDock: Bool = false

    // MARK: Настройки категории FreeModel (персистятся, вкладка «FreeModel» в настройках)

    // Фоновое автообновление лимитов (таймер-тикер). Когда выключено, лимиты
    // обновляются только вручную и при входе в раздел FreeModel.
    @Published var freeModelAutoRefresh: Bool = true
    // Интервал автообновления аккаунта активного ключа, минуты.
    @Published var freeModelActiveRefreshMinutes: Int = 2
    // Интервал автообновления остальных аккаунтов, минуты.
    @Published var freeModelOthersRefreshMinutes: Int = 15
    // Пауза между аккаунтами при последовательном «Обновить все», секунды.
    @Published var freeModelSequentialPauseSeconds: Int = 3
    // Автопереключение на верхний ключ таблицы FreeModel при исчерпании
    // любого из окон лимитов (5 ч или 7 дн) активного ключа.
    @Published var freeModelAutoSwitch: Bool = true
    // Порог «исчерпания» окна лимитов в процентах: детект перехода через
    // него запускает звук и автопереключение (по умолчанию 100%).
    @Published var freeModelSwitchThresholdPercent: Int = 100
    // Играть системный звук при исчерпании окна активного ключа.
    @Published var freeModelSoundEnabled: Bool = true
    // Имя системного звука (`NSSound(named:)`); при недоступности — beep.
    @Published var freeModelSoundName: String = "Glass"
    // Показывать в меню-баре кастомную иконку с процентом 5-часового окна
    // активного FreeModel-ключа (вместо системного символа).
    @Published var freeModelMenuBarIcon: Bool = true
    // Автосортировка списка FreeModel по лимитам. Когда выключено, порядок
    // ручной (как у обычных ключей, с перетаскиванием).
    @Published var freeModelAutoSort: Bool = true

    // Security-scoped bookmark to the user-selected Claude target file. Persisted;
    // used to regain access to the file across launches under App Sandbox. Not
    // shown in the UI directly (the readable path lives in `filePath`).
    private var fileBookmark: Data?
    // Security-scoped bookmark to the user-selected Codex target file (auth.json).
    private var codexFileBookmark: Data?

    // Transient runtime state (not persisted)
    @Published var isRunning: Bool = false
    @Published var currentKeyID: UUID?
    @Published var lastError: String?
    @Published var lastRotation: Date?

    // Transient per-key validation results (not persisted)
    @Published var testStates: [UUID: KeyTestState] = [:]

    // Transient per-proxy validation results (not persisted)
    @Published var proxyTestStates: [UUID: ProxyTestState] = [:]

    // Transient per-key FreeModel account limits (окна 5 ч / 7 дн); not persisted.
    @Published var usageStates: [UUID: FreeModelUsageState] = [:]
    // Идёт ли последовательное обновление всех аккаунтов (кнопка «Обновить все»).
    @Published var usageRefreshingAll = false
    // Вызывается, когда любое окно лимитов (5 ч или 7 дн) активного
    // FreeModel-ключа дошло до порога (см. performUsageFetch). RotationManager
    // подставляет сюда переключение на верхний ключ таблицы FreeModel
    // (порядок displayedFreeModelKeys). Транзиентно, не персистится.
    var onActiveKeyExhausted: (() -> Void)?
    // Токены, по которым запрос уже выполняется (защита от дублей).
    private var usageTokensInFlight: Set<String> = []
    // Когда токен опрашивался в последний раз (для minInterval).
    private var usageFetchedAt: [String: Date] = [:]
    private var usageTimer: Timer?

    private var isLoading = false

    // MARK: - Persistence

    private struct Config: Codable {
        var keys: [APIKey]
        var freeModelBaseURL: String?
        var proxies: [Proxy]?
        var proxiesEnabled: Bool?
        var filePath: String
        var fileBookmark: Data?
        var claudeEnabled: Bool?
        var codexFilePath: String?
        var codexFileBookmark: Data?
        var codexEnabled: Bool?
        var intervalMinutes: Int
        var startOnLaunch: Bool
        var currentKeyID: UUID?
        var language: AppLanguage?
        var hideFromDock: Bool?
        var freeModelAutoRefresh: Bool?
        var freeModelActiveRefreshMinutes: Int?
        var freeModelOthersRefreshMinutes: Int?
        var freeModelSequentialPauseSeconds: Int?
        var freeModelAutoSwitch: Bool?
        var freeModelSwitchThresholdPercent: Int?
        var freeModelSoundEnabled: Bool?
        var freeModelSoundName: String?
        var freeModelMenuBarIcon: Bool?
        var freeModelAutoSort: Bool?
    }

    private static var configURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ClaudeRotate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    init() {
        load()
        startUsageAutoRefresh()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: Self.configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return
        }
        keys = config.keys
        freeModelBaseURL = config.freeModelBaseURL ?? ""
        proxies = config.proxies ?? []
        proxiesEnabled = config.proxiesEnabled ?? true
        filePath = config.filePath
        fileBookmark = config.fileBookmark
        claudeEnabled = config.claudeEnabled ?? true
        codexFilePath = config.codexFilePath ?? ""
        codexFileBookmark = config.codexFileBookmark
        codexEnabled = config.codexEnabled ?? false
        intervalMinutes = max(1, config.intervalMinutes)
        startOnLaunch = config.startOnLaunch
        language = config.language ?? .systemDefault
        hideFromDock = config.hideFromDock ?? false
        freeModelAutoRefresh = config.freeModelAutoRefresh ?? true
        freeModelActiveRefreshMinutes = max(1, config.freeModelActiveRefreshMinutes ?? 2)
        freeModelOthersRefreshMinutes = max(1, config.freeModelOthersRefreshMinutes ?? 15)
        freeModelSequentialPauseSeconds = max(0, config.freeModelSequentialPauseSeconds ?? 3)
        freeModelAutoSwitch = config.freeModelAutoSwitch ?? true
        freeModelSwitchThresholdPercent = min(max(config.freeModelSwitchThresholdPercent ?? 100, 50), 100)
        freeModelSoundEnabled = config.freeModelSoundEnabled ?? true
        freeModelSoundName = config.freeModelSoundName ?? "Glass"
        freeModelMenuBarIcon = config.freeModelMenuBarIcon ?? true
        freeModelAutoSort = config.freeModelAutoSort ?? true
        // Restore the last active key only if it still exists.
        if let id = config.currentKeyID, keys.contains(where: { $0.id == id }) {
            currentKeyID = id
        }
    }

    func save() {
        guard !isLoading else { return }
        let config = Config(keys: keys,
                            freeModelBaseURL: freeModelBaseURL,
                            proxies: proxies,
                            proxiesEnabled: proxiesEnabled,
                            filePath: filePath,
                            fileBookmark: fileBookmark,
                            claudeEnabled: claudeEnabled,
                            codexFilePath: codexFilePath,
                            codexFileBookmark: codexFileBookmark,
                            codexEnabled: codexEnabled,
                            intervalMinutes: intervalMinutes,
                            startOnLaunch: startOnLaunch,
                            currentKeyID: currentKeyID,
                            language: language,
                            hideFromDock: hideFromDock,
                            freeModelAutoRefresh: freeModelAutoRefresh,
                            freeModelActiveRefreshMinutes: freeModelActiveRefreshMinutes,
                            freeModelOthersRefreshMinutes: freeModelOthersRefreshMinutes,
                            freeModelSequentialPauseSeconds: freeModelSequentialPauseSeconds,
                            freeModelAutoSwitch: freeModelAutoSwitch,
                            freeModelSwitchThresholdPercent: freeModelSwitchThresholdPercent,
                            freeModelSoundEnabled: freeModelSoundEnabled,
                            freeModelSoundName: freeModelSoundName,
                            freeModelMenuBarIcon: freeModelMenuBarIcon,
                            freeModelAutoSort: freeModelAutoSort)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }

    // MARK: - Target file access (App Sandbox)

    var hasTargetFile: Bool { fileBookmark != nil }
    var hasCodexFile: Bool { codexFileBookmark != nil }

    /// Есть ли хотя бы одна включённая и выбранная цель для записи ключа.
    var hasAnyActiveTarget: Bool {
        (claudeEnabled && hasTargetFile) || (codexEnabled && hasCodexFile)
    }

    /// Stores a security-scoped bookmark for the user-selected Claude target file
    /// so the app can keep accessing it across launches under App Sandbox.
    func setTargetFile(_ url: URL) {
        do {
            fileBookmark = try url.bookmarkData(options: [.withSecurityScope],
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
            filePath = url.path
            lastError = nil
            save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Stores a security-scoped bookmark for the user-selected Codex target file.
    func setCodexFile(_ url: URL) {
        do {
            codexFileBookmark = try url.bookmarkData(options: [.withSecurityScope],
                                                     includingResourceValuesForKeys: nil,
                                                     relativeTo: nil)
            codexFilePath = url.path
            lastError = nil
            save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Resolves the Claude bookmark, opens security-scoped access, runs `body`,
    /// then releases access. Refreshes a stale bookmark in place.
    func withTargetAccess<T>(_ body: (URL) throws -> T) throws -> T {
        try withAccess(fileBookmark) { fresh, path in
            self.fileBookmark = fresh
            self.filePath = path
        } body: { try body($0) }
    }

    /// Resolves the Codex bookmark, opens security-scoped access, runs `body`,
    /// then releases access. Refreshes a stale bookmark in place.
    func withCodexAccess<T>(_ body: (URL) throws -> T) throws -> T {
        try withAccess(codexFileBookmark) { fresh, path in
            self.codexFileBookmark = fresh
            self.codexFilePath = path
        } body: { try body($0) }
    }

    /// Общая логика доступа к security-scoped файлу: резолвит bookmark, открывает
    /// доступ, выполняет `body`, освобождает доступ. Устаревший bookmark обновляет
    /// через `refresh(freshBookmark, path)`.
    private func withAccess<T>(_ bookmark: Data?,
                               refresh: (Data, String) -> Void,
                               body: (URL) throws -> T) throws -> T {
        guard let bookmark else { throw RotationError.noFileSelected }

        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmark,
                          options: [.withSecurityScope],
                          relativeTo: nil,
                          bookmarkDataIsStale: &stale)
        } catch {
            throw RotationError.accessDenied(error.localizedDescription)
        }

        guard url.startAccessingSecurityScopedResource() else {
            throw RotationError.accessDenied(url.path)
        }
        defer { url.stopAccessingSecurityScopedResource() }

        if stale,
           let fresh = try? url.bookmarkData(options: [.withSecurityScope],
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil) {
            refresh(fresh, url.path)
            save()
        }

        return try body(url)
    }

    // MARK: - CRUD

    func addKey() {
        keys.append(APIKey(name: "New Key"))
        save()
    }

    func add(_ key: APIKey) {
        keys.append(key)
        save()
        if key.category == .freeModel { refreshUsage(for: key) }
    }

    func updateKey(_ key: APIKey) {
        guard let idx = keys.firstIndex(where: { $0.id == key.id }) else { return }
        let tokenChanged = keys[idx].usageToken != key.usageToken
        keys[idx] = key
        save()
        // Подтянуть лимиты, если токен появился/сменился или данных ещё нет.
        if key.category == .freeModel, tokenChanged || usageStates[key.id] == nil {
            refreshUsage(for: key)
        }
    }

    func deleteKey(_ key: APIKey) {
        keys.removeAll { $0.id == key.id }
        if currentKeyID == key.id { currentKeyID = nil }
        usageStates.removeValue(forKey: key.id)
        save()
    }

    func deleteKeys(at offsets: IndexSet) {
        let removed = offsets.map { keys[$0].id }
        keys.remove(atOffsets: offsets)
        if let current = currentKeyID, removed.contains(current) {
            currentKeyID = nil
        }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        keys.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Categories (FreeModel)

    /// Ключи одной категории в порядке их следования в общем списке.
    func keys(in category: KeyCategory) -> [APIKey] {
        keys.filter { $0.category == category }
    }

    /// FreeModel-ключи в порядке отображения в таблице: сначала по заполнению
    /// 5-часового окна (0% → 100%), при равенстве — по моменту сброса
    /// 7-дневного окна (чей сброс раньше, тот выше); ключи без загруженных
    /// лимитов — после них в исходном порядке, а полностью исчерпанные
    /// (любое окно на 100%) — в самом конце (тай-брейк по исходному индексу
    /// делает сортировку стабильной).
    func sortedFreeModelKeys() -> [APIKey] {
        // Ранг группы: 0 — рабочие с данными, 1 — без данных, 2 — полностью
        // исчерпанные (любое окно ≥ 100%, независимо от порога переключения).
        func rank(_ usage: FreeModelUsage?) -> Int {
            guard let usage else { return 1 }
            return usage.window5h.fraction >= 1 || usage.windowWeek.fraction >= 1 ? 2 : 0
        }
        return keys(in: .freeModel).enumerated().sorted { a, b in
            let ua = usageStates[a.element.id]?.usage
            let ub = usageStates[b.element.id]?.usage
            let ra = rank(ua), rb = rank(ub)
            if ra != rb { return ra < rb }
            if let ua, let ub {
                if ua.window5h.fraction != ub.window5h.fraction {
                    return ua.window5h.fraction < ub.window5h.fraction
                }
                if ua.windowWeek.resetsAt != ub.windowWeek.resetsAt {
                    return ua.windowWeek.resetsAt < ub.windowWeek.resetsAt
                }
            }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// FreeModel-ключи в порядке отображения таблицы: автосортировка по
    /// лимитам (`sortedFreeModelKeys`), если включена настройка
    /// `freeModelAutoSort`, иначе — ручной порядок общего списка. Этот же
    /// порядок использует автопереключение с исчерпанного ключа
    /// (`RotationManager.switchFromExhaustedKey`).
    func displayedFreeModelKeys() -> [APIKey] {
        freeModelAutoSort ? sortedFreeModelKeys() : keys(in: .freeModel)
    }

    /// Переставляет ключи внутри категории. `source`/`destination` — индексы
    /// отфильтрованного по категории списка; глобальные позиции ключей других
    /// категорий не меняются (переставляемые ключи занимают те же слоты).
    func move(in category: KeyCategory, from source: IndexSet, to destination: Int) {
        let indices = keys.indices.filter { keys[$0].category == category }
        var subset = indices.map { keys[$0] }
        subset.move(fromOffsets: source, toOffset: destination)
        for (pos, idx) in indices.enumerated() { keys[idx] = subset[pos] }
        save()
    }

    /// Base URL, который реально будет записан в файл для данного ключа:
    /// собственный baseURL ключа, а если он пуст у FreeModel-ключа — общий
    /// `freeModelBaseURL` категории.
    func effectiveBaseURL(for key: APIKey) -> String {
        let own = key.baseURL.trimmingCharacters(in: .whitespaces)
        if !own.isEmpty { return own }
        if key.category == .freeModel {
            return freeModelBaseURL.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    // MARK: - FreeModel usage (окна лимитов 5 ч / 7 дн)

    /// Опрос лимитов FreeModel: сразу при запуске, далее по таймеру-тикеру
    /// (каждые 30 секунд) с разными интервалами по группам: аккаунт активного
    /// ключа — раз в `freeModelActiveRefreshMinutes`, остальные — раз в
    /// `freeModelOthersRefreshMinutes`. Автообновление можно выключить
    /// настройкой `freeModelAutoRefresh` (тикер продолжает идти и подхватит
    /// включение без перезапуска). Результаты — в `usageStates`.
    private func startUsageAutoRefresh() {
        if freeModelAutoRefresh { refreshAllUsage() }
        usageTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.autoRefreshUsageTick() }
        }
    }

    /// Тик автообновления: запускает только «просроченные» группы токенов.
    /// Интервалы — из настроек FreeModel (активный аккаунт / остальные).
    private func autoRefreshUsageTick() {
        guard freeModelAutoRefresh else { return }
        let now = Date()
        for (token, ids) in usageTokenGroups {
            let isActiveGroup = currentKeyID.map(ids.contains) ?? false
            let minutes = isActiveGroup ? freeModelActiveRefreshMinutes
                                        : freeModelOthersRefreshMinutes
            let interval = TimeInterval(max(1, minutes) * 60)
            if let last = usageFetchedAt[token],
               now.timeIntervalSince(last) < interval { continue }
            fetchUsage(token: token, keyIDs: ids)
        }
    }

    /// FreeModel-ключи с заданным токеном сессии, сгруппированные по токену:
    /// у ключей одного аккаунта токен общий, запрос делается один на аккаунт,
    /// а результат раскладывается по всем его ключам.
    private var usageTokenGroups: [String: [UUID]] {
        var groups: [String: [UUID]] = [:]
        for key in keys where key.category == .freeModel {
            let token = (key.usageToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            groups[token, default: []].append(key.id)
        }
        return groups
    }

    /// Есть ли хотя бы один FreeModel-ключ с токеном сессии (для кнопки обновления).
    var hasUsageTokens: Bool { !usageTokenGroups.isEmpty }

    /// Обновляет лимиты всех FreeModel-ключей с токеном. `minInterval` — не
    /// опрашивать токен чаще, чем раз в столько секунд (0 — принудительно).
    func refreshAllUsage(minInterval: TimeInterval = 0) {
        let now = Date()
        for (token, ids) in usageTokenGroups {
            if minInterval > 0, let last = usageFetchedAt[token],
               now.timeIntervalSince(last) < minInterval { continue }
            fetchUsage(token: token, keyIDs: ids)
        }
    }

    /// Обновляет лимиты для ключа (и всех ключей с тем же токеном сессии).
    func refreshUsage(for key: APIKey) {
        let token = (key.usageToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        fetchUsage(token: token, keyIDs: usageTokenGroups[token] ?? [key.id])
    }

    /// Обновляет лимиты всех аккаунтов по очереди: следующий запрос уходит
    /// через `freeModelSequentialPauseSeconds` секунд после получения ответа
    /// на предыдущий (щадящий режим, кнопка «Обновить все» внизу списка
    /// FreeModel).
    func refreshAllUsageSequentially() {
        guard !usageRefreshingAll else { return }
        let groups = usageTokenGroups
        guard !groups.isEmpty else { return }
        usageRefreshingAll = true
        let pause = UInt64(max(0, freeModelSequentialPauseSeconds)) * 1_000_000_000
        Task { [weak self] in
            var first = true
            for (token, ids) in groups {
                if !first, pause > 0 { try? await Task.sleep(nanoseconds: pause) }
                first = false
                await self?.performUsageFetch(token: token, keyIDs: ids)
            }
            self?.usageRefreshingAll = false
        }
    }

    private func fetchUsage(token: String, keyIDs: [UUID]) {
        Task { [weak self] in await self?.performUsageFetch(token: token, keyIDs: keyIDs) }
    }

    private func performUsageFetch(token: String, keyIDs: [UUID]) async {
        guard !usageTokensInFlight.contains(token) else { return }
        usageTokensInFlight.insert(token)
        // Спиннер — только там, где данных ещё нет; обновление идёт без мерцания.
        for id in keyIDs where usageStates[id]?.usage == nil {
            usageStates[id] = .loading
        }
        // Прокси для запроса: первый прокси, привязанный к любому ключу группы
        // (у ключей одного аккаунта токен общий). Глобальный переключатель
        // `proxiesEnabled` намеренно игнорируется — он управляет только записью
        // прокси в целевой файл. При недоступности прокси запрос уйдёт напрямую
        // (фолбэк внутри fetchFreeModelUsage).
        let proxy = keyIDs.lazy
            .compactMap { [self] id in keys.first { $0.id == id } }
            .compactMap { [self] in assignedProxy(for: $0) }
            .first
        let result = await fetchFreeModelUsage(sessionToken: token, proxy: proxy)
        usageTokensInFlight.remove(token)
        usageFetchedAt[token] = Date()
        let state: FreeModelUsageState
        switch result {
        case .ok(let usage):
            state = .loaded(usage, at: Date())
        case .unauthorized:
            state = .failure(tr("Токен сессии недействителен или истёк",
                                "Session token is invalid or expired"))
        case .httpError(let code):
            state = .failure("HTTP \(code)")
        case .error(let message):
            state = .failure(message)
        }
        // Было ли какое-либо окно активного ключа исчерпано по прежним данным —
        // фиксируем до перезаписи состояний, чтобы поймать именно переход.
        // Порог «исчерпания» настраивается (freeModelSwitchThresholdPercent);
        // исчерпание — достижение порога ЛЮБЫМ из окон (5 ч или 7 дн).
        let wasExhausted = currentKeyID.flatMap { usageStates[$0]?.usage }
            .map(isUsageExhausted) ?? false
        for id in keyIDs { usageStates[id] = state }
        // Если активный ключ входит в эту группу и одно из его окон только
        // что дошло до порога — звук (если включён) и переключение на верхний
        // неисчерпанный ключ таблицы FreeModel (если включено автопереключение,
        // см. RotationManager.switchFromExhaustedKey). Срабатывает только на
        // переходе через порог: когда исчерпаны все ключи и выбранный тоже за
        // порогом, повторного переключения на каждом опросе не будет.
        if let activeID = currentKeyID, keyIDs.contains(activeID),
           let usage = state.usage, isUsageExhausted(usage), !wasExhausted {
            if freeModelSoundEnabled { playExhaustSound() }
            if freeModelAutoSwitch { onActiveKeyExhausted?() }
        }
    }

    /// Исчерпаны ли лимиты: любое из окон (5 ч или 7 дн) достигло порога
    /// `freeModelSwitchThresholdPercent`. Используется детектом исчерпания и
    /// фильтром кандидатов автопереключения.
    func isUsageExhausted(_ usage: FreeModelUsage) -> Bool {
        let threshold = Double(min(max(freeModelSwitchThresholdPercent, 1), 100)) / 100
        return usage.window5h.fraction >= threshold
            || usage.windowWeek.fraction >= threshold
    }

    /// Исчерпан ли ключ по загруженным лимитам (`isUsageExhausted`); без
    /// загруженных данных считается неисчерпанным.
    func isKeyExhausted(_ id: UUID) -> Bool {
        usageStates[id]?.usage.map(isUsageExhausted) ?? false
    }

    /// Играет системный звук исчерпания (настройка `freeModelSoundName`);
    /// если звук с таким именем недоступен — системный beep. Используется при
    /// детекте исчерпания и для прослушивания в настройках.
    func playExhaustSound() {
        if let sound = NSSound(named: freeModelSoundName) { sound.play() } else { NSSound.beep() }
    }

    // MARK: - Proxy CRUD

    func addProxy() {
        proxies.append(Proxy(name: "New Proxy"))
        save()
    }

    func updateProxy(_ proxy: Proxy) {
        guard let idx = proxies.firstIndex(where: { $0.id == proxy.id }) else { return }
        proxies[idx] = proxy
        save()
    }

    func deleteProxy(_ proxy: Proxy) {
        proxies.removeAll { $0.id == proxy.id }
        // Снимаем привязку этого прокси со всех ключей.
        for idx in keys.indices where keys[idx].proxyID == proxy.id {
            keys[idx].proxyID = nil
        }
        save()
    }

    func moveProxy(from source: IndexSet, to destination: Int) {
        proxies.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Прокси, который будет применён к ключу при ротации: учитывает глобальный
    /// переключатель `proxiesEnabled`. Возвращает nil, если прокси отключены
    /// глобально, не назначены или больше не существуют.
    func proxy(for key: APIKey) -> Proxy? {
        guard proxiesEnabled else { return nil }
        return assignedProxy(for: key)
    }

    /// Прокси, привязанный к ключу, независимо от глобального переключателя
    /// (для отображения привязки в списке ключей).
    func assignedProxy(for key: APIKey) -> Proxy? {
        guard let id = key.proxyID else { return nil }
        return proxies.first { $0.id == id }
    }

    // MARK: - Key testing

    func test(_ key: APIKey) {
        let id = key.id
        let api = key.apiKey
        let base = effectiveBaseURL(for: key)
        testStates[id] = .testing
        Task { [weak self] in
            let result = await testKey(apiKey: api, baseURL: base)
            guard let self else { return }
            switch result {
            case .valid:
                self.testStates[id] = .success
            case .invalid(let code):
                self.testStates[id] = .failure("HTTP \(code)")
            case .error(let message):
                self.testStates[id] = .failure(message)
            }
        }
    }

    func testAll() {
        for key in keys { test(key) }
    }

    func testAll(in category: KeyCategory) {
        for key in keys(in: category) { test(key) }
    }

    // MARK: - Proxy testing

    func testProxy(_ proxy: Proxy) {
        let id = proxy.id
        proxyTestStates[id] = .testing
        Task { [weak self] in
            let result = await KeyRotator.testProxy(proxy)
            guard let self else { return }
            switch result {
            case .ok(let check):
                self.proxyTestStates[id] = .success(check)
            case .authFailed:
                self.proxyTestStates[id] = .failure(self.tr("Ошибка авторизации (407)", "Auth failed (407)"))
            case .httpError(let code):
                self.proxyTestStates[id] = .failure("HTTP \(code)")
            case .error(let message):
                self.proxyTestStates[id] = .failure(message)
            }
        }
    }

    func testAllProxies() {
        for proxy in proxies { testProxy(proxy) }
    }

    var enabledKeys: [APIKey] {
        keys.filter { $0.enabled }
    }

    // MARK: - Import / Export / Reset

    /// Переносимое подмножество конфигурации для экспорта/импорта. Исключает
    /// security-scoped bookmark и путь к целевому файлу: доступ к файлу
    /// специфичен для конкретной машины/пользователя и не переносится.
    private struct ExportData: Codable {
        var keys: [APIKey]
        var freeModelBaseURL: String?
        var proxies: [Proxy]
        var proxiesEnabled: Bool?
        var intervalMinutes: Int
        var startOnLaunch: Bool
        var language: AppLanguage?
        var hideFromDock: Bool?
        var freeModelAutoRefresh: Bool?
        var freeModelActiveRefreshMinutes: Int?
        var freeModelOthersRefreshMinutes: Int?
        var freeModelSequentialPauseSeconds: Int?
        var freeModelAutoSwitch: Bool?
        var freeModelSwitchThresholdPercent: Int?
        var freeModelSoundEnabled: Bool?
        var freeModelSoundName: String?
        var freeModelMenuBarIcon: Bool?
        var freeModelAutoSort: Bool?
    }

    /// Сериализует текущие настройки (ключи, прокси, интервал, автозапуск, язык)
    /// в pretty-printed JSON для сохранения в файл.
    func exportData() -> Data? {
        let export = ExportData(keys: keys,
                                freeModelBaseURL: freeModelBaseURL,
                                proxies: proxies,
                                proxiesEnabled: proxiesEnabled,
                                intervalMinutes: intervalMinutes,
                                startOnLaunch: startOnLaunch,
                                language: language,
                                hideFromDock: hideFromDock,
                                freeModelAutoRefresh: freeModelAutoRefresh,
                                freeModelActiveRefreshMinutes: freeModelActiveRefreshMinutes,
                                freeModelOthersRefreshMinutes: freeModelOthersRefreshMinutes,
                                freeModelSequentialPauseSeconds: freeModelSequentialPauseSeconds,
                                freeModelAutoSwitch: freeModelAutoSwitch,
                                freeModelSwitchThresholdPercent: freeModelSwitchThresholdPercent,
                                freeModelSoundEnabled: freeModelSoundEnabled,
                                freeModelSoundName: freeModelSoundName,
                                freeModelMenuBarIcon: freeModelMenuBarIcon,
                                freeModelAutoSort: freeModelAutoSort)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(export)
    }

    /// Заменяет текущие настройки данными из `data`. Привязка к целевому файлу
    /// (bookmark) не затрагивается. Возвращает `true` при успехе.
    @discardableResult
    func importData(_ data: Data) -> Bool {
        guard let imported = try? JSONDecoder().decode(ExportData.self, from: data) else {
            lastError = tr("Не удалось прочитать файл настроек", "Couldn't read the settings file")
            return false
        }
        keys = imported.keys
        freeModelBaseURL = imported.freeModelBaseURL ?? ""
        proxies = imported.proxies
        proxiesEnabled = imported.proxiesEnabled ?? true
        intervalMinutes = max(1, imported.intervalMinutes)
        startOnLaunch = imported.startOnLaunch
        language = imported.language ?? .systemDefault
        hideFromDock = imported.hideFromDock ?? false
        freeModelAutoRefresh = imported.freeModelAutoRefresh ?? true
        freeModelActiveRefreshMinutes = max(1, imported.freeModelActiveRefreshMinutes ?? 2)
        freeModelOthersRefreshMinutes = max(1, imported.freeModelOthersRefreshMinutes ?? 15)
        freeModelSequentialPauseSeconds = max(0, imported.freeModelSequentialPauseSeconds ?? 3)
        freeModelAutoSwitch = imported.freeModelAutoSwitch ?? true
        freeModelSwitchThresholdPercent = min(max(imported.freeModelSwitchThresholdPercent ?? 100, 50), 100)
        freeModelSoundEnabled = imported.freeModelSoundEnabled ?? true
        freeModelSoundName = imported.freeModelSoundName ?? "Glass"
        freeModelMenuBarIcon = imported.freeModelMenuBarIcon ?? true
        freeModelAutoSort = imported.freeModelAutoSort ?? true
        // Сбрасываем рантайм-состояние, которое могло устареть.
        currentKeyID = nil
        testStates = [:]
        proxyTestStates = [:]
        usageStates = [:]
        usageFetchedAt = [:]
        lastError = nil
        save()
        refreshAllUsage()
        return true
    }

    /// Очищает все ключи, прокси и настройки до значений по умолчанию и забывает
    /// выбранный целевой файл. Сам файл settings.json пользователя не трогается.
    func resetAll() {
        keys = []
        freeModelBaseURL = ""
        proxies = []
        proxiesEnabled = true
        intervalMinutes = 30
        startOnLaunch = false
        language = .systemDefault
        hideFromDock = false
        freeModelAutoRefresh = true
        freeModelActiveRefreshMinutes = 2
        freeModelOthersRefreshMinutes = 15
        freeModelSequentialPauseSeconds = 3
        freeModelAutoSwitch = true
        freeModelSwitchThresholdPercent = 100
        freeModelSoundEnabled = true
        freeModelSoundName = "Glass"
        freeModelMenuBarIcon = true
        freeModelAutoSort = true
        fileBookmark = nil
        filePath = ""
        claudeEnabled = true
        codexFileBookmark = nil
        codexFilePath = ""
        codexEnabled = false
        currentKeyID = nil
        testStates = [:]
        proxyTestStates = [:]
        usageStates = [:]
        usageFetchedAt = [:]
        lastError = nil
        lastRotation = nil
        save()
    }

    // MARK: - Localization

    /// Returns the string for the currently selected UI language. Reading
    /// `language` here makes any view that calls `tr` re-render when it changes.
    func tr(_ ru: String, _ en: String) -> String {
        switch language {
        case .russian: return ru
        case .english: return en
        }
    }

    var currentKey: APIKey? {
        guard let id = currentKeyID else { return nil }
        return keys.first { $0.id == id }
    }

    var currentKeyName: String? {
        currentKey?.name
    }
}
