import SwiftUI
import Observation
import UniformTypeIdentifiers
import os

// MARK: - Settings Store

@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    var settingsJSON: [String: Any] = [:]
    /// Presets keyed by API type: "openai" → [names], "kobold" → [names], etc.
    var presetNames: [String: [String]] = [:]
    /// Preset contents keyed by API type: "openai" → [preset JSON objects], etc.
    var presetContents: [String: [Any]] = [:]
    var isLoading = false
    var errorMessage: String?
    var savePending = false

    /// Returns preset names for the current chat_completion_source
    var currentPresetNames: [String] {
        presetNames[presetKeyForSource] ?? []
    }

    /// Maps chat_completion_source to preset key
    private var presetKeyForSource: String {
        switch chatCompletionSource {
        case "openai": return "openai"
        case "claude": return "openai"
        case "groq": return "openai"
        case "deepseek": return "openai"
        case "mistralai": return "openai"
        case "cohere": return "openai"
        case "perplexity": return "openai"
        case "xai": return "openai"
        case "fireworks": return "openai"
        case "openrouter": return "openai"
        case "custom": return "openai"
        case "kobold": return "kobold"
        case "novel": return "novel"
        case "textgenerationwebui": return "textgenerationwebui"
        default: return "openai"
        }
    }

    // Per-panel state
    var temperature: Double = 0.7
    var maxTokens: Int = 200
    var maxCompletionTokens: Int = 0
    var topP: Double = 1.0
    var topK: Int = 0
    var frequencyPenalty: Double = 0.0
    var presencePenalty: Double = 0.0
    var repetitionPenalty: Double = 1.0
    var stopSequences: String = ""
    var seed: Int = 0
    var streamEnabled: Bool = true
    var chatCompletionSource: String = "openai"
    var model: String = ""
    var reverseProxy: String = ""
    var customURL: String = ""
    var proxyPassword: String = ""
    var customIncludeBody: String = ""
    var customIncludeHeaders: String = ""
    var customExcludeBody: String = ""
    var selectedPreset: String = ""
    var apiKey: String = ""
    var dirty: Bool = false
    var availableModels: [String] = []
    var isLoadingModels = false

    /// Maps provider → SillyTavern secret key name
    var currentSecretKey: String {
        switch chatCompletionSource {
        case "openai": return "api_key_openai"
        case "claude": return "api_key_claude"
        case "openrouter": return "api_key_openrouter"
        case "mistralai": return "api_key_mistralai"
        case "cohere": return "api_key_cohere"
        case "perplexity": return "api_key_perplexity"
        case "groq": return "api_key_groq"
        case "deepseek": return "api_key_deepseek"
        case "xai": return "api_key_xai"
        case "fireworks": return "api_key_fireworks"
        case "custom": return "api_key_custom"
        case "kobold": return "api_key_kobold"
        case "novel": return "api_key_novel"
        case "makersuite": return "api_key_makersuite"
        case "vertexai": return "api_key_vertexai"
        case "ai21": return "api_key_ai21"
        case "chutes": return "api_key_chutes"
        case "electronhub": return "api_key_electronhub"
        case "nanogpt": return "api_key_nanogpt"
        case "aimlapi": return "api_key_aimlapi"
        case "pollinations": return "api_key_pollinations"
        case "cometapi": return "api_key_cometapi"
        case "moonshot": return "api_key_moonshot"
        case "azure_openai": return "api_key_azure_openai"
        case "zai": return "api_key_zai"
        case "siliconflow": return "api_key_siliconflow"
        case "minimax": return "api_key_minimax"
        case "workers_ai": return "api_key_workers_ai"
        default: return "api_key_openai"
        }
    }

    // Extension settings: [extId: [String: Any]]
    var extensionSettings: [String: [String: Any]] = [:]

    // Debounce
    private var saveTask: Task<Void, Never>?
    private let client = STAPIClient.shared
    private let logger = Logger(subsystem: "com.stswiftapp", category: "SettingsStore")

    /// Recursively unwrap nested `settings` JSON strings until we reach the real data.
    private func unpackSettings(_ dict: [String: Any]) -> [String: Any] {
        if let inner = dict["settings"] as? String,
           let data = inner.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return unpackSettings(parsed)
        }
        return dict
    }

    // MARK: - Load

    @MainActor
    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let data = try await client.postRaw("/api/settings/get", body: EmptyBody())
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw STAPIError.decodingFailed(NSError(domain: "", code: -1))
            }
            if let settingsStr = json["settings"] as? String,
               let settingsData = settingsStr.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any] {
                let unpacked = unpackSettings(parsed)
                settingsJSON = unpacked
                print("[Settings] Loaded keys: \(unpacked.keys.sorted().joined(separator: ", "))")
                hydrate(from: unpacked)
            }
            // Load all preset types
            var allPresets: [String: [String]] = [:]
            var allContents: [String: [Any]] = [:]
            if let names = json["openai_setting_names"] as? [String] { allPresets["openai"] = names }
            if let contents = json["openai_settings"] as? [Any] { allContents["openai"] = contents }
            if let names = json["koboldai_setting_names"] as? [String] { allPresets["kobold"] = names }
            if let contents = json["koboldai_settings"] as? [Any] { allContents["kobold"] = contents }
            if let names = json["novelai_setting_names"] as? [String] { allPresets["novel"] = names }
            if let contents = json["novelai_settings"] as? [Any] { allContents["novel"] = contents }
            if let names = json["textgenerationwebui_preset_names"] as? [String] { allPresets["textgenerationwebui"] = names }
            if let contents = json["textgenerationwebui_presets"] as? [Any] { allContents["textgenerationwebui"] = contents }
            presetNames = allPresets
            presetContents = allContents
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func hydrate(from json: [String: Any]) {
        // Settings are nested under oai_settings (SillyTavern's format)
        let oai = json["oai_settings"] as? [String: Any] ?? json

        temperature = (oai["temp_openai"] as? Double) ?? (json["temperature"] as? Double) ?? 0.7
        maxTokens = (oai["openai_max_tokens"] as? Int) ?? (json["max_tokens"] as? Int) ?? 200
        maxCompletionTokens = (oai["max_completion_tokens"] as? Int) ?? (json["max_completion_tokens"] as? Int) ?? 0
        topP = (oai["top_p_openai"] as? Double) ?? (json["top_p"] as? Double) ?? 1.0
        topK = (oai["top_k_openai"] as? Int) ?? (json["top_k"] as? Int) ?? 0
        frequencyPenalty = (oai["freq_pen_openai"] as? Double) ?? (json["frequency_penalty"] as? Double) ?? 0.0
        presencePenalty = (oai["pres_pen_openai"] as? Double) ?? (json["presence_penalty"] as? Double) ?? 0.0
        repetitionPenalty = (json["repetition_penalty"] as? Double) ?? 1.0
        streamEnabled = (oai["stream_openai"] as? Bool) ?? (json["stream"] as? Bool) ?? true
        seed = oai["seed"] as? Int ?? json["seed"] as? Int ?? 0
        stopSequences = (json["stop"] as? [String])?.joined(separator: ", ") ?? ""

        chatCompletionSource = (oai["chat_completion_source"] as? String) ?? (json["chat_completion_source"] as? String) ?? "openai"
        model = (oai["openai_model"] as? String) ?? (oai["model"] as? String) ?? ""
        reverseProxy = (oai["reverse_proxy"] as? String) ?? (oai["reverse_proxy"] as? String) ?? ""
        customURL = (oai["custom_url"] as? String) ?? (oai["custom_url"] as? String) ?? ""
        proxyPassword = (oai["proxy_password"] as? String) ?? (oai["proxy_password"] as? String) ?? ""
        customIncludeBody = (oai["custom_include_body"] as? String) ?? ""
        customIncludeHeaders = (oai["custom_include_headers"] as? String) ?? ""
        customExcludeBody = (oai["custom_exclude_body"] as? String) ?? ""

        if let ext = json["extensions"] as? [String: [String: Any]] {
            extensionSettings = ext
        }
    }

    // MARK: - Models

    @MainActor
    func fetchModels() async {
        isLoadingModels = true
        let body = STConnectionTestBody(
            chat_completion_source: chatCompletionSource,
            reverse_proxy: reverseProxy, custom_url: customURL,
            proxy_password: proxyPassword, custom_include_headers: customIncludeHeaders
        )
        do {
            let data = try await client.postRaw("/api/backends/chat-completions/status", body: body)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["data"] as? [[String: Any]] {
                self.availableModels = models.compactMap { $0["id"] as? String }
                print("[Settings] Fetched \(self.availableModels.count) models for \(self.chatCompletionSource)")
            }
        } catch {
            print("[Settings] Model fetch failed"); logger.warning("Model fetch failed: \(error.localizedDescription)")
        }
        isLoadingModels = false
    }

    // MARK: - Save (debounced)

    private var isImmediateSave = false

    /// Immediately persist all settings to server — no debounce delay.
    @MainActor
    func saveNow() {
        isImmediateSave = true
        saveTask?.cancel()
        savePending = true
        Task {
            await persist()
            isImmediateSave = false
        }
    }

    func scheduleSave() {
        guard !isImmediateSave else { return }
        dirty = true
        savePending = true
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            await persist()
        }
    }

    /// Mark settings as dirty so the user can manually save later.
    /// Does NOT auto-save. The UI shows a Save button when dirty.
    func markDirty() {
        dirty = true
    }

    @MainActor
    private func persist() async {
        // Build oai_settings dict — matches SillyTavern's format
        var oai: [String: Any] = settingsJSON["oai_settings"] as? [String: Any] ?? [:]
        oai["chat_completion_source"] = chatCompletionSource
        oai["openai_model"] = model
        oai["temp_openai"] = temperature
        oai["openai_max_tokens"] = maxTokens
        oai["max_completion_tokens"] = maxCompletionTokens
        oai["top_p_openai"] = topP
        oai["top_k_openai"] = topK
        oai["freq_pen_openai"] = frequencyPenalty
        oai["pres_pen_openai"] = presencePenalty
        oai["stream_openai"] = streamEnabled
        oai["reverse_proxy"] = reverseProxy
        oai["custom_url"] = customURL
        oai["proxy_password"] = proxyPassword
        oai["custom_include_body"] = customIncludeBody
        oai["custom_include_headers"] = customIncludeHeaders
        oai["custom_exclude_body"] = customExcludeBody
        if seed > 0 { oai["seed"] = seed }
        let stops = stopSequences.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !stops.isEmpty { oai["stop"] = stops }

        settingsJSON["oai_settings"] = oai
        // Also update root-level repetition_penalty for compatibility
        settingsJSON["repetition_penalty"] = repetitionPenalty
        if !extensionSettings.isEmpty { settingsJSON["extensions"] = extensionSettings }

        dirty = false
        do {
            // Save API key if provided
            if !apiKey.isEmpty {
                let keyBody = STSecretWriteBody(key: currentSecretKey, value: apiKey)
                _ = try? await (client.post("/api/secrets/write", body: keyBody) as [String: String])
            }
            let data = try JSONSerialization.data(withJSONObject: settingsJSON, options: [])
            _ = try await client.postRawData("/api/settings/save", rawBody: data)
            print("[Settings] Saved: source=\(self.chatCompletionSource) model=\(self.model)")
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
            print("[Settings] Save FAILED: \(error.localizedDescription)")
            dirty = true
        }
        savePending = false
        if dirty {
            scheduleSave()
        }
    }

    // MARK: - Reset

    @MainActor
    func resetSection(_ section: SettingsSection) {
        switch section {
        case .sampling:
            temperature = 0.7; maxTokens = 200; maxCompletionTokens = 0
            topP = 1.0; topK = 0; frequencyPenalty = 0.0; presencePenalty = 0.0
            repetitionPenalty = 1.0; streamEnabled = true; seed = 0
        case .api:
            chatCompletionSource = "openai"; model = ""; reverseProxy = ""; customURL = ""
            proxyPassword = ""; customIncludeBody = ""; customIncludeHeaders = ""; customExcludeBody = ""
        }
        scheduleSave()
    }

    @MainActor
    func factoryReset() {
        settingsJSON = DefaultSettings.defaults
        hydrate(from: DefaultSettings.defaults)
        scheduleSave()
    }

    // MARK: - Presets

    /// Load a preset by name for the current chat_completion_source
    func loadPreset(_ name: String) {
        let key = presetKeyForSource
        guard let contents = presetContents[key] else { return }
        // Find the matching preset — contents are JSON strings
        for item in contents {
            let json: [String: Any]?
            if let str = item as? String, let data = str.data(using: .utf8) {
                json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            } else if let dict = item as? [String: Any] {
                json = dict
            } else { continue }

            guard let preset = json else { continue }
            // Some presets are keyed by name differently — try common patterns
            if let presetName = preset["name"] as? String, presetName == name {
                applyPresetValues(preset)
                return
            }
            // Also check if it's wrapped: the settings response gives arrays of JSON strings
        }
        // If not found in contents, try by index in presetNames
        if let names = presetNames[key], let idx = names.firstIndex(of: name),
           idx < contents.count {
            if let str = contents[idx] as? String, let data = str.data(using: .utf8),
               let preset = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                applyPresetValues(preset)
            } else if let preset = contents[idx] as? [String: Any] {
                applyPresetValues(preset)
            }
        }
    }

    private func applyPresetValues(_ preset: [String: Any]) {
        if let v = preset["model"] as? String { model = v }
        if let v = preset["temperature"] as? Double, v != 0 { temperature = v }
        if let v = preset["max_tokens"] as? Int, v != 0 { maxTokens = v }
        if let v = preset["max_completion_tokens"] as? Int { maxCompletionTokens = v }
        if let v = preset["top_p"] as? Double { topP = v }
        if let v = preset["top_k"] as? Int { topK = v }
        if let v = preset["frequency_penalty"] as? Double { frequencyPenalty = v }
        if let v = preset["presence_penalty"] as? Double { presencePenalty = v }
        if let v = preset["repetition_penalty"] as? Double { repetitionPenalty = v }
        if let v = preset["stop"] as? [String] { stopSequences = v.joined(separator: ", ") }
        if let v = preset["seed"] as? Int, v != 0 { seed = v }
        scheduleSave()
    }

    // MARK: - Import / Export

    func exportData() -> Data? {
        try? JSONSerialization.data(withJSONObject: settingsJSON, options: .prettyPrinted)
    }

    @MainActor
    func importSettings(from data: Data) {
        guard let imported = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            errorMessage = "Invalid settings file"
            return
        }
        settingsJSON = settingsJSON.merging(imported) { _, new in new }
        hydrate(from: settingsJSON)
        scheduleSave()
        isLoading = false
    }
}

