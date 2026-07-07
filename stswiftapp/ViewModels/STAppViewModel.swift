import SwiftUI
import Observation

@Observable
final class STAppViewModel {
    var serverConfig: STServerConfig = .init()
    var isConnected = false
    var isConnecting = false
    var errorMessage: String?
    var selectedTab: STTab = .chats

    /// Active persona name — the display name of the currently selected persona.
    /// Falls back to the server user handle, then "User".
    var activePersonaName: String = "User"
    /// Active persona description — injected into the system prompt.
    var activePersonaDescription: String = ""

    // Navigation state
    var navigationPath = NavigationPath()

    // Tab
    enum STTab: String, CaseIterable {
        case chats = "Chats"
        case characters = "Characters"
        case groups = "Groups"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .chats: return "bubble.left.and.bubble.right"
            case .characters: return "person.2"
            case .groups: return "person.3"
            case .settings: return "gear"
            }
        }
    }

    func loadConfiguration() {
        serverConfig = STServerConfigManager.shared.load()
        if serverConfig.isValid {
            connect()
        }
    }

    func connect() {
        guard serverConfig.isValid else {
            errorMessage = "Please configure server address"
            return
        }

        isConnecting = true
        errorMessage = nil

        let client = STAPIClient.shared
        client.configure(with: serverConfig)

        Task {
            do {
                // Try fetching CSRF token as a connectivity test
                try await client.fetchCSRFToken()

                // If user account mode, try login
                if serverConfig.authMode == .userAccount {
                    try await client.login(
                        handle: serverConfig.userHandle,
                        password: serverConfig.userPassword
                    )
                }

                await MainActor.run {
                    isConnected = true
                    isConnecting = false
                }
                // Load settings immediately on connect
                await SettingsStore.shared.load()
                await loadActivePersona()
                if SettingsStore.shared.chatCompletionSource != "custom" {
                    await SettingsStore.shared.fetchModels()
                }
            } catch {
                await MainActor.run {
                    isConnected = false
                    isConnecting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func saveAndConnect(_ config: STServerConfig) {
        serverConfig = config
        STServerConfigManager.shared.save(config)
        connect()
    }

    /// Load the currently selected persona from settings.
    func loadActivePersona() async {
        let settingsJSON = SettingsStore.shared.settingsJSON
        let powerUser = settingsJSON["power_user"] as? [String: Any] ?? [:]
        let personasDict = powerUser["personas"] as? [String: Any] ?? [:]
        let descriptionsDict = powerUser["persona_descriptions"] as? [String: Any] ?? [:]

        let avatarId = settingsJSON["user_avatar"] as? String ?? ""
        if !avatarId.isEmpty, let name = personasDict[avatarId] as? String {
            activePersonaName = name
        } else {
            // Fall back to server handle or "User"
            activePersonaName = serverConfig.userHandle.isEmpty ? "User" : serverConfig.userHandle
        }

        if !avatarId.isEmpty, let desc = descriptionsDict[avatarId] as? [String: Any] {
            activePersonaDescription = desc["description"] as? String ?? ""
        } else {
            activePersonaDescription = ""
        }
    }

    func disconnect() {
        let client = STAPIClient.shared
        Task {
            if serverConfig.authMode == .userAccount {
                try? await client.logout()
            }
            await MainActor.run {
                client.reset()
                isConnected = false
                navigationPath = NavigationPath()
            }
        }
    }
}
