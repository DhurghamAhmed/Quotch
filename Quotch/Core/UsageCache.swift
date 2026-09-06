import Foundation

struct CachedUsage: Codable {
    var snapshot: ProviderSnapshot?
    var lastAttempt: Date?
    var backoff: TimeInterval
    var throttledUntil: Date?

    var age: TimeInterval? {
        snapshot.map { Date().timeIntervalSince($0.fetchedAt) }
    }
}

enum UsageCache {

    private static func key(for provider: Provider) -> String {
        "cachedUsage.\(provider.rawValue)"
    }

    static func load(_ provider: Provider, from defaults: UserDefaults = .standard) -> CachedUsage? {
        guard let data = defaults.data(forKey: key(for: provider)) else { return nil }
        return try? JSONDecoder().decode(CachedUsage.self, from: data)
    }

    static func save(_ cached: CachedUsage,
                     for provider: Provider,
                     to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(cached) else { return }
        defaults.set(data, forKey: key(for: provider))
    }

    static func clear(_ provider: Provider, from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(for: provider))
    }
}
