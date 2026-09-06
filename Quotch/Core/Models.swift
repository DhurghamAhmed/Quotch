import Foundation

enum Provider: String, CaseIterable, Identifiable, Codable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex:  return "Codex"
        }
    }
}

struct UsageWindow: Identifiable, Equatable, Codable {
    var key: String
    var label: String
    var usedPercent: Double
    var resetsAt: Date?
    var order: Int

    var id: String { key }

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

struct ProviderSnapshot: Equatable, Codable {
    var provider: Provider
    var windows: [UsageWindow]
    var limitReached: Bool
    var fetchedAt: Date
    var source: UsageSource = .server

    var headline: UsageWindow? {
        windows.min { $0.remainingPercent < $1.remainingPercent }
    }
}

enum UsageSource: String, Codable {
    case server = "Synced with account"
    case session = "Updated from activity"
}

enum ProviderStatus: Equatable {
    case idle
    case loading
    case ok
    case throttled(until: Date)
    case needsLogin(String)
    case error(String)

    var isBlocking: Bool {
        switch self {
        case .needsLogin, .error, .throttled: return true
        case .idle, .loading, .ok: return false
        }
    }
}

struct ProviderState: Equatable {
    var status: ProviderStatus = .idle
    var snapshot: ProviderSnapshot?
    var isRefreshing: Bool = false
}

struct DiscoveredWindow: Identifiable {
    let provider: Provider
    let window: UsageWindow

    var id: String { AppSettings.windowID(provider: provider, key: window.key) }
}

enum ProviderError: LocalizedError, Equatable {
    case noCredentials(String)
    case unauthorized
    case rateLimited
    case httpStatus(Int, String)
    case badPayload(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials(let detail):
            return detail
        case .unauthorized:
            return "Token rejected — sign in again in the CLI"
        case .rateLimited:
            return "Rate limited by the server"
        case .httpStatus(let code, let body):
            let trimmed = body.prefix(160)
            return "HTTP \(code)\(trimmed.isEmpty ? "" : " — \(trimmed)")"
        case .badPayload(let detail):
            return "Unrecognised response: \(detail)"
        case .transport(let detail):
            return detail
        }
    }
}
