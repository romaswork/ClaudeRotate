//
//  ProxyTester.swift
//  ClaudeRotate
//

import Foundation

/// Подробности успешной проверки прокси: задержка (ping) и страна выхода.
struct ProxyCheck: Equatable {
    var latencyMs: Int
    var countryCode: String?   // ISO-код, напр. "US"
    var ip: String?

    /// Локализованное название страны по ISO-коду (зависит от локали системы).
    var countryName: String? {
        guard let code = countryCode, !code.isEmpty else { return nil }
        return Locale.current.localizedString(forRegionCode: code)
    }

    /// Эмодзи-флаг из двухбуквенного ISO-кода страны.
    var flag: String? {
        guard let code = countryCode, code.count == 2 else { return nil }
        let base: UInt32 = 0x1F1E6 - 0x41 // смещение к Regional Indicator от 'A'
        var result = ""
        for scalar in code.uppercased().unicodeScalars {
            guard scalar.value >= 0x41, scalar.value <= 0x5A,
                  let flagScalar = UnicodeScalar(base + scalar.value) else { return nil }
            result.unicodeScalars.append(flagScalar)
        }
        return result
    }
}

enum ProxyTestResult {
    case ok(ProxyCheck)
    case authFailed
    case httpError(Int)
    case error(String)
}

/// UI-состояние последней проверки прокси.
enum ProxyTestState: Equatable {
    case testing
    case success(ProxyCheck)
    case failure(String)
}

/// Проверяет прокси, выполняя запрос к сервису геолокации через него. Это даёт
/// одновременно: факт работоспособности туннеля, задержку (ping) и страну выхода
/// (определяется по внешнему IP, который видит сервис). `407` — отклонена
/// авторизация; ошибка транспорта — прокси недоступен.
nonisolated func testProxy(_ proxy: Proxy) async -> ProxyTestResult {
    let host = proxy.host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else { return .error("Empty proxy host") }

    let portString = proxy.port.trimmingCharacters(in: .whitespacesAndNewlines)
    let port = Int(portString) ?? 8080

    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = [
        kCFNetworkProxiesHTTPEnable as String: true,
        kCFNetworkProxiesHTTPProxy as String: host,
        kCFNetworkProxiesHTTPPort as String: port,
        kCFNetworkProxiesHTTPSEnable as String: true,
        kCFNetworkProxiesHTTPSProxy as String: host,
        kCFNetworkProxiesHTTPSPort as String: port,
    ]
    config.timeoutIntervalForRequest = 15
    config.requestCachePolicy = .reloadIgnoringLocalCacheData

    let delegate = ProxyAuthDelegate(username: proxy.username, password: proxy.password)
    let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }

    // HTTPS-сервис геолокации без ключа: возвращает country_code и ip.
    guard let url = URL(string: "https://ipwho.is/?fields=success,country_code,ip") else {
        return .error("Invalid test URL")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 15

    let start = Date()
    do {
        let (data, response) = try await session.data(for: request)
        let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
        guard let http = response as? HTTPURLResponse else {
            return .error("No HTTP response")
        }
        if http.statusCode == 407 { return .authFailed }
        // Туннель установлен. Пытаемся извлечь страну/IP (необязательно).
        var countryCode: String?
        var ip: String?
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            countryCode = (json["country_code"] as? String)?.uppercased()
            ip = json["ip"] as? String
        }
        return .ok(ProxyCheck(latencyMs: latencyMs, countryCode: countryCode, ip: ip))
    } catch {
        return .error(error.localizedDescription)
    }
}

/// Делегат сессии, отвечающий на запрос basic-авторизации прокси введёнными
/// логином и паролем. Если данные неверны, авторизация отменяется (→ 407/ошибка).
private final class ProxyAuthDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let username: String
    private let password: String

    init(username: String, password: String) {
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
    }

    nonisolated func urlSession(_ session: URLSession,
                                task: URLSessionTask,
                                didReceive challenge: URLAuthenticationChallenge,
                                completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.isProxy(), !username.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Повторный запрос означает, что предыдущие данные не подошли.
        if challenge.previousFailureCount > 0 {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let credential = URLCredential(user: username, password: password, persistence: .forSession)
        completionHandler(.useCredential, credential)
    }
}
