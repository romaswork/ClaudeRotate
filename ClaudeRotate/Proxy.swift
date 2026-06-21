//
//  Proxy.swift
//  ClaudeRotate
//

import Foundation

/// Прокси-сервер, который можно привязать к ключу. При ротации URL прокси
/// записывается в `env.HTTPS_PROXY`/`env.HTTP_PROXY` целевого файла.
/// Авторизация необязательна: если `username`/`password` пусты, URL строится
/// без них.
struct Proxy: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var host: String
    var port: String
    var username: String
    var password: String

    init(id: UUID = UUID(),
         name: String = "",
         host: String = "",
         port: String = "",
         username: String = "",
         password: String = "") {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    /// Полный URL прокси для подстановки в переменные окружения.
    /// Формат: `http://[user:pass@]host[:port]`. Логин и пароль
    /// percent-кодируются. Возвращает nil, если хост пуст.
    var url: String? {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return nil }

        var authority = ""
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty {
            let encUser = user.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? user
            let encPass = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
            authority = password.isEmpty ? "\(encUser)@" : "\(encUser):\(encPass)@"
        }

        let p = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let portPart = p.isEmpty ? "" : ":\(p)"
        return "http://\(authority)\(h)\(portPart)"
    }

    /// Человекочитаемое имя для списков и подписей.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = port.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.isEmpty { return "—" }
        return p.isEmpty ? h : "\(h):\(p)"
    }
}
