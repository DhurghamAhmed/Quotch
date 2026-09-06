import SwiftUI

enum Palette {
    static let good    = Color(red: 0.29, green: 0.83, blue: 0.55)
    static let fair    = Color(red: 0.94, green: 0.80, blue: 0.29)
    static let low     = Color(red: 0.96, green: 0.62, blue: 0.20)
    static let spent   = Color(red: 0.94, green: 0.33, blue: 0.33)

    static let primaryText   = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.76)
    static let tertiaryText  = Color.white.opacity(0.55)
    static let hairline      = Color.white.opacity(0.14)
    static let trackFill     = Color.white.opacity(0.10)
}

enum Format {

    static func duration(until date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "now" }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours < 24 {
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        }
        let days = hours / 24
        let leftoverHours = hours % 24
        return leftoverHours == 0 ? "\(days)d" : "\(days)d \(leftoverHours)h"
    }

    static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value > 0 && value < 0.1 { return "<0.1%" }
        return value == value.rounded()
            ? "\(Int(value))%"
            : String(format: "%.1f%%", value)
    }

    static func color(forRemaining remaining: Double) -> Color {
        switch remaining {
        case ..<10: return Palette.spent
        case ..<25: return Palette.low
        case ..<50: return Palette.fair
        default:    return Palette.good
        }
    }

    static func value(_ window: UsageWindow, metric: Metric) -> Double {
        metric == .used ? window.usedPercent : window.remainingPercent
    }

    static func fill(_ window: UsageWindow, metric: Metric) -> Double {
        min(1, max(0, value(window, metric: metric) / 100))
    }

    static func resetText(for date: Date, now: Date, style: ResetStyle) -> String {
        switch style {
        case .relative:
            return "Resets in \(duration(until: date, now: now))"
        case .clock:
            let formatter = DateFormatter()
            if Calendar.current.isDate(date, inSameDayAs: now) {
                formatter.dateStyle = .none
                formatter.timeStyle = .short
            } else {
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
            }
            return "Resets \(formatter.string(from: date))"
        }
    }

    static func color(_ window: UsageWindow) -> Color {
        color(forRemaining: window.remainingPercent)
    }
}
