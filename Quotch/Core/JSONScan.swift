import Foundation

enum JSONScan {

    private static let percentKeys: Set<String> = [
        "used_percent", "usedpercent", "percent_used", "percentused",
        "utilization", "utilisation",
        "usage_percent", "usagepercent",
    ]

    private static let fractionHintKeys: Set<String> = [
        "ratio", "fraction"
    ]

    private static let positionalNames: Set<String> = [
        "primary_window", "primary", "secondary_window", "secondary"
    ]

    private static let resetKeys: Set<String> = [
        "reset_at", "resetat", "resets_at", "resetsat",
        "reset_time", "resettime",
        "resets_in_seconds", "resetsinseconds",
        "reset_after_seconds", "resetafterseconds",
        "seconds_until_reset", "secondsuntilreset",
        "resets_in", "resetsin",
        "reset"
    ]

    private static let prettyLabels: [String: String] = [
        "primary_window": "Session quota",
        "primary": "Session quota",
        "secondary_window": "Weekly quota",
        "secondary": "Weekly quota",
        "five_hour": "Session quota",
        "fivehour": "Session quota",
        "seven_day": "Weekly · All models",
        "sevenday": "Weekly · All models",
        "seven_day_opus": "Weekly · Opus",
        "seven_day_sonnet": "Weekly · Sonnet",
        "seven_day_oauth_apps": "Weekly · Connected apps",
        "seven_day_cowork": "Weekly · Cowork",
        "extra_usage": "Extra usage",
        "weekly": "Weekly",
        "session": "Session",
        "daily": "Daily",
        "monthly": "Monthly"
    ]

