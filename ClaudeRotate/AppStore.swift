//
//  AppStore.swift
//  ClaudeRotate
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    // Persisted configuration
    @Published var keys: [APIKey] = [] { didSet { save() } }
    @Published var filePath: String = "" { didSet { save() } }
    @Published var intervalMinutes: Int = 30 { didSet { save() } }
    @Published var startOnLaunch: Bool = false { didSet { save() } }

    // Transient runtime state (not persisted)
    @Published var isRunning: Bool = false
    @Published var currentKeyID: UUID?
    @Published var lastError: String?
    @Published var lastRotation: Date?

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
        filePath = config.filePath
        intervalMinutes = max(1, config.intervalMinutes)
        startOnLaunch = config.startOnLaunch
    }

    private func save() {
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
    }

    func updateKey(_ key: APIKey) {
        guard let idx = keys.firstIndex(where: { $0.id == key.id }) else { return }
        keys[idx] = key
    }

    func deleteKey(_ key: APIKey) {
        keys.removeAll { $0.id == key.id }
        if currentKeyID == key.id { currentKeyID = nil }
    }

    func deleteKeys(at offsets: IndexSet) {
        let removed = offsets.map { keys[$0].id }
        keys.remove(atOffsets: offsets)
        if let current = currentKeyID, removed.contains(current) {
            currentKeyID = nil
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        keys.move(fromOffsets: source, toOffset: destination)
    }

    var enabledKeys: [APIKey] {
        keys.filter { $0.enabled }
    }

    var currentKeyName: String? {
        guard let id = currentKeyID else { return nil }
        return keys.first { $0.id == id }?.name
    }
}
