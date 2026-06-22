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
    @Published var proxies: [Proxy] = []
    // Display-only path of the selected target file (resolved from the bookmark).
    // Under App Sandbox actual file access goes through `fileBookmark`, NOT this.
    @Published var filePath: String = ""
    @Published var intervalMinutes: Int = 30
    @Published var startOnLaunch: Bool = false
    @Published var language: AppLanguage = .systemDefault

    // Security-scoped bookmark to the user-selected target file. Persisted; used
    // to regain access to the file across launches under App Sandbox. Not shown
    // in the UI directly (the readable path lives in `filePath`).
    private var fileBookmark: Data?

    // Transient runtime state (not persisted)
    @Published var isRunning: Bool = false
    @Published var currentKeyID: UUID?
    @Published var lastError: String?
    @Published var lastRotation: Date?

    // Transient per-key validation results (not persisted)
    @Published var testStates: [UUID: KeyTestState] = [:]

    // Transient per-proxy validation results (not persisted)
    @Published var proxyTestStates: [UUID: ProxyTestState] = [:]

    private var isLoading = false

    // MARK: - Persistence

    private struct Config: Codable {
        var keys: [APIKey]
        var proxies: [Proxy]?
        var filePath: String
        var fileBookmark: Data?
        var intervalMinutes: Int
        var startOnLaunch: Bool
        var currentKeyID: UUID?
        var language: AppLanguage?
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
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: Self.configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return
        }
        keys = config.keys
        proxies = config.proxies ?? []
        filePath = config.filePath
        fileBookmark = config.fileBookmark
        intervalMinutes = max(1, config.intervalMinutes)
        startOnLaunch = config.startOnLaunch
        language = config.language ?? .systemDefault
        // Restore the last active key only if it still exists.
        if let id = config.currentKeyID, keys.contains(where: { $0.id == id }) {
            currentKeyID = id
        }
    }

    func save() {
        guard !isLoading else { return }
        let config = Config(keys: keys,
                            proxies: proxies,
                            filePath: filePath,
                            fileBookmark: fileBookmark,
                            intervalMinutes: intervalMinutes,
                            startOnLaunch: startOnLaunch,
                            currentKeyID: currentKeyID,
                            language: language)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }

    // MARK: - Target file access (App Sandbox)

    var hasTargetFile: Bool { fileBookmark != nil }

    /// Stores a security-scoped bookmark for the user-selected target file so the
    /// app can keep accessing it across launches under App Sandbox.
    func setTargetFile(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope],
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
            fileBookmark = bookmark
            filePath = url.path
            lastError = nil
            save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Resolves the bookmark, opens security-scoped access, runs `body` with the
    /// resolved URL, then releases access. Refreshes a stale bookmark in place.
    func withTargetAccess<T>(_ body: (URL) throws -> T) throws -> T {
        guard let bookmark = fileBookmark else { throw RotationError.noFileSelected }

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
            fileBookmark = fresh
            filePath = url.path
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
    }

    func updateKey(_ key: APIKey) {
        guard let idx = keys.firstIndex(where: { $0.id == key.id }) else { return }
        keys[idx] = key
        save()
    }

    func deleteKey(_ key: APIKey) {
        keys.removeAll { $0.id == key.id }
        if currentKeyID == key.id { currentKeyID = nil }
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

    /// Возвращает прокси, привязанный к ключу (если назначен и существует).
    func proxy(for key: APIKey) -> Proxy? {
        guard let id = key.proxyID else { return nil }
        return proxies.first { $0.id == id }
    }

    // MARK: - Key testing

    func test(_ key: APIKey) {
        let id = key.id
        let api = key.apiKey
        let base = key.baseURL
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
        var proxies: [Proxy]
        var intervalMinutes: Int
        var startOnLaunch: Bool
        var language: AppLanguage?
    }

    /// Сериализует текущие настройки (ключи, прокси, интервал, автозапуск, язык)
    /// в pretty-printed JSON для сохранения в файл.
    func exportData() -> Data? {
        let export = ExportData(keys: keys,
                                proxies: proxies,
                                intervalMinutes: intervalMinutes,
                                startOnLaunch: startOnLaunch,
                                language: language)
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
        proxies = imported.proxies
        intervalMinutes = max(1, imported.intervalMinutes)
        startOnLaunch = imported.startOnLaunch
        language = imported.language ?? .systemDefault
        // Сбрасываем рантайм-состояние, которое могло устареть.
        currentKeyID = nil
        testStates = [:]
        proxyTestStates = [:]
        lastError = nil
        save()
        return true
    }

    /// Очищает все ключи, прокси и настройки до значений по умолчанию и забывает
    /// выбранный целевой файл. Сам файл settings.json пользователя не трогается.
    func resetAll() {
        keys = []
        proxies = []
        intervalMinutes = 30
        startOnLaunch = false
        language = .systemDefault
        fileBookmark = nil
        filePath = ""
        currentKeyID = nil
        testStates = [:]
        proxyTestStates = [:]
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
