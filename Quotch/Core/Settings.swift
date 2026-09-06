import Foundation

enum Metric: String, CaseIterable, Identifiable {
    case remaining
    case used

    var id: String { rawValue }
    var title: String { self == .used ? "Used" : "Left" }
    var suffix: String { self == .used ? "used" : "left" }
}

enum ResetStyle: String, CaseIterable, Identifiable {
    case relative
    case clock

    var id: String { rawValue }
    var title: String { self == .relative ? "Countdown" : "Clock time" }
}

enum SettingsKey {
    static let claudeEnabled = "claudeEnabled"
    static let codexEnabled = "codexEnabled"
    static let claudeInterval = "claudeIntervalSeconds"
    static let codexInterval = "codexIntervalSeconds"
    static let metric = "metric"
    static let resetStyle = "resetStyle"
    static let hiddenWindows = "hiddenWindows"
}

enum Limits {
    static let claudeMinInterval: TimeInterval = 120
    static let claudeDefaultInterval: TimeInterval = 300

    static let codexMinInterval: TimeInterval = 60
    static let codexDefaultInterval: TimeInterval = 120

    static func manualRefreshFloor(for provider: Provider) -> TimeInterval {
        switch provider {
        case .claude: return claudeDefaultInterval
        case .codex:  return 60
        }
    }

    static let backoffStart: TimeInterval = 300
    static let backoffCap: TimeInterval = 1800
}

struct AppSettings {
    var claudeEnabled: Bool
    var codexEnabled: Bool
    var claudeInterval: TimeInterval
    var codexInterval: TimeInterval

    var metric: Metric
    var resetStyle: ResetStyle
    var hiddenWindows: Set<String>

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        defaults.register(defaults: [
            SettingsKey.claudeEnabled: true,
            SettingsKey.codexEnabled: true,
            SettingsKey.claudeInterval: Limits.claudeDefaultInterval,
            SettingsKey.codexInterval: Limits.codexDefaultInterval,
            SettingsKey.metric: Metric.remaining.rawValue,
            SettingsKey.resetStyle: ResetStyle.relative.rawValue,
            SettingsKey.hiddenWindows: [String]()
        ])

        let metric = Metric(rawValue: defaults.string(forKey: SettingsKey.metric) ?? "") ?? .remaining
        let resetStyle = ResetStyle(
            rawValue: defaults.string(forKey: SettingsKey.resetStyle) ?? ""
        ) ?? .relative
        let hidden = defaults.stringArray(forKey: SettingsKey.hiddenWindows) ?? []

        return AppSettings(
            claudeEnabled: defaults.bool(forKey: SettingsKey.claudeEnabled),
            codexEnabled: defaults.bool(forKey: SettingsKey.codexEnabled),
            claudeInterval: max(Limits.claudeMinInterval,
                                defaults.double(forKey: SettingsKey.claudeInterval)),
            codexInterval: max(Limits.codexMinInterval,
                               defaults.double(forKey: SettingsKey.codexInterval)),
            metric: metric,
            resetStyle: resetStyle,
            hiddenWindows: Set(hidden)
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(claudeEnabled, forKey: SettingsKey.claudeEnabled)
        defaults.set(codexEnabled, forKey: SettingsKey.codexEnabled)
        defaults.set(claudeInterval, forKey: SettingsKey.claudeInterval)
        defaults.set(codexInterval, forKey: SettingsKey.codexInterval)
        defaults.set(metric.rawValue, forKey: SettingsKey.metric)
        defaults.set(resetStyle.rawValue, forKey: SettingsKey.resetStyle)
        defaults.set(Array(hiddenWindows).sorted(), forKey: SettingsKey.hiddenWindows)
    }

    func interval(for provider: Provider) -> TimeInterval {
        switch provider {
        case .claude: return claudeInterval
        case .codex:  return codexInterval
        }
    }

    func isEnabled(_ provider: Provider) -> Bool {
        switch provider {
        case .claude: return claudeEnabled
        case .codex:  return codexEnabled
        }
    }

    static func windowID(provider: Provider, key: String) -> String {
        "\(provider.rawValue)|\(key)"
    }

    func isWindowVisible(provider: Provider, key: String) -> Bool {
        !hiddenWindows.contains(AppSettings.windowID(provider: provider, key: key))
    }

    mutating func setWindow(provider: Provider, key: String, visible: Bool) {
        let id = AppSettings.windowID(provider: provider, key: key)
        if visible {
            hiddenWindows.remove(id)
        } else {
            hiddenWindows.insert(id)
        }
    }
}
