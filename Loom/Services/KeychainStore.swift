import Foundation
import Security

struct KeychainStore {
    private let service = "online.minidesk.loom.model-keys"
    func read(_ id: UUID) -> String {
        var query = query(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    func write(_ key: String, for id: UUID) throws {
        let status: OSStatus
        if key.isEmpty {
            status = SecItemDelete(query(id) as CFDictionary)
        } else {
            let attributes = [kSecValueData as String: Data(key.utf8)]
            let update = SecItemUpdate(query(id) as CFDictionary, attributes as CFDictionary)
            if update == errSecItemNotFound {
                var item = query(id)
                item[kSecValueData as String] = Data(key.utf8)
                item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            } else { status = update }
        }
        guard status == errSecSuccess || (key.isEmpty && status == errSecItemNotFound) else {
            throw KeychainError(status: status)
        }
    }
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }
    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "无法保存 API Key（钥匙串错误 \(status)）。" }
    }
}
