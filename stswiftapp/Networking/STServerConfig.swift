import Foundation

/// Persisted server connection configuration.
struct STServerConfig: Codable, Equatable {
    var serverURL: String = ""
    var authMode: STAuthMode = .none
    var basicAuthUsername: String = ""
    var basicAuthPassword: String = ""
    var userHandle: String = ""
    var userPassword: String = ""
    var allowSelfSignedCerts: Bool = false

    var displayURL: String {
        serverURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var sanitizedURL: String {
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "http://" + url
        }
        while url.hasSuffix("/") {
            url.removeLast()
        }
        return url
    }

    var isValid: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum STAuthMode: String, Codable, CaseIterable {
    case none
    case basicAuth
    case userAccount

    var displayName: String {
        switch self {
        case .none: return "None (whitelist mode)"
        case .basicAuth: return "Basic Auth"
        case .userAccount: return "User Account"
        }
    }
}

/// Manages persistence of server configuration.
final class STServerConfigManager {
    static let shared = STServerConfigManager()
    private let defaultsKey = "st_server_config"

    private init() {}

    func load() -> STServerConfig {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(STServerConfig.self, from: data) else {
            return STServerConfig()
        }
        return config
    }

    func save(_ config: STServerConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
