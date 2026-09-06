import Foundation
import CoreServices

final class ActivityMonitor {
    private let queue = DispatchQueue(label: "Quotch.activity", qos: .utility)
    private var stream: FSEventStreamRef?
    private var offsets: [String: UInt64] = [:]
    private var fragments: [String: Data] = [:]
    private var startedAt = Date()
    private let onEvent: (Provider, ProviderSnapshot?) -> Void
    private let configuredRoots: [(Provider, URL)]?

    init(roots: [(Provider, URL)]? = nil, onEvent: @escaping (Provider, ProviderSnapshot?) -> Void) {
        self.configuredRoots = roots
        self.onEvent = onEvent
    }

    private var roots: [(Provider, URL)] {
        if let configuredRoots { return configuredRoots }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment
        return [
            (.codex, environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".codex")),
            (.claude, environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".claude"))
        ]
    }

    func start() {
        stop()
        startedAt = Date()
        var context = FSEventStreamContext(version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<ActivityMonitor>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(paths, to: NSArray.self) as! [String]
            for path in paths.prefix(count) { monitor.consume(path) }
        }
        stream = FSEventStreamCreate(nil, callback, &context,
            roots.map { $0.1.path } as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.15, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        queue.sync {
            offsets.removeAll()
            fragments.removeAll()
        }
    }

    deinit { stop() }

    private func consume(_ path: String) {
        guard path.hasSuffix(".jsonl"),
              let (provider, root) = roots.first(where: { path.hasPrefix($0.1.path + "/") }),
              path.hasPrefix(root.appendingPathComponent(provider == .codex ? "sessions" : "projects").path + "/"),
              let file = FileHandle(forReadingAtPath: path) else { return }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd() else { return }
        let oldOffset = offsets[path]
        let offset = oldOffset.flatMap { $0 <= size ? $0 : nil } ?? (size > 1_048_576 ? size - 1_048_576 : 0)
        guard size > offset else { return }
        guard (try? file.seek(toOffset: offset)) != nil,
              let bytes = try? file.readToEnd() else { return }
        offsets[path] = size
        var data = fragments.removeValue(forKey: path) ?? Data()
        data.append(bytes)
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        if let tail = lines.popLast(), tail.count < 1_048_576 { fragments[path] = Data(tail) }
        if oldOffset == nil && offset > 0 && !lines.isEmpty { lines.removeFirst() }

        var activity = false
        var latest: ProviderSnapshot?
        for line in lines {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let timestamp = event["timestamp"] as? String,
                  let date = Self.eventDate(timestamp), date >= startedAt else { continue }
            if provider == .claude, event["type"] as? String == "assistant" { activity = true }
            if provider == .codex, let snapshot = Self.codexSnapshot(event: event, date: date),
               latest == nil || snapshot.fetchedAt >= latest!.fetchedAt { latest = snapshot }
        }
        if activity || latest != nil { onEvent(provider, latest) }
    }

    static func codexSnapshot(event: [String: Any], date: Date) -> ProviderSnapshot? {
        guard event["type"] as? String == "event_msg",
              let payload = event["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let limits = payload["rate_limits"] as? [String: Any],
              (limits["limit_id"] as? String ?? "codex") == "codex" else { return nil }
        var quota: [String: Any] = [:]
        if let primary = limits["primary"] { quota["primary_window"] = primary }
        if let secondary = limits["secondary"] { quota["secondary_window"] = secondary }
        let root: [String: Any] = ["rate_limit": quota]
        let windows = JSONScan.windows(in: root)
        guard !windows.isEmpty else { return nil }
        return ProviderSnapshot(provider: .codex, windows: windows,
            limitReached: windows.contains { $0.remainingPercent <= 0 }, fetchedAt: date,
            source: .session)
    }

    private static func eventDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
