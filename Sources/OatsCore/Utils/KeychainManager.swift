import Foundation
import CryptoKit

public enum KeychainManager {
    private static let ud     = UserDefaults(suiteName: "oats.prefs")!
    private static let prefix = "oats1:"

    // MARK: - Encryption key

    private static var encryptionKey: SymmetricKey {
        let file = keyFilePath()
        if let data = try? Data(contentsOf: file), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key  = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600 as Int16)],
            ofItemAtPath: file.path
        )
        return key
    }

    private static func keyFilePath() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir  = base.appendingPathComponent("Oats", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".enckey")
    }

    // MARK: - API

    public static func save(_ value: String, for key: String) {
        guard let plaintext = value.data(using: .utf8),
              let sealed    = try? AES.GCM.seal(plaintext, using: encryptionKey),
              let combined  = sealed.combined
        else { return }
        ud.set(prefix + combined.base64EncodedString(), forKey: key)
        ud.synchronize()
    }

    public static func load(_ key: String) -> String? {
        guard let stored = ud.string(forKey: key), !stored.isEmpty else { return nil }
        if stored.hasPrefix(prefix) {
            let b64 = String(stored.dropFirst(prefix.count))
            guard let data  = Data(base64Encoded: b64),
                  let box   = try? AES.GCM.SealedBox(combined: data),
                  let plain = try? AES.GCM.open(box, using: encryptionKey),
                  let value = String(data: plain, encoding: .utf8)
            else { return nil }
            return value
        }
        save(stored, for: key)
        return stored
    }

    public static func delete(_ key: String) {
        ud.removeObject(forKey: key)
        ud.synchronize()
    }

    // MARK: - Migration

    public static func migrateFromUserDefaultsIfNeeded() {
        let oldUD = UserDefaults(suiteName: "com.oats.app")
        for key in [Key.granolaAPIKey, Key.claudeAPIKey] {
            if let stored = ud.string(forKey: key), stored.hasPrefix(prefix) { continue }
            if let stored = ud.string(forKey: key), !stored.isEmpty { save(stored, for: key); continue }
            if let oldValue = oldUD?.string(forKey: key), !oldValue.isEmpty {
                ud.set(oldValue, forKey: key); ud.synchronize()
                oldUD?.removeObject(forKey: key); oldUD?.synchronize()
                continue
            }
            if let value = loadFromKeychain(key: key) { save(value, for: key); deleteFromKeychain(key: key) }
        }
        if let oldUD {
            for key in ["userName", "userEmail", "hasCompletedOnboarding"] {
                if ud.object(forKey: key) == nil, let val = oldUD.object(forKey: key) {
                    ud.set(val, forKey: key); oldUD.removeObject(forKey: key)
                }
            }
            oldUD.synchronize(); ud.synchronize()
        }
    }

    // MARK: - Keychain helpers (migration only)

    private static let keychainService = "oats.prefs"

    private static func loadFromKeychain(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService as AnyObject,
            kSecAttrAccount: key as AnyObject, kSecReturnData: true as AnyObject,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    private static func deleteFromKeychain(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: keychainService as AnyObject,
            kSecAttrAccount: key as AnyObject,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Key constants

    public enum Key {
        public static let granolaAPIKey = "granolaAPIKey"
        public static let claudeAPIKey  = "claudeAPIKey"
    }
}
