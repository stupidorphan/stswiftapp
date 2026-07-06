import SwiftUI
import Observation
import UniformTypeIdentifiers

// MARK: - Settings View

struct SettingsView: View {
    @Environment(STAppViewModel.self) private var appViewModel
    @State private var store = SettingsStore.shared
    @State private var showFactoryReset = false
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var exportData: Data?
    @State private var showCustomModelField = false
    @State private var selectedModelOption: String = ""
    private let customModelSentinel = "__custom__"

    let providers = ["openai", "claude", "openrouter", "custom", "groq", "deepseek", "mistralai", "cohere", "perplexity", "xai", "fireworks", "makersuite", "vertexai", "ai21", "chutes", "electronhub", "nanogpt", "aimlapi", "pollinations", "cometapi", "moonshot", "azure_openai", "zai", "siliconflow", "minimax", "workers_ai"]

    var body: some View {
        NavigationStack {
            List {
                // MARK: API
                Section {
                    Picker("Provider", selection: store.chatCompletionSourceBinding) {
                        ForEach(providers, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .onChange(of: store.chatCompletionSource) { _, _ in
                        Task { await store.fetchModels() }
                    }

                    if store.chatCompletionSource == "custom" {
                        TextField("Model", text: store.modelBinding)
                            .autocapitalization(.none).font(.body)
                    } else if store.availableModels.isEmpty {
                        HStack {
                            TextField("Model", text: store.modelBinding)
                                .autocapitalization(.none).font(.body)
                            Button { Task { await store.fetchModels() } } label: {
                                if store.isLoadingModels { ProgressView().controlSize(.small) }
                                else { Image(systemName: "arrow.down.circle") }
                            }
                        }
                    } else {
                        Picker("Model", selection: $selectedModelOption) {
                            ForEach(store.availableModels, id: \.self) { Text($0).tag($0) }
                            Text("Custom model…").tag(customModelSentinel)
                        }
                        .onChange(of: selectedModelOption) { _, newValue in
                            if newValue == customModelSentinel {
                                showCustomModelField = true
                            } else {
                                store.model = newValue
                                showCustomModelField = false
                            }
                        }
                        if showCustomModelField {
                            TextField("Enter custom model name", text: store.modelBinding)
                                .autocapitalization(.none).font(.body)
                        }
                    }

                    if store.chatCompletionSource == "custom" {
                        TextField("Custom Endpoint (Base URL)", text: store.customURLBinding)
                            .autocapitalization(.none)
                    }

                    SecureField("API Key", text: store.apiKeyBinding)
                        .autocapitalization(.none)

                    if !store.currentPresetNames.isEmpty {
                        Picker("Preset", selection: store.selectedPresetBinding) {
                            Text("None").tag("")
                            ForEach(store.currentPresetNames, id: \.self) { Text($0).tag($0) }
                        }
                        if !store.selectedPreset.isEmpty {
                            Button("Load Preset") { store.loadPreset(store.selectedPreset) }
                        }
                    }
                } header: {
                    Label("API Provider", systemImage: "server.rack")
                } footer: {
                    if let err = store.errorMessage { Text(err).foregroundStyle(.red) }
                }

                // MARK: Sampling
                Section {
                    EditableSlider(label: "Temperature", systemImage: "thermometer.medium", value: store.temperatureBinding, range: 0...2, step: 0.05, helpText: "Controls randomness.")
                    EditableSlider(label: "Max Tokens", systemImage: "text.alignleft", value: store.maxTokensBinding, range: 1...128000, step: 100, format: "%.0f", helpText: "Maximum response length.")
                } header: {
                    Label("Basic", systemImage: "slider.horizontal.3")
                }

                Section {
                    EditableSlider(label: "Top P", systemImage: "chart.bar", value: store.topPBinding, range: 0...1, step: 0.05, helpText: "Nucleus sampling threshold.")
                    EditableSlider(label: "Top K", systemImage: "list.number", value: store.topKBinding, range: 0...200, step: 1, format: "%.0f", helpText: "Limits token pool to top K.")
                    EditableSlider(label: "Frequency Penalty", systemImage: "repeat", value: store.frequencyPenaltyBinding, range: -2...2, step: 0.05)
                    EditableSlider(label: "Presence Penalty", systemImage: "person.badge.minus", value: store.presencePenaltyBinding, range: -2...2, step: 0.05)
                    EditableSlider(label: "Repetition Penalty", systemImage: "arrow.triangle.2.circlepath", value: store.repetitionPenaltyBinding, range: 1...2, step: 0.05)
                    EditableSlider(label: "Max Completion", systemImage: "arrow.right.to.line", value: store.maxCompletionTokensBinding, range: 0...128000, step: 100, format: "%.0f")
                    Toggle("Stream", isOn: store.streamBinding)
                    TextField("Stop sequences (comma-separated)", text: store.stopSequencesBinding)
                        .font(.caption)
                } header: {
                    Label("Advanced", systemImage: "gearshape.2")
                }

                // MARK: Presets
                Section {
                    ForEach(store.currentPresetNames, id: \.self) { name in
                        HStack {
                            Text(name).font(.body)
                            Spacer()
                            Button("Apply") { store.loadPreset(name) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                } header: {
                    Label("Presets", systemImage: "rectangle.stack")
                }

                // MARK: Connection
                Section {
                    LabeledContent("Server", value: appViewModel.serverConfig.displayURL)
                    LabeledContent("Auth", value: appViewModel.serverConfig.authMode.displayName)
                    Button {
                        Task { await testConnection() }
                    } label: {
                        Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                    }
                } header: {
                    Label("Connection", systemImage: "network")
                }

                // MARK: Personas
                Section {
                    NavigationLink {
                        PersonaListView()
                    } label: {
                        Label("Manage Personas", systemImage: "person.text.rectangle")
                    }
                } header: {
                    Label("Personas", systemImage: "person.crop.circle")
                }

                // MARK: World Info
                Section {
                    NavigationLink {
                        WorldInfoListView()
                    } label: {
                        Label("Manage Lorebooks", systemImage: "book.pages")
                    }
                } header: {
                    Label("World Info", systemImage: "globe")
                }

                // MARK: Appearance
                Section {
                    ColorPicker("Quote Color", selection: Binding(
                        get: { QuoteColorSettings.shared.quoteColor },
                        set: { QuoteColorSettings.shared.quoteColor = $0 }
                    ))
                } header: {
                    Label("Appearance", systemImage: "paintbrush")
                } footer: {
                    Text("Color applied to quoted text in chats.")
                }

                // MARK: Reset
                Section {
                    Button(role: .destructive) {
                        store.resetSection(.api)
                    } label: { Label("Reset API defaults", systemImage: "arrow.counterclockwise") }

                    Button(role: .destructive) {
                        store.resetSection(.sampling)
                    } label: { Label("Reset sampling defaults", systemImage: "arrow.counterclockwise") }
                } header: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }

                // MARK: Data
                Section {
                    Button { exportSettings() } label: {
                        Label("Export all settings", systemImage: "square.and.arrow.up")
                    }
                    Button { showImporter = true } label: {
                        Label("Import settings", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Label("Data", systemImage: "doc")
                }

                // MARK: Disconnect
                Section {
                    Button(role: .destructive) { showFactoryReset = true } label: {
                        Label("Factory reset all settings", systemImage: "exclamationmark.triangle")
                    }
                    Button(role: .destructive) { appViewModel.disconnect() } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 8) {
                        if store.savePending {
                            ProgressView()
                        }
                        Button("Save") {
                            store.saveNow()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!store.dirty)
                    }
                }
            }
            .task {
                await store.load()
                if store.chatCompletionSource != "custom" {
                    await store.fetchModels()
                }
            }
            .onChange(of: store.availableModels) { _, models in
                if !models.isEmpty {
                    if models.contains(store.model) {
                        selectedModelOption = store.model
                        showCustomModelField = false
                    } else if !store.model.isEmpty {
                        selectedModelOption = customModelSentinel
                        showCustomModelField = true
                    }
                }
            }
            .alert("Factory Reset", isPresented: $showFactoryReset) {
                Button("Reset", role: .destructive) { store.factoryReset() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Restore all settings to defaults. Cannot be undone.") }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result, let data = try? Data(contentsOf: url) {
                    store.importSettings(from: data)
                }
            }
            .fileExporter(isPresented: $showExporter, document: JSONFileDocument(data: exportData ?? Data()), contentType: .json, defaultFilename: "st-settings.json", onCompletion: { _ in })
        }
    }

    private func exportSettings() {
        if let data = store.exportData() { exportData = data; showExporter = true }
    }

    private func testConnection() async {
        let body = STConnectionTestBody(chat_completion_source: store.chatCompletionSource, reverse_proxy: store.reverseProxy, custom_url: store.customURL, proxy_password: store.proxyPassword, custom_include_headers: store.customIncludeHeaders)
        do {
            let _ = try await STAPIClient.shared.postRaw("/api/backends/chat-completions/status", body: body)
            store.errorMessage = nil
        } catch {
            store.errorMessage = "Connection failed: \(error.localizedDescription)"
        }
    }

}

struct STConnectionTestBody: Codable {
    let chat_completion_source: String; let reverse_proxy: String; let custom_url: String
    let proxy_password: String; let custom_include_headers: String
}
struct STPresetGetBody: Codable { let name: String }
