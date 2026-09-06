import Foundation
import Security

enum Keychain {

    struct Lookup {
        var data: Data?
        var status: OSStatus
        var service: String?

        var found: Bool { data != nil }

        var wasDenied: Bool {
            switch status {
            case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled,
                 errSecInteractionRequired, errSecMissingEntitlement:
                return true
            default:
                return false
            }
        }
    }

    static func genericPassword(service: String, account: String? = nil) -> Lookup {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            return Lookup(data: nil, status: status, service: service)
        }
        return Lookup(data: item as? Data, status: status, service: service)
    }

    static func firstGenericPassword(services: [String]) -> Lookup {
        var mostInformative = Lookup(data: nil, status: errSecItemNotFound, service: nil)

        for service in services {
            let lookup = genericPassword(service: service)
            if lookup.found { return lookup }
            if lookup.wasDenied { mostInformative = lookup }
        }
        return mostInformative
    }

    static func describe(_ status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(message) (\(status))"
        }
        return "OSStatus \(status)"
    }
}
