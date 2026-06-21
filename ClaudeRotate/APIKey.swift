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

    init(id: UUID = UUID(),
         name: String = "",
         apiKey: String = "",
         baseURL: String = "",
         enabled: Bool = true) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.enabled = enabled
    }
}
