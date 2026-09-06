import Foundation

struct BearerCredentials {
    var accessToken: String
    var accountId: String?
    var expiresAt: Date?
    var source: String
}

enum CredentialsLoader {

    private static let accessTokenKeys: Set<String> = [
        "accesstoken", "access_token"
    ]
    private static let expiryKeys: Set<String> = [
        "expiresat", "expires_at", "expiry", "expires"
    ]
    private static let accountKeys: Set<String> = [
        "account_id", "accountid", "chatgpt_account_id", "chatgptaccountid"
    ]

    static func claude() -> Result<BearerCredentials, ProviderError> {
        let lookup = Keychain.firstGenericPassword(services: [
            "Claude Code-credentials",
            "Claude Code",
            "claude-code-credentials"
        ])

        if let data = lookup.data, let creds = parse(data, source: "login keychain") {
            return .success(creds)
        }

        var checkedFiles: [String] = []
        for url in claudeCredentialFiles() {
            checkedFiles.append((url.path as NSString).abbreviatingWithTildeInPath)
            guard let data = try? Data(contentsOf: url) else { continue }
            if let creds = parse(data, source: url.path) {
                return .success(creds)
            }
        }

        if lookup.wasDenied {
            return .failure(.noCredentials(
                "macOS blocked access to the Claude keychain item "
                + "(\(Keychain.describe(lookup.status))). The grant is tied to the app's "
                + "signature, so a rebuild revokes it: quit Quotch, relaunch it, and choose "
                + "\"Always Allow\" when macOS asks."
            ))
        }

        return .failure(.noCredentials(
            "No Claude Code login found. Looked in the login keychain "
            + "(\(Keychain.describe(lookup.status))) and at \(checkedFiles.joined(separator: ", ")). "
            + "Run `claude` in a terminal and sign in, then use Refresh Now."
        ))
    }

    private static func claudeCredentialFiles() -> [URL] {
        var roots: [URL] = []
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !override.isEmpty {
            for piece in override.split(separator: ",") {
                roots.append(URL(fileURLWithPath: String(piece).trimmingCharacters(in: .whitespaces)))
            }
        }
        roots.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"))
        return roots.map { $0.appendingPathComponent(".credentials.json") }
    }

    static func codex() -> Result<BearerCredentials, ProviderError> {
        for url in codexAuthFiles() {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard var creds = parse(data, source: url.path) else { continue }
            if creds.accountId == nil {
                creds.accountId = accountIdFromIdToken(in: data)
            }
            return .success(creds)
        }

        return .failure(.noCredentials(
            "No Codex login found at ~/.codex/auth.json. Run `codex` once and sign in."
        ))
    }

    private static func codexAuthFiles() -> [URL] {
        var roots: [URL] = []
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            for piece in override.split(separator: ",") {
                roots.append(URL(fileURLWithPath: String(piece).trimmingCharacters(in: .whitespaces)))
            }
        }
        roots.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"))
        return roots.map { $0.appendingPathComponent("auth.json") }
    }

    private static func parse(_ data: Data, source: String) -> BearerCredentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let token = JSONScan.firstString(in: root, keys: accessTokenKeys), !token.isEmpty else {
            return nil
        }

        var expiresAt: Date?
        if let raw = JSONScan.firstNumber(in: root, keys: expiryKeys) {
            expiresAt = raw > 100_000_000_000
                ? Date(timeIntervalSince1970: raw / 1000)
                : Date(timeIntervalSince1970: raw)
        }

        let accountId = JSONScan.firstString(in: root, keys: accountKeys)

        return BearerCredentials(accessToken: token,
                                 accountId: accountId,
                                 expiresAt: expiresAt,
                                 source: source)
    }

    private static func accountIdFromIdToken(in data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data),
            let idToken = JSONScan.firstString(in: root, keys: ["id_token", "idtoken"])
        else { return nil }

        let segments = idToken.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        guard let payload = base64URLDecode(String(segments[1])) else { return nil }
        guard let claims = try? JSONSerialization.jsonObject(with: payload) else { return nil }
        return JSONScan.firstString(in: claims, keys: accountKeys)
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = padded.count % 4
        if remainder > 0 {
            padded.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: padded)
    }
}
