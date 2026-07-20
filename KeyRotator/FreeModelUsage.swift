//
//  FreeModelUsage.swift
//  ClaudeRotate
//

import Foundation
import SwiftUI

/// Использование лимитов аккаунта FreeModel: два скользящих окна — 5 часов и
/// 7 дней. Источник — `GET https://freemodel.dev/api/usage` с cookie
/// `bm_session` (токен сессии дашборда). По API-ключу (`fe_oa_…`) эти данные
/// недоступны: эндпоинт авторизуется только сессией, а `cc.freemodel.dev`
/// не отдаёт rate-limit-заголовков в ответах.
struct FreeModelUsage: Decodable, Equatable {
    struct Window: Decodable, Equatable {
        /// Израсходовано, в центах доллара.
        var usedCents: Int
        /// Лимит окна, в центах доллара.
        var limitCents: Int
        /// Момент сброса окна (unix-секунды).
        var resetsAt: TimeInterval

        /// Доля израсходованного лимита, 0…1.
        var fraction: Double {
            guard limitCents > 0 else { return 0 }
            return min(1, max(0, Double(usedCents) / Double(limitCents)))
        }

        var resetDate: Date { Date(timeIntervalSince1970: resetsAt) }
    }

    var window5h: Window
    var windowWeek: Window
}

extension FreeModelUsage.Window {
    /// Цвет заполнения окна по четвертям: <25% — зелёный, 25–50% — жёлтый,
    /// 50–75% — оранжевый, ≥75% — красный. Единый для индикаторов в списке
    /// FreeModel и окраски иконки в меню-баре.
    var tint: Color {
        switch fraction {
        case ..<0.25: return .green
        case ..<0.50: return .yellow
        case ..<0.75: return .orange
        default:      return .red
        }
    }
}

enum FreeModelUsageResult {
    case ok(FreeModelUsage)
    /// 401/403 — токен сессии истёк или неверен.
    case unauthorized
    case httpError(Int)
    case error(String)
}

/// UI-состояние загрузки лимитов для строк списка FreeModel.
enum FreeModelUsageState: Equatable {
    case loading
    case loaded(FreeModelUsage, at: Date)
    case failure(String)

    var usage: FreeModelUsage? {
        if case .loaded(let usage, _) = self { return usage }
        return nil
    }
}

/// Запрашивает использование лимитов по токену сессии дашборда (`bm_session`).
/// Cookie ставится вручную в отдельной эфемерной сессии без автоматических
/// cookie, чтобы токены разных аккаунтов не смешивались между запросами.
/// Если передан `proxy` (прокси, привязанный к ключу аккаунта), запрос сначала
/// идёт через него; если через прокси не удалось (транспортная ошибка, отказ
/// авторизации прокси и т.п.) — повторяется напрямую. Осмысленные ответы самого
/// сервиса (`ok` и `unauthorized` — истёкший токен) напрямую не перепроверяются.
nonisolated func fetchFreeModelUsage(sessionToken: String, proxy: Proxy? = nil) async -> FreeModelUsageResult {
    let token = sessionToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { return .error("Empty session token") }

    if let proxy {
        let viaProxy = await fetchFreeModelUsageAttempt(token: token, proxy: proxy)
        switch viaProxy {
        case .ok, .unauthorized:
            return viaProxy
        case .httpError, .error:
            break // прокси не помог — пробуем напрямую
        }
    }
    return await fetchFreeModelUsageAttempt(token: token, proxy: nil)
}

/// Одна попытка запроса лимитов: напрямую (`proxy == nil`) или через прокси
/// (авторизация прокси — через `ProxyAuthDelegate`, общий с проверкой прокси).
private nonisolated func fetchFreeModelUsageAttempt(token: String, proxy: Proxy?) async -> FreeModelUsageResult {
    guard let url = URL(string: "https://freemodel.dev/api/usage") else {
        return .error("Invalid URL")
    }

    var request = URLRequest(url: url)
    request.setValue("bm_session=\(token)", forHTTPHeaderField: "Cookie")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 20

    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.httpCookieAcceptPolicy = .never

    var delegate: URLSessionTaskDelegate?
    if let proxy {
        let host = proxy.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return .error("Empty proxy host") }
        let port = Int(proxy.port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8080
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: host,
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: host,
            kCFNetworkProxiesHTTPSPort as String: port,
        ]
        // Через прокси ждём меньше, чтобы фолбэк напрямую не затягивался.
        config.timeoutIntervalForRequest = 15
        delegate = ProxyAuthDelegate(username: proxy.username, password: proxy.password)
    }
    let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }

    do {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return .error("No HTTP response")
        }
        switch http.statusCode {
        case 200...299:
            guard let usage = try? JSONDecoder().decode(FreeModelUsage.self, from: data) else {
                return .error("Bad response format")
            }
            return .ok(usage)
        case 401, 403:
            return .unauthorized
        default:
            return .httpError(http.statusCode)
        }
    } catch {
        return .error(error.localizedDescription)
    }
}
