import Foundation
import SwiftUI

private final class FakeProvider: UsageProvider {
    let provider: Provider = .claude
    var calls = 0
    var result: Result<ProviderSnapshot, ProviderError>
    init(_ result: Result<ProviderSnapshot, ProviderError>) { self.result = result }
    func fetch() async -> Result<ProviderSnapshot, ProviderError> {
        calls += 1
        return result
    }
}

@main
struct UsageTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    @MainActor
    static func main() async throws {
        let decimals = JSONScan.windows(in: ["five_hour": ["utilization": 0.5],
                                            "seven_day": ["utilization": 0]])
        check(decimals.count == 2, "Both Claude quotas are recognised")
        check(decimals[0].usedPercent == 0.5, "0.5% must not become 50%")
        check(decimals[1].remainingPercent == 100, "Unused quota is completely available")
        check(decimals[0].label == "Session quota", "Session has a descriptive name")
        check(decimals[1].label == "Weekly · All models", "Weekly scope is explicit")
        check(Format.percent(0.5) == "0.5%", "Decimal precision is visible")
        check(Format.percent(0) == "0%", "Zero stays zero")
        check(Format.percent(0.01) == "<0.1%", "Tiny positive percentages are not displayed as zero")
        check(Format.fill(decimals[1], metric: .used) == 0, "Empty meters have no artificial fill")
        check(JSONScan.windows(in: ["utilization": true]).isEmpty, "Booleans are not numbers")
        check(JSONScan.windows(in: ["used_percent": "nan"]).isEmpty, "NaN is rejected")
        check(JSONScan.windows(in: ["used_percent": Double.infinity]).isEmpty, "Infinity is rejected")
        check(JSONScan.windows(in: ["percent": 50]).isEmpty, "Unrelated percentages are not quotas")
        check(JSONScan.windows(in: ["fraction": 0.5]).first?.usedPercent == 50, "Explicit fractions are scaled")
        check(JSONScan.windows(in: ["fraction": 0.5, "used_percent": 2]).first?.usedPercent == 2,
              "Explicit percentages take priority over fraction fallback")
        let names = JSONScan.windows(in: ["seven_day_opus": ["utilization": 10],
                                         "seven_day_sonnet": ["utilization": 20]])
        check(Set(names.map(\.label)) == ["Weekly · Opus", "Weekly · Sonnet"], "Model names remain clear")
        let additional = JSONScan.windows(in: ["additional_rate_limits": [["limit_name": "Research", "rate_limit": [
            "primary_window": ["used_percent": 15, "limit_window_seconds": 86400]]]]])
        check(additional.first?.label == "Research · Daily quota", "Named additional quotas retain their scope")
        let numeric = JSONScan.windows(in: ["quotas": [["used_percent": 12]]])
        check(numeric.first?.label == "Quotas", "Array indices never become quota names")

        let scoped = JSONScan.windows(in: [
            "five_hour": ["utilization": 0.0, "resets_at": "2026-09-06T18:20:00.134480+00:00"],
            "seven_day": ["utilization": 12.0],
            "seven_day_opus": NSNull(),
            "spend": ["percent": 0, "used": ["amount_minor": 0]],
            "limits": [
                ["kind": "session", "group": "session", "percent": 0, "is_active": false],
                ["kind": "weekly_all", "group": "weekly", "percent": 12, "is_active": false],
                ["kind": "weekly_scoped", "group": "weekly", "percent": 13, "is_active": true,
                 "resets_at": "2026-09-08T10:00:00.134713+00:00",
                 "scope": ["model": ["id": NSNull(), "display_name": "Fable"], "surface": NSNull()]]
            ]
        ])
        check(scoped.map(\.label) == ["Session quota", "Weekly · All models", "Weekly · Fable"],
              "A per-model weekly cap is shown next to the all-models one")
        check(scoped.last?.usedPercent == 13, "The scoped weekly keeps the server's percentage")
        check(scoped.last?.key == "limits.weekly_scoped.fable",
              "Scoped keys survive the server reordering its limits array")
        check(scoped.last?.resetsAt != nil, "Scoped windows carry their own reset time")
        check(!scoped.contains { $0.label.contains("Spend") }, "Money is not a quota window")

        let placeholders = JSONScan.windows(in: [
            "five_hour": ["utilization": 0.0, "resets_at": "2026-09-06T18:20:00Z"],
            "seven_day": ["utilization": 0.0],
            "nimbus_quill": ["utilization": 0.0, "resets_at": NSNull(), "limit_dollars": NSNull()],
            "copper_kite": NSNull()
        ])
        check(placeholders.map(\.key) == ["five_hour", "seven_day"],
              "An unlabelable key with no window, no reset and no usage is not a quota")
        check(JSONScan.windows(in: ["nimbus_quill": ["utilization": 3.0]]).map(\.label) == ["Nimbus Quill"],
              "A placeholder that starts reporting usage appears without a code change")
        check(JSONScan.windows(in: ["nimbus_quill": ["utilization": 0, "resets_at": 1_800_000_000]]).count == 1,
              "A placeholder that gains a reset time appears even at zero usage")
        check(JSONScan.windows(in: ["rate_limit": ["primary_window": ["used_percent": 0]]]).count == 1,
              "A recognised window at zero usage is still a quota")

        let both = JSONScan.windows(in: ["seven_day_opus": ["utilization": 10],
                                        "limits": [["kind": "weekly_scoped", "group": "weekly", "percent": 10,
                                                    "scope": ["model": ["display_name": "Opus"]]]]])
        check(both.map(\.key) == ["seven_day_opus"], "A quota named twice in one payload draws one row")

        let event: [String: Any] = ["type": "event_msg", "payload": ["type": "token_count", "rate_limits": [
            "limit_id": "codex", "primary": ["used_percent": 4.0, "window_minutes": 300, "resets_at": 1_800_000_000],
            "secondary": ["used_percent": 2.0, "window_minutes": 10080, "resets_at": 1_800_500_000]]]]
        let snapshot = ActivityMonitor.codexSnapshot(event: event, date: Date())!
        check(snapshot.source == .session, "Activity source is identified")
        check(snapshot.windows.map(\.key) == ["rate_limit.primary_window", "rate_limit.secondary_window"],
              "Activity and HTTP quotas share stable keys")
        check(snapshot.windows.first?.resetsAt == Date(timeIntervalSince1970: 1_800_000_000), "Server reset date is preserved")
        check(ActivityMonitor.codexSnapshot(event: ["type": "response_item"], date: Date()) == nil,
              "Conversation records are not used as quota data")

        func isolatedDefaults() -> UserDefaults {
            UserDefaults(suiteName: "quotch.tests.\(UUID().uuidString)")!
        }

        let limited = FakeProvider(.failure(.rateLimited))
        let limitedDefaults = isolatedDefaults()
        let store = UsageStore(providers: [.claude: limited], defaults: limitedDefaults)
        store.settings.claudeEnabled = true
        await store.refresh(.claude, manual: false)
        await store.refresh(.claude, manual: true)
        await store.refresh(.claude, manual: false)
        check(limited.calls == 1, "Manual and automatic requests both respect backoff")
        check(store.state(.claude).snapshot == nil, "No invented values on failure")
        check(!store.state(.claude).isRefreshing, "Failed requests clear loading state")

        let successful = FakeProvider(.success(ProviderSnapshot(provider: .claude, windows: decimals,
            limitReached: false, fetchedAt: Date())))
        let successStore = UsageStore(providers: [.claude: successful], defaults: isolatedDefaults())
        successStore.settings.claudeEnabled = true
        await successStore.refresh(.claude, manual: false)
        await successStore.refresh(.claude, manual: true)
        check(successful.calls == 1, "Refreshes are coalesced across entry points")
        check(successStore.headline(for: .claude)?.usedPercent == 0.5, "Headline uses real quota")
        successStore.settings.setWindow(provider: .claude, key: "five_hour", visible: false)
        check(successStore.headline(for: .claude)?.usedPercent == 0, "Hidden quotas do not determine the headline")
        successStore.settings.claudeEnabled = false
        await successStore.refresh(.claude, manual: false)
        check(successful.calls == 1, "Disabled providers do not fetch")

        let throttledDefaults = isolatedDefaults()
        let throttled = FakeProvider(.failure(.rateLimited))
        let first = UsageStore(providers: [.claude: throttled], defaults: throttledDefaults)
        first.settings.claudeEnabled = true
        await first.refresh(.claude, manual: false)
        check(throttled.calls == 1, "The first process spends exactly one request")

        let relaunched = UsageStore(providers: [.claude: throttled], defaults: throttledDefaults)
        relaunched.settings.claudeEnabled = true
        await relaunched.refresh(.claude, manual: false)
        check(throttled.calls == 1, "A relaunch honours the throttle it was already under")

        let cached = UsageCache.load(.claude, from: throttledDefaults)
        check(cached?.backoff == Limits.backoffStart, "Backoff survives the relaunch")
        let stored = String(data: throttledDefaults.data(forKey: "cachedUsage.claude") ?? Data(),
                            encoding: .utf8) ?? ""
        check(!stored.lowercased().contains("token") && !stored.contains("Bearer")
              && !stored.contains("sk-"), "Nothing resembling a credential is ever written to disk")

        let carried = isolatedDefaults()
        let good = FakeProvider(.success(ProviderSnapshot(provider: .claude, windows: decimals,
            limitReached: false, fetchedAt: Date())))
        let before = UsageStore(providers: [.claude: good], defaults: carried)
        before.settings.claudeEnabled = true
        await before.refresh(.claude, manual: false)
        let after = UsageStore(providers: [.claude: good], defaults: carried)
        check(after.headline(for: .claude)?.usedPercent == 0.5,
              "The last known numbers are on screen before the first request of a new process")

        print("Passed: percentages, labels, activity payloads, real-data states, refresh coalescing, backoff and cache survival.")
    }
}