enum SettingsSection: String, CaseIterable {
    case api, sampling
}

// MARK: - Binding helpers

extension SettingsStore {
    var temperatureBinding: Binding<Double> {
        Binding(get: { self.temperature }, set: { self.temperature = $0; self.markDirty() })
    }
    var maxTokensBinding: Binding<Double> {
        Binding(get: { Double(self.maxTokens) }, set: { self.maxTokens = Int($0); self.markDirty() })
    }
    var maxCompletionTokensBinding: Binding<Double> {
        Binding(get: { Double(self.maxCompletionTokens) }, set: { self.maxCompletionTokens = Int($0); self.markDirty() })
    }
    var topPBinding: Binding<Double> {
        Binding(get: { self.topP }, set: { self.topP = $0; self.markDirty() })
    }
    var topKBinding: Binding<Double> {
        Binding(get: { Double(self.topK) }, set: { self.topK = Int($0); self.markDirty() })
    }
    var frequencyPenaltyBinding: Binding<Double> {
        Binding(get: { self.frequencyPenalty }, set: { self.frequencyPenalty = $0; self.markDirty() })
    }
    var presencePenaltyBinding: Binding<Double> {
        Binding(get: { self.presencePenalty }, set: { self.presencePenalty = $0; self.markDirty() })
    }
    var repetitionPenaltyBinding: Binding<Double> {
        Binding(get: { self.repetitionPenalty }, set: { self.repetitionPenalty = $0; self.markDirty() })
    }
    var streamBinding: Binding<Bool> {
        Binding(get: { self.streamEnabled }, set: { self.streamEnabled = $0; self.markDirty() })
    }
    var chatCompletionSourceBinding: Binding<String> {
        Binding(get: { self.chatCompletionSource }, set: { self.chatCompletionSource = $0; self.markDirty() })
    }
    var modelBinding: Binding<String> {
        Binding(get: { self.model }, set: { self.model = $0; self.markDirty() })
    }
    var reverseProxyBinding: Binding<String> {
        Binding(get: { self.reverseProxy }, set: { self.reverseProxy = $0; self.markDirty() })
    }
    var customURLBinding: Binding<String> {
        Binding(get: { self.customURL }, set: { self.customURL = $0; self.markDirty() })
    }
    var proxyPasswordBinding: Binding<String> {
        Binding(get: { self.proxyPassword }, set: { self.proxyPassword = $0; self.markDirty() })
    }
    var customIncludeBodyBinding: Binding<String> {
        Binding(get: { self.customIncludeBody }, set: { self.customIncludeBody = $0; self.markDirty() })
    }
    var customIncludeHeadersBinding: Binding<String> {
        Binding(get: { self.customIncludeHeaders }, set: { self.customIncludeHeaders = $0; self.markDirty() })
    }
    var customExcludeBodyBinding: Binding<String> {
        Binding(get: { self.customExcludeBody }, set: { self.customExcludeBody = $0; self.markDirty() })
    }
    var stopSequencesBinding: Binding<String> {
        Binding(get: { self.stopSequences }, set: { self.stopSequences = $0; self.markDirty() })
    }
    var selectedPresetBinding: Binding<String> {
        Binding(get: { self.selectedPreset }, set: { self.selectedPreset = $0; self.markDirty() })
    }
    var apiKeyBinding: Binding<String> {
        Binding(get: { self.apiKey }, set: { self.apiKey = $0; self.markDirty() })
    }
}

struct STSecretWriteBody: Codable {
    let key: String
    let value: String
}
