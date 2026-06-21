//
//  RotationEngine.swift
//  ClaudeRotate
//

import Foundation
import Combine

enum RotationError: LocalizedError {
    case noFilePath
    case fileNotFound(String)
    case invalidJSON(String)
    case rootNotObject
    case noEnabledKeys

    var errorDescription: String? {
        switch self {
        case .noFilePath:
            return "No JSON file path is configured in Settings."
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidJSON(let path):
            return "Could not parse JSON at: \(path)"
        case .rootNotObject:
            return "The JSON file's root is not an object."
        case .noEnabledKeys:
            return "No enabled keys to rotate."
        }
    }
}

/// Reads the target JSON file, mutates only `apiKeyHelper`,
/// `env.ANTHROPIC_API_KEY` and `env.ANTHROPIC_BASE_URL`, then writes it back.
/// All other keys and values are preserved.
func writeKey(_ key: APIKey, toPath path: String) throws {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw RotationError.noFilePath }

    let expanded = (trimmed as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded)

    guard FileManager.default.fileExists(atPath: expanded) else {
        throw RotationError.fileNotFound(expanded)
    }

    let data = try Data(contentsOf: url)
    let parsed = try? JSONSerialization.jsonObject(with: data, options: [])
    guard let parsed else { throw RotationError.invalidJSON(expanded) }
    guard var root = parsed as? [String: Any] else { throw RotationError.rootNotObject }

    root["apiKeyHelper"] = "echo '\(key.apiKey)'"

    var env = root["env"] as? [String: Any] ?? [:]
    env["ANTHROPIC_API_KEY"] = key.apiKey
    env["ANTHROPIC_BASE_URL"] = key.baseURL
    root["env"] = env

    let output = try JSONSerialization.data(withJSONObject: root,
                                            options: [.prettyPrinted, .sortedKeys])
    // JSONSerialization escapes forward slashes (e.g. "https:\/\/..."); restore them
    // so URLs stay readable and preserved fields keep their original look.
    let text = String(decoding: output, as: UTF8.self)
        .replacingOccurrences(of: "\\/", with: "/")
    try Data(text.utf8).write(to: url, options: .atomic)
}

@MainActor
final class RotationManager: ObservableObject {
    nonisolated let objectWillChange = ObservableObjectPublisher()
    private let store: AppStore
    private var timer: Timer?

    init(store: AppStore) {
        self.store = store
    }

    /// Starts the rotation timer. When `immediate` is true the next key is applied
    /// right away; pass false to keep the currently active key for the first
    /// interval (e.g. when a restored key was just applied on launch).
    func start(immediate: Bool = true) {
        stop()
        store.isRunning = true
        let interval = TimeInterval(max(1, store.intervalMinutes) * 60)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.rotateNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if immediate {
            rotateNow()
        }
    }

    /// Writes the last active key (restored from config) to the target file.
    /// Returns true if a key was applied. Used on launch so the file immediately
    /// reflects the key that was active in the previous session.
    @discardableResult
    func applyCurrentKey() -> Bool {
        guard let key = store.currentKey else { return false }
        apply(key)
        return true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        store.isRunning = false
    }

    func restartIfRunning() {
        if store.isRunning { start() }
    }

    /// Writes a specific key to the target file immediately and marks it active.
    /// Works regardless of whether rotation is running or paused; does not touch
    /// the timer. If rotation is running, the next tick continues after this key.
    func apply(_ key: APIKey) {
        do {
            try writeKey(key, toPath: store.filePath)
            store.currentKeyID = key.id
            store.lastRotation = Date()
            store.lastError = nil
            store.save()
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    /// Applies the next enabled key (wrapping around) to the target file.
    func rotateNow() {
        rotate(by: 1)
    }

    /// Applies the previous enabled key (wrapping around) to the target file.
    func rotatePrevious() {
        rotate(by: -1)
    }

    /// Applies the enabled key `offset` positions away from the current one
    /// (wrapping around). If no key is active yet, applies the first enabled key.
    private func rotate(by offset: Int) {
        let enabled = store.enabledKeys
        guard !enabled.isEmpty else {
            store.lastError = RotationError.noEnabledKeys.localizedDescription
            return
        }

        let index: Int
        if let current = store.currentKeyID,
           let idx = enabled.firstIndex(where: { $0.id == current }) {
            index = ((idx + offset) % enabled.count + enabled.count) % enabled.count
        } else {
            index = 0
        }
        let key = enabled[index]

        do {
            try writeKey(key, toPath: store.filePath)
            store.currentKeyID = key.id
            store.lastRotation = Date()
            store.lastError = nil
            store.save()
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}
