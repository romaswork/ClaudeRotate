//
//  APIKey.swift
//  ClaudeRotate
//

import Foundation

/// Категория ключа: обычный или полученный через сервис FreeModel.
/// FreeModel-ключи хранятся в отдельном подменю вкладки «Ключи» и по умолчанию
/// используют общий Base URL категории (`AppStore.freeModelBaseURL`), если
/// у ключа не задан собственный.
enum KeyCategory: String, Codable, CaseIterable {
    case general
    case freeModel

    // Терпимо к неизвестным значениям из старых/чужих конфигов.
    init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        self = KeyCategory(rawValue: raw ?? "") ?? .general
    }
}

struct APIKey: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var apiKey: String
    var baseURL: String
    var enabled: Bool
    /// Привязанный прокси (если назначен). При ротации его URL пишется в env.
    var proxyID: UUID?
    var category: KeyCategory
    /// Токен сессии дашборда FreeModel (значение cookie `bm_session`).
    /// Нужен только для показа окон лимитов (5 ч / 7 дн) в списке ключей;
    /// в целевой файл не записывается.
    var usageToken: String?

    init(id: UUID = UUID(),
         name: String = "",
         apiKey: String = "",
         baseURL: String = "",
         enabled: Bool = true,
         proxyID: UUID? = nil,
         category: KeyCategory = .general,
         usageToken: String? = nil) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.enabled = enabled
        self.proxyID = proxyID
        self.category = category
        self.usageToken = usageToken
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, apiKey, baseURL, enabled, proxyID, category, usageToken
    }

    // Кастомный декодер: конфиги, записанные до появления категорий, не содержат
    // поля `category` — такие ключи считаются обычными.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        apiKey = try c.decode(String.self, forKey: .apiKey)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        proxyID = try c.decodeIfPresent(UUID.self, forKey: .proxyID)
        category = try c.decodeIfPresent(KeyCategory.self, forKey: .category) ?? .general
        usageToken = try c.decodeIfPresent(String.self, forKey: .usageToken)
    }
}
