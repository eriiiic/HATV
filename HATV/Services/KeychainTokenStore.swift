import Foundation
import Security

enum KeychainTokenStoreError: LocalizedError {
    case unexpectedData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "The saved Home Assistant token is unreadable."
        case .unhandledStatus(let status):
            if status == errSecMissingEntitlement {
                return "Keychain access is unavailable for this build."
            }
            return "Keychain returned error \(status)."
        }
    }
}

struct KeychainTokenStore {
    private let service = "app.delattre.me.HATV.homeassistant"
    private let simulatorFallbackPrefix = "simulator.keychain_fallback."

    func save(_ token: String, account: String) throws {
        if shouldUseSimulatorFallback {
            saveSimulatorFallback(token, account: account)
            return
        }

        let data = Data(token.utf8)
        let query = baseQuery(account: account)

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw KeychainTokenStoreError.unhandledStatus(updateStatus)
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)

        guard addStatus == errSecSuccess else {
            throw KeychainTokenStoreError.unhandledStatus(addStatus)
        }
    }

    func load(account: String) throws -> String? {
        if shouldUseSimulatorFallback {
            return loadSimulatorFallback(account: account)
        }

        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainTokenStoreError.unhandledStatus(status)
        }

        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainTokenStoreError.unexpectedData
        }

        return token
    }

    func delete(account: String) throws {
        if shouldUseSimulatorFallback {
            deleteSimulatorFallback(account: account)
            return
        }

        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private var shouldUseSimulatorFallback: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private func saveSimulatorFallback(_ token: String, account: String) {
        UserDefaults.standard.set(token, forKey: simulatorFallbackPrefix + account)
    }

    private func loadSimulatorFallback(account: String) -> String? {
        UserDefaults.standard.string(forKey: simulatorFallbackPrefix + account)
    }

    private func deleteSimulatorFallback(account: String) {
        UserDefaults.standard.removeObject(forKey: simulatorFallbackPrefix + account)
    }
}
