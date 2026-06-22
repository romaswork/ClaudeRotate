//
//  APIKey.swift
//  ClaudeRotate
//

import Foundation

struct APIKey: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var apiKey: String
    var baseURL: String
    var enabled: Bool
    /// Привязанный прокси (если назначен). При ротации его URL пишется в env.
    var proxyID: UUID?

    init(id: UUID = UUID(),
         name: String = "",
         apiKey: String = "",
         baseURL: String = "",
         enabled: Bool = true,
         proxyID: UUID? = nil) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.enabled = enabled
        self.proxyID = proxyID
    }
}
