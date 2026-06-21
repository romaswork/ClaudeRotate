//
//  AppLanguage.swift
//  ClaudeRotate
//

import Foundation

/// UI language selectable in Settings. Persisted in config; applied at runtime
/// via `AppStore.tr(_:_:)` so switching takes effect immediately without restart.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case russian = "ru"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        }
    }

    /// Default language based on the system locale (Russian for ru-* systems).
    static var systemDefault: AppLanguage {
        let code = Locale.current.language.languageCode?.identifier
        return code == "ru" ? .russian : .english
    }
}