    static func windows(in root: Any) -> [UsageWindow] {
        var found: [UsageWindow] = []
        walk(root, path: [], into: &found)
        collectLimitEntries(in: root, into: &found)

        for index in found.indices where found[index].order == Int.max {
            found[index].order = 500 + index
        }
        return found.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.key < rhs.key
        }
    }

    private static func walk(_ node: Any, path: [String], scope: String? = nil, into found: inout [UsageWindow]) {
        if let dict = node as? [String: Any] {
            let scope = (dict["limit_name"] as? String) ?? scope
            if var window = window(from: dict, path: path) {
                if let scope, !scope.isEmpty { window.label = "\(scope) · \(window.label)" }
                found.append(window)
            }
            for key in dict.keys.sorted() {
                guard let value = dict[key] else { continue }
                if key.lowercased().contains("token") && value is String { continue }
                walk(value, path: path + [key], scope: scope, into: &found)
            }
        } else if let array = node as? [Any] {
            for (index, value) in array.enumerated() {
                walk(value, path: path + ["\(index)"], scope: scope, into: &found)
            }
        }
    }

    private static func window(from dict: [String: Any], path: [String]) -> UsageWindow? {
        var percent: Double?
        var isFraction = false

        let orderedKeys = dict.keys.sorted { lhs, rhs in
            let leftIsPercent = percentKeys.contains(normalise(lhs))
            let rightIsPercent = percentKeys.contains(normalise(rhs))
            return leftIsPercent == rightIsPercent ? lhs < rhs : leftIsPercent
        }
        for rawKey in orderedKeys {
            guard let value = dict[rawKey] else { continue }
            let key = normalise(rawKey)
            guard percentKeys.contains(key) || fractionHintKeys.contains(key) else { continue }
            guard let number = double(from: value) else { continue }
            percent = number
            isFraction = fractionHintKeys.contains(key)
            break
        }

        guard var usedPercent = percent, usedPercent.isFinite else { return nil }
        if isFraction { usedPercent *= 100 }
        usedPercent = max(0, min(100, usedPercent))

        var resetsAt: Date?
        for (rawKey, value) in dict {
            let key = normalise(rawKey)
            guard resetKeys.contains(key) else { continue }
            if let date = date(from: value, key: key) {
                resetsAt = date
                break
            }
        }

        let ownName = path.last ?? "usage"
        let key = path.isEmpty ? "usage" : path.joined(separator: ".")
        let normalisedName = normalise(ownName)

        var hasRealName = true
        var isRecognised = true
        var label: String

        if let pretty = prettyLabels[normalisedName] {
            label = pretty
            hasRealName = !positionalNames.contains(normalisedName)
        } else if let family = familyLabel(for: normalisedName) {
            label = family
        } else if Int(ownName) != nil {
            label = (dict["name"] as? String)
                ?? (dict["limit_name"] as? String)
                ?? humanise(path.dropLast().last ?? "Additional quota")
            hasRealName = (dict["name"] as? String) != nil || (dict["limit_name"] as? String) != nil
            isRecognised = hasRealName
        } else {
            label = humanise(ownName)
            hasRealName = false
            isRecognised = false
        }

        if !hasRealName,
           let minutes = double(from: dict["window_minutes"] ?? NSNull())
            ?? double(from: dict["limit_window_seconds"] ?? NSNull()).map({ $0 / 60 }) {
            if minutes == 10080 { label = "Weekly quota"; isRecognised = true }
            else if minutes == 1440 { label = "Daily quota"; isRecognised = true }
            else if minutes == 43200 { label = "Monthly quota"; isRecognised = true }
        }

        if !isRecognised, resetsAt == nil, usedPercent == 0 { return nil }

        if path.contains("code_review_rate_limit"), !label.hasPrefix("Code review · ") {
            label = "Code review · \(label)"
        }

        let order = knownOrder(for: normalisedName)

        return UsageWindow(key: key, label: label, usedPercent: usedPercent,
                           resetsAt: resetsAt, order: order)
    }

    private static func collectLimitEntries(in node: Any, into found: inout [UsageWindow]) {
        if let dict = node as? [String: Any] {
            if let entries = dict["limits"] as? [[String: Any]] {
                let existing = Set(found.map(\.key))
                for (index, entry) in entries.enumerated() {
                    guard var window = limitWindow(from: entry, index: index, supersededBy: existing)
                    else { continue }
                    if found.contains(where: { $0.key == window.key }) { window.key += ".\(index)" }
                    found.append(window)
                }
            }
            for value in dict.values { collectLimitEntries(in: value, into: &found) }
        } else if let array = node as? [Any] {
            for value in array { collectLimitEntries(in: value, into: &found) }
        }
    }

    private static func limitWindow(from entry: [String: Any], index: Int,
                                    supersededBy existing: Set<String>) -> UsageWindow? {
        guard let kind = entry["kind"] as? String, !kind.isEmpty else { return nil }
        guard let percent = double(from: entry["percent"] ?? NSNull()), percent.isFinite else { return nil }

        let normalisedKind = normalise(kind)
        let scope = scopeName(in: entry["scope"])
        let scopeSlug = scope.map(slug)

        if let legacy = legacyKey(kind: normalisedKind, scopeSlug: scopeSlug), existing.contains(legacy) {
            return nil
        }

        let family: String
        switch normalise(entry["group"] as? String ?? kind) {
        case "session":      family = "Session"
        case "weekly":       family = "Weekly"
        case "daily":        family = "Daily"
        case "monthly":      family = "Monthly"
        default:             family = humanise(kind)
        }

        let label: String
        if let scope {
            label = "\(family) · \(scope)"
        } else if normalisedKind.hasSuffix("_all") {
            label = "\(family) · All models"
        } else {
            label = family == "Session" ? "Session quota" : "\(family) quota"
        }

        var resetsAt: Date?
        for (rawKey, value) in entry where resetKeys.contains(normalise(rawKey)) {
            if let date = date(from: value, key: normalise(rawKey)) {
                resetsAt = date
                break
            }
        }

        let order: Int
        switch normalisedKind {
        case "session":  order = 0
        case "weekly_all": order = 1
        default: order = 4 + index
        }

        return UsageWindow(
            key: (["limits", normalisedKind] + (scopeSlug.map { [$0] } ?? [])).joined(separator: "."),
            label: label,
            usedPercent: max(0, min(100, percent)),
            resetsAt: resetsAt,
            order: order
        )
    }

    private static func legacyKey(kind: String, scopeSlug: String?) -> String? {
        switch kind {
        case "session":        return "five_hour"
        case "weekly_all":     return "seven_day"
        case "weekly_scoped":  return scopeSlug.map { "seven_day_\($0)" }
        default:               return nil
        }
    }

    private static func scopeName(in node: Any?) -> String? {
        guard let scope = node as? [String: Any] else { return nil }
        for key in ["model", "surface", "product"] {
            if let child = scope[key] as? [String: Any] {
                for field in ["display_name", "name"] {
                    if let name = child[field] as? String, !name.isEmpty { return name }
                }
                if let id = child["id"] as? String, !id.isEmpty { return humanise(id) }
            } else if let name = scope[key] as? String, !name.isEmpty {
                return humanise(name)
            }
        }
        if let name = scope["display_name"] as? String, !name.isEmpty { return name }
        return nil
    }

    private static func slug(_ raw: String) -> String {
        let mapped = String(raw.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
        return mapped.split(separator: "_").joined(separator: "_")
    }

    private static let families: [(prefix: String, name: String)] = [
        ("seven_day", "Weekly"),
        ("sevenday", "Weekly"),
        ("five_hour", "Session"),
        ("fivehour", "Session"),
        ("one_day", "Daily"),
        ("thirty_day", "Monthly")
    ]

    private static func familyLabel(for normalisedName: String) -> String? {
        for family in families where normalisedName.hasPrefix(family.prefix + "_") {
            let suffix = String(normalisedName.dropFirst(family.prefix.count + 1))
            guard !suffix.isEmpty else { return nil }
            return "\(family.name) · \(humanise(suffix))"
        }
        return nil
    }

    private static func normalise(_ key: String) -> String {
        key.lowercased().replacingOccurrences(of: "-", with: "_")
    }

    private static func double(from value: Any) -> Double? {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            return number.doubleValue
        }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func date(from value: Any, key: String) -> Date? {
        if let string = value as? String {
            if let date = isoDate(from: string) { return date }
            if let number = Double(string) { return date(fromNumber: number, key: key) }
            return nil
        }
        if let number = double(from: value) { return date(fromNumber: number, key: key) }
        return nil
    }

    private static func date(fromNumber number: Double, key: String) -> Date? {
        guard number.isFinite, number > 0 else { return nil }
        if key.contains("in_seconds") || key.contains("until") || key.contains("after_seconds")
            || key == "resets_in" || key == "resetsin" {
            return Date().addingTimeInterval(number)
        }
        if number > 100_000_000_000 { return Date(timeIntervalSince1970: number / 1000) }
        if number > 1_000_000_000 { return Date(timeIntervalSince1970: number) }
        return Date().addingTimeInterval(number)
    }

    private static let isoFormatters: [ISO8601DateFormatter] = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return [withFraction, plain]
    }()

    private static func isoDate(from string: String) -> Date? {
        for formatter in isoFormatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    private static func knownOrder(for normalisedName: String) -> Int {
        switch normalisedName {
        case "primary_window", "primary", "five_hour", "fivehour", "session": return 0
        case "secondary_window", "secondary", "seven_day", "sevenday", "weekly": return 1
        case "seven_day_opus": return 2
        case "seven_day_sonnet": return 3
        case "monthly": return 3
        default: return Int.max
        }
    }

    private static func humanise(_ raw: String) -> String {
        let spaced = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let words = spaced.split(separator: " ").map { word -> String in
            let lower = word.lowercased()
            if lower == "window" || lower == "limit" { return "" }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
        let joined = words.filter { !$0.isEmpty }.joined(separator: " ")
        return joined.isEmpty ? "Usage" : joined
    }

    static func firstString(in node: Any, keys: Set<String>) -> String? {
        if let dict = node as? [String: Any] {
            for (rawKey, value) in dict {
                if keys.contains(normalise(rawKey)), let string = value as? String, !string.isEmpty {
                    return string
                }
            }
            for value in dict.values {
                if let found = firstString(in: value, keys: keys) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = firstString(in: value, keys: keys) { return found }
            }
        }
        return nil
    }

    static func firstNumber(in node: Any, keys: Set<String>) -> Double? {
        if let dict = node as? [String: Any] {
            for (rawKey, value) in dict {
                if keys.contains(normalise(rawKey)), let number = double(from: value) { return number }
            }
            for value in dict.values {
                if let found = firstNumber(in: value, keys: keys) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = firstNumber(in: value, keys: keys) { return found }
            }
        }
        return nil
    }

    static func firstBool(in node: Any, keys: Set<String>) -> Bool? {
        if let dict = node as? [String: Any] {
            for (rawKey, value) in dict {
                if keys.contains(normalise(rawKey)), let number = value as? NSNumber,
                   CFGetTypeID(number) == CFBooleanGetTypeID() {
                    return number.boolValue
                }
            }
            for value in dict.values {
                if let found = firstBool(in: value, keys: keys) { return found }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = firstBool(in: value, keys: keys) { return found }
            }
        }
        return nil
    }
}
