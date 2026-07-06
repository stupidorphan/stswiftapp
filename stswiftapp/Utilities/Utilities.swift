import Foundation

// MARK: - Image Cache Utility

/// In-memory + disk image cache for avatars.
final class STImageCache {
    static let shared = STImageCache()
    private let cache = NSCache<NSString, NSData>()
    private let diskDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("STImageCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }

    private func sanitize(_ key: String) -> String {
        key.replacingOccurrences(of: "/", with: "_")
           .replacingOccurrences(of: "?", with: "_")
           .replacingOccurrences(of: "=", with: "_")
    }

    func get(for key: String) -> Data? {
        // Memory first
        if let mem = cache.object(forKey: key as NSString) as Data? {
            return mem
        }
        // Then disk
        if let disk = try? Data(contentsOf: diskDir.appendingPathComponent(sanitize(key))) {
            cache.setObject(disk as NSData, forKey: key as NSString)
            return disk
        }
        return nil
    }

    func set(_ data: Data, for key: String) {
        cache.setObject(data as NSData, forKey: key as NSString)
        try? data.write(to: diskDir.appendingPathComponent(sanitize(key)), options: .atomic)
    }

    func clear() {
        cache.removeAllObjects()
        try? FileManager.default.removeItem(at: diskDir)
        try? FileManager.default.createDirectory(at: diskDir, withIntermediateDirectories: true)
    }
}

// MARK: - Keychain Helper

import Security

final class STKeychain {
    static func save(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func saveString(key: String, value: String) {
        save(key: key, data: Data(value.utf8))
    }

    static func loadString(key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Date Helpers

extension Double {
    var dateFromTimestamp: Date {
        Date(timeIntervalSince1970: self / 1000.0)
    }
}

extension Date {
    var relativeDisplay: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
