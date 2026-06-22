//
//  KeyTester.swift
//  ClaudeRotate
//

import Foundation

enum KeyTestResult {
    case valid
    case invalid(Int)
    case error(String)
}

/// UI-facing state for a key's last validation attempt.
enum KeyTestState: Equatable {
    case testing
    case success
    case failure(String)
}

/// Validates a key by issuing `GET {baseURL}/v1/models` with the Anthropic auth
/// headers. 2xx = valid, other HTTP status = invalid (bad key / forbidden),
/// transport failure = unreachable base URL. Does not consume tokens.
nonisolated func testKey(apiKey: String, baseURL: String) async -> KeyTestResult {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return .error("Empty API key") }

    var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if base.isEmpty { base = "https://api.anthropic.com" }
    while base.hasSuffix("/") { base = String(base.dropLast()) }

    guard let url = URL(string: base + "/v1/models") else {
        return .error("Invalid base URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(key, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.timeoutInterval = 15

    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return .error("No HTTP response")
        }
        switch http.statusCode {
        case 200...299: return .valid
        default: return .invalid(http.statusCode)
        }
    } catch {
        return .error(error.localizedDescription)
    }
}
