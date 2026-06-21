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
    @Published var filePath: String = ""
    @Published var intervalMinutes: Int = 30
    @Published var startOnLaunch: Bool = false

    // Transient runtime state (not persisted)
    @Published var isRunning: Bool = false
    @Published var currentKeyID: UUID?
    @Published var lastError: String?
    @Published var lastRotation: Date?

    // Transient per-key validation results (not persisted)
    @Published var testStates: [UUID: KeyTestState] = [:]

    private var isLoading = false

    // MARK: - Persistence

    private struct Config: Codable {
        var keys: [APIKey]
        var filePath: String
        var intervalMinutes: Int
        var startOnLaunch: Bool
    }

    private static var configURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ClaudeRotate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static let defaultFilePath = "~/.claude/settings.json"

    init() {
        load()
        if filePath.isEmpty {
            filePath = Self.defaultFilePath
        }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: Self.configURL),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return
        }
        keys = config.keys
        filePath = config.filePath
        intervalMinutes = max(1, config.intervalMinutes)
        startOnLaunch = config.startOnLaunch
    }

    func save() {
        guard !isLoading else { return }
        let config = Config(keys: keys,
                            filePath: filePath,
                            intervalMinutes: intervalMinutes,
                            startOnLaunch: startOnLaunch)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
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

    var enabledKeys: [APIKey] {
        keys.filter { $0.enabled }
    }

    var currentKeyName: String? {
        guard let id = currentKeyID else { return nil }
        return keys.first { $0.id == id }?.name
    }
}
