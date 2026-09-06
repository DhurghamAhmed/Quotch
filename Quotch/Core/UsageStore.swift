import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {

    @Published private(set) var states: [Provider: ProviderState] = [
        .claude: ProviderState(),
        .codex: ProviderState()
    ]
    @Published var settings: AppSettings = .load()

    private let providers: [Provider: any UsageProvider]
    private let defaults: UserDefaults

    init(providers: [Provider: any UsageProvider] = [
        .claude: ClaudeUsageProvider(), .codex: CodexUsageProvider()
    ], defaults: UserDefaults = .standard) {
        self.providers = providers
        self.defaults = defaults
        restoreCache()
    }

    private func restoreCache() {
        for provider in Provider.allCases {
            guard let cached = UsageCache.load(provider, from: defaults) else { continue }
            lastAttempt[provider] = cached.lastAttempt
            backoff[provider] = cached.backoff

            var state = ProviderState()
            state.snapshot = cached.snapshot
            if let until = cached.throttledUntil, until > Date() {
                state.status = .throttled(until: until)
            } else if cached.snapshot != nil {
                state.status = .ok
            }
            states[provider] = state
        }
    }

    private func persist(_ provider: Provider) {
        var throttledUntil: Date?
        if case .throttled(let until) = state(provider).status { throttledUntil = until }

        UsageCache.save(CachedUsage(snapshot: state(provider).snapshot,
                                    lastAttempt: lastAttempt[provider],
                                    backoff: backoff[provider] ?? 0,
                                    throttledUntil: throttledUntil),
                        for: provider, to: defaults)
    }

    private var lastAttempt: [Provider: Date] = [:]
    private var backoff: [Provider: TimeInterval] = [:]
    private var pollTasks: [Provider: Task<Void, Never>] = [:]
    private var activityMonitor: ActivityMonitor?
    private var activityTasks: [Provider: Task<Void, Never>] = [:]

    func start() {
        activityMonitor?.stop()
        activityMonitor = ActivityMonitor { [weak self] provider, snapshot in
            Task { @MainActor in self?.handleActivity(provider, snapshot: snapshot) }
        }
        activityMonitor?.start()
        restartPolling()
    }

    func stop() {
        activityMonitor?.stop()
        activityMonitor = nil
        for task in activityTasks.values { task.cancel() }
        activityTasks.removeAll()
        for task in pollTasks.values { task.cancel() }
        pollTasks.removeAll()
    }

    func applySettings(_ new: AppSettings) {
        let pollingChanged = new.claudeEnabled != settings.claudeEnabled
            || new.codexEnabled != settings.codexEnabled
            || new.claudeInterval != settings.claudeInterval
            || new.codexInterval != settings.codexInterval

        settings = new
        new.save()

        if pollingChanged {
            restartPolling()
        }
    }

    private func restartPolling() {
        for (provider, task) in pollTasks {
            task.cancel()
            pollTasks[provider] = nil
        }
        for provider in Provider.allCases {
            guard settings.isEnabled(provider) else {
                states[provider] = ProviderState()
                continue
            }
            pollTasks[provider] = Task { [weak self] in
                await self?.pollLoop(provider)
            }
        }
    }

    private func pollLoop(_ provider: Provider) async {
        let owed = await MainActor.run { self.timeUntilNextAllowedFetch(for: provider) }
        if owed > 0 {
            try? await Task.sleep(nanoseconds: UInt64(owed * 1_000_000_000))
        }

        while !Task.isCancelled {
            await refresh(provider, manual: false)
            let wait = await MainActor.run { self.nextDelay(for: provider) }
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    private func timeUntilNextAllowedFetch(for provider: Provider) -> TimeInterval {
        var wait: TimeInterval = 0
        if let last = lastAttempt[provider] {
            wait = max(0, nextDelay(for: provider) - Date().timeIntervalSince(last))
        }
        if case .throttled(let until) = state(provider).status {
            wait = max(wait, until.timeIntervalSinceNow)
        }
        return wait
    }

    private func nextDelay(for provider: Provider) -> TimeInterval {
        let base = settings.interval(for: provider)
        let penalty = backoff[provider] ?? 0
        return max(base, penalty)
    }

    private func handleActivity(_ provider: Provider, snapshot: ProviderSnapshot?) {
        guard settings.isEnabled(provider) else { return }
        if let snapshot {
            guard snapshot.fetchedAt > (state(provider).snapshot?.fetchedAt ?? .distantPast) else { return }
            mutate(provider) { state in
                var merged = snapshot
                let keys = Set(snapshot.windows.map(\.key))
                merged.windows += (state.snapshot?.windows ?? []).filter { !keys.contains($0.key) }
                state.snapshot = merged
                if !state.status.isBlocking { state.status = .ok }
            }
            persist(provider)
            return
        }
        guard activityTasks[provider] == nil else { return }
        activityTasks[provider] = Task { [weak self] in
            guard let self else { return }
            var wait = max(0, Limits.manualRefreshFloor(for: provider) - Date().timeIntervalSince(lastAttempt[provider] ?? .distantPast))
            if case .throttled(let until) = state(provider).status {
                wait = max(wait, until.timeIntervalSinceNow)
            }
            do { try await Task.sleep(nanoseconds: UInt64(max(0.25, wait) * 1_000_000_000)) }
            catch { return }
            await refresh(provider, manual: true)
            activityTasks[provider] = nil
        }
    }

    func refresh(_ provider: Provider, manual: Bool) async {
        guard settings.isEnabled(provider) else { return }
        guard let impl = providers[provider] else { return }

        if case .throttled(let until) = states[provider]?.status ?? .idle, until > Date() { return }
        if let last = lastAttempt[provider], Date().timeIntervalSince(last) < Limits.manualRefreshFloor(for: provider) { return }

        if states[provider]?.isRefreshing == true { return }

        let requestStartedAt = Date()
        lastAttempt[provider] = requestStartedAt
        mutate(provider) { state in
            state.isRefreshing = true
            if state.snapshot == nil { state.status = .loading }
        }

        let result = await impl.fetch()

        guard !Task.isCancelled, settings.isEnabled(provider) else {
            mutate(provider) { $0.isRefreshing = false }
            return
        }

        mutate(provider) { state in
            state.isRefreshing = false
            switch result {
            case .success(let snapshot):
                if (state.snapshot?.fetchedAt ?? .distantPast) <= requestStartedAt {
                    state.snapshot = snapshot
                }
                state.status = .ok
                self.backoff[provider] = 0

            case .failure(let error):
                switch error {
                case .rateLimited:
                    let previous = self.backoff[provider] ?? 0
                    let next = min(Limits.backoffCap,
                                   previous == 0 ? Limits.backoffStart : previous * 2)
                    self.backoff[provider] = next
                    state.status = .throttled(until: Date().addingTimeInterval(next))

                case .unauthorized:
                    state.status = .needsLogin(provider == .claude
                        ? "Claude token rejected. Run `claude` and sign in again."
                        : "Codex token rejected. Run `codex` and sign in again.")

                case .noCredentials(let detail):
                    state.status = .needsLogin(detail)

                default:
                    state.status = .error(error.errorDescription ?? "Unknown error")
                }
            }
        }

        persist(provider)
    }

    func refreshAll(manual: Bool) {
        for provider in Provider.allCases where settings.isEnabled(provider) {
            Task { await self.refresh(provider, manual: manual) }
        }
    }

    private func mutate(_ provider: Provider, _ body: (inout ProviderState) -> Void) {
        var state = states[provider] ?? ProviderState()
        body(&state)
        states[provider] = state
    }

    func state(_ provider: Provider) -> ProviderState {
        states[provider] ?? ProviderState()
    }

    var activeProviders: [Provider] {
        Provider.allCases.filter { settings.isEnabled($0) }
    }

    func windows(for provider: Provider) -> [UsageWindow] {
        guard let snapshot = state(provider).snapshot else { return [] }
        return snapshot.windows.filter {
            settings.isWindowVisible(provider: provider, key: $0.key)
        }
    }

    func headline(for provider: Provider) -> UsageWindow? {
        windows(for: provider).min { $0.remainingPercent < $1.remainingPercent }
    }

    var discoveredWindows: [DiscoveredWindow] {
        var result: [DiscoveredWindow] = []
        for provider in Provider.allCases {
            guard let snapshot = state(provider).snapshot else { continue }
            for window in snapshot.windows {
                result.append(DiscoveredWindow(provider: provider, window: window))
            }
        }
        return result
    }
}
