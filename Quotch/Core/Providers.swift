import Foundation

protocol UsageProvider {
    var provider: Provider { get }
    func fetch() async -> Result<ProviderSnapshot, ProviderError>
}

enum HTTP {

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func getJSON(url: URL, headers: [String: String]) async -> Result<(Any, Data), ProviderError> {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.transport("No HTTP response"))
            }

            switch http.statusCode {
            case 200...299:
                guard let object = try? JSONSerialization.jsonObject(with: data) else {
                    let preview = String(data: data.prefix(200), encoding: .utf8) ?? ""
                    return .failure(.badPayload("body was not JSON — \(preview)"))
                }
                return .success((object, data))
            case 401, 403:
                return .failure(.unauthorized)
            case 429:
                return .failure(.rateLimited)
            default:
                let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
                return .failure(.httpStatus(http.statusCode, body))
            }
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }
}

struct ClaudeUsageProvider: UsageProvider {
    let provider: Provider = .claude

    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetch() async -> Result<ProviderSnapshot, ProviderError> {
        let credentials: BearerCredentials
        switch CredentialsLoader.claude() {
        case .success(let value): credentials = value
        case .failure(let error): return .failure(error)
        }

        let headers = [
            "Authorization": "Bearer \(credentials.accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
            "anthropic-version": "2023-06-01",
            "Accept": "application/json",
            "User-Agent": AppInfo.userAgent
        ]

        switch await HTTP.getJSON(url: endpoint, headers: headers) {
        case .failure(let error):
            return .failure(error)
        case .success(let (root, _)):
            let windows = JSONScan.windows(in: root)
            guard !windows.isEmpty else {
                return .failure(.badPayload("no quota fields found in the response"))
            }
            let limitReached = windows.contains { $0.remainingPercent <= 0 }
            return .success(ProviderSnapshot(
                provider: .claude,
                windows: windows,
                limitReached: limitReached,
                fetchedAt: Date()
            ))
        }
    }
}

struct CodexUsageProvider: UsageProvider {
    let provider: Provider = .codex

    private let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    func fetch() async -> Result<ProviderSnapshot, ProviderError> {
        let credentials: BearerCredentials
        switch CredentialsLoader.codex() {
        case .success(let value): credentials = value
        case .failure(let error): return .failure(error)
        }

        var headers = [
            "Authorization": "Bearer \(credentials.accessToken)",
            "Accept": "application/json",
            "User-Agent": AppInfo.userAgent
        ]
        if let accountId = credentials.accountId {
            headers["ChatGPT-Account-Id"] = accountId
        }

        switch await HTTP.getJSON(url: endpoint, headers: headers) {
        case .failure(let error):
            return .failure(error)
        case .success(let (root, _)):
            let windows = JSONScan.windows(in: root)
            guard !windows.isEmpty else {
                return .failure(.badPayload("no quota fields found in the response"))
            }
            let limitReached = JSONScan.firstBool(in: root, keys: ["limit_reached", "limitreached"])
                ?? (JSONScan.firstBool(in: root, keys: ["allowed"]).map { !$0 })
                ?? windows.contains { $0.remainingPercent <= 0 }

            return .success(ProviderSnapshot(
                provider: .codex,
                windows: windows,
                limitReached: limitReached,
                fetchedAt: Date()
            ))
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    static var userAgent: String { "Quotch/\(version)" }
}
