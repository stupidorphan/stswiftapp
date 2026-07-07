import SwiftUI
import Observation
import PhotosUI

// MARK: - ViewModel

@Observable
final class PersonaListViewModel {
    var personas: [STPersona] = []
    var availableAvatars: [String] = [] // Raw avatar filenames from /api/avatars/get
    var isLoading = false
    var errorMessage: String?
    var selectedPersonaId: String? // The currently active persona's avatarId

    /// Full parsed settings dict (top-level keys like power_user, etc.)
    private var settingsJSON: [String: Any] = [:]

    private let client = STAPIClient.shared

    // MARK: - Load

    func loadPersonas() async {
        isLoading = true
        errorMessage = nil
        do {
            // 1. Fetch avatar list
            let avatarData = try await client.postRaw("/api/avatars/get", body: Optional<String>.none)
            if let avatarArray = try JSONSerialization.jsonObject(with: avatarData) as? [String] {
                availableAvatars = avatarArray
            }

            // 2. Fetch settings
            try await loadSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadSettings() async throws {
        let data = try await client.postRaw("/api/settings/get", body: Optional<String>.none)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settingsStr = json["settings"] as? String,
              let settingsData = settingsStr.data(using: .utf8),
              let settings = try JSONSerialization.jsonObject(with: settingsData) as? [String: Any] else {
            throw STAPIError.decodingFailed(NSError(domain: "", code: -1))
        }
        settingsJSON = settings

        let powerUser = settings["power_user"] as? [String: Any] ?? [:]
        let personasDict = powerUser["personas"] as? [String: Any] ?? [:]
        let descriptionsDict = powerUser["persona_descriptions"] as? [String: Any] ?? [:]
        let defaultPersona = powerUser["default_persona"] as? String
        let currentAvatar = settings["user_avatar"] as? String

        selectedPersonaId = currentAvatar

        personas = personasDict.compactMap { (avatarId, value) -> STPersona? in
            let name = value as? String ?? "[Unnamed]"
            let desc = descriptionsDict[avatarId] as? [String: Any] ?? [:]
            return STPersona(
                avatarId: avatarId,
                name: name,
                description: desc["description"] as? String ?? "",
                title: desc["title"] as? String ?? "",
                position: desc["position"] as? Int ?? 0,
                depth: desc["depth"] as? Int ?? 2,
                role: desc["role"] as? Int ?? 0,
                lorebook: desc["lorebook"] as? String ?? "",
                isDefault: defaultPersona == avatarId
            )
        }.sorted { sortIgnoreCase($0.name, $1.name) }
    }

    private func sortIgnoreCase(_ a: String, _ b: String) -> Bool {
        a.localizedCaseInsensitiveCompare(b) == .orderedAscending
    }

    // MARK: - Save settings

    func saveSettings() async throws {
        var powerUser = settingsJSON["power_user"] as? [String: Any] ?? [:]

        // Rebuild personas and persona_descriptions dicts
        var personasDict: [String: String] = [:]
        var descriptionsDict: [String: [String: Any]] = [:]

        for p in personas {
            personasDict[p.avatarId] = p.name
            descriptionsDict[p.avatarId] = [
                "description": p.description,
                "title": p.title,
                "position": p.position,
                "depth": p.depth,
                "role": p.role,
                "lorebook": p.lorebook,
                "connections": (settingsJSON["power_user"] as? [String: Any])
                    .flatMap { $0["persona_descriptions"] as? [String: Any] }
                    .flatMap { $0[p.avatarId] as? [String: Any] }
                    .flatMap { $0["connections"] } ?? [],
            ]
        }

        powerUser["personas"] = personasDict
        powerUser["persona_descriptions"] = descriptionsDict
        settingsJSON["power_user"] = powerUser

        // SillyTavern expects the raw settings JSON as the request body
        let rawBody = try JSONSerialization.data(withJSONObject: settingsJSON)
        let _ = try await client.postRawData("/api/settings/save", rawBody: rawBody)
    }

    // MARK: - CRUD

    func createPersona(name: String, description: String, title: String, avatarData: Data?) async {
        do {
            let avatarId: String
            if let avatarData = avatarData {
                // Upload the avatar first
                let uploadResp = try await client.postMultipart("/api/avatars/upload",
                    formData: ["avatar": avatarData])
                if let json = try JSONSerialization.jsonObject(with: uploadResp) as? [String: Any],
                   let path = json["path"] as? String {
                    avatarId = path
                } else {
                    // Fallback: generate a unique avatar ID
                    avatarId = "\(Int(Date().timeIntervalSince1970 * 1000))-\(name.replacingOccurrences(of: "[^a-zA-Z0-9]", with: "", options: .regularExpression)).png"
                }
                availableAvatars.append(avatarId)
            } else {
                // Use default avatar
                avatarId = "user-default.png"
                if !availableAvatars.contains(avatarId) {
                    // Create a dummy persona with default avatar
                }
            }

            let persona = STPersona(
                avatarId: avatarId,
                name: name,
                description: description,
                title: title,
                position: 0,
                depth: 2,
                role: 0,
                lorebook: "",
                isDefault: false
            )
            personas.append(persona)
            try await saveSettings()
            await loadPersonas() // Refresh to get any server-side changes
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updatePersona(_ persona: STPersona) async {
        if let idx = personas.firstIndex(where: { $0.avatarId == persona.avatarId }) {
            personas[idx] = persona
            do {
                try await saveSettings()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deletePersona(_ persona: STPersona) async {
        do {
            // Delete avatar file from server
            let body = ["avatar": persona.avatarId]
            let _ = try await client.post("/api/avatars/delete", body: body) as [String: String]
            availableAvatars.removeAll { $0 == persona.avatarId }
            personas.removeAll { $0.avatarId == persona.avatarId }
            try await saveSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setDefaultPersona(_ persona: STPersona) async {
        var powerUser = settingsJSON["power_user"] as? [String: Any] ?? [:]
        powerUser["default_persona"] = persona.avatarId
        settingsJSON["power_user"] = powerUser

        // Update local state
        for i in personas.indices { personas[i].isDefault = (personas[i].avatarId == persona.avatarId) }
        do {
            let rawBody = try JSONSerialization.data(withJSONObject: settingsJSON)
            let _ = try await client.postRawData("/api/settings/save", rawBody: rawBody)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectPersona(_ persona: STPersona) async {
        settingsJSON["user_avatar"] = persona.avatarId
        selectedPersonaId = persona.avatarId
        do {
            let rawBody = try JSONSerialization.data(withJSONObject: settingsJSON)
            let _ = try await client.postRawData("/api/settings/save", rawBody: rawBody)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Persona List View

struct PersonaListView: View {
    @State private var viewModel = PersonaListViewModel()
    @State private var showCreateSheet = false
    @State private var showEditSheet: STPersona?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.personas.isEmpty {
                ProgressView("Loading personas...")
            } else if viewModel.personas.isEmpty {
                ContentUnavailableView(
                    "No Personas",
                    systemImage: "person.text.rectangle",
                    description: Text("Create a persona to represent you in chats")
                )
            } else {
                List {
                    ForEach(viewModel.personas) { persona in
                        PersonaRow(
                            persona: persona,
                            isSelected: viewModel.selectedPersonaId == persona.avatarId
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await viewModel.selectPersona(persona) }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.deletePersona(persona) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                showEditSheet = persona
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .contextMenu {
                            Button {
                                Task { await viewModel.selectPersona(persona) }
                            } label: {
                                Label("Use Persona", systemImage: "checkmark")
                            }
                            Button {
                                showEditSheet = persona
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button {
                                Task { await viewModel.setDefaultPersona(persona) }
                            } label: {
                                Label("Set as Default", systemImage: "star")
                            }
                            Divider()
                            Button(role: .destructive) {
                                Task { await viewModel.deletePersona(persona) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Personas")
        .task { await viewModel.loadPersonas() }
        .refreshable { await viewModel.loadPersonas() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            PersonaCreateView { name, description, title, avatarData in
                Task { await viewModel.createPersona(name: name, description: description, title: title, avatarData: avatarData) }
            }
        }
        .sheet(item: $showEditSheet) { persona in
            PersonaEditView(persona: persona) { updated in
                Task { await viewModel.updatePersona(updated) }
            }
        }
    }
}

// MARK: - Persona Row

struct PersonaRow: View {
    let persona: STPersona
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            PersonaThumbnail(avatarId: persona.avatarId, size: 44)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(persona.name).font(.headline)
                    if persona.isDefault {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                if !persona.title.isEmpty {
                    Text(persona.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !persona.description.isEmpty {
                    Text(persona.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Thumbnail

struct PersonaThumbnail: View {
    let avatarId: String
    var size: CGFloat = 44

    var body: some View {
        STAuthAsyncImage(avatar: avatarId, name: "", cornerRadius: size / 2, size: size)
    }
}

// MARK: - Create View

struct PersonaCreateView: View {
    var onCreated: (String, String, String, Data?) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var title = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarData: Data?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Avatar") {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            if let avatarData = avatarData,
                               let uiImage = UIImage(data: avatarData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .frame(width: 80, height: 80)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }

                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Title (optional)", text: $title)
                }

                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("New Persona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreated(name, description, title, avatarData)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        avatarData = data
                    }
                }
            }
        }
    }
}

// MARK: - Edit View

struct PersonaEditView: View {
    let persona: STPersona
    var onSave: (STPersona) -> Void

    @State private var name: String
    @State private var description: String
    @State private var title: String
    @State private var position: Int
    @State private var depth: Int
    @State private var role: Int
    @Environment(\.dismiss) private var dismiss

    init(persona: STPersona, onSave: @escaping (STPersona) -> Void) {
        self.persona = persona
        self.onSave = onSave
        _name = State(initialValue: persona.name)
        _description = State(initialValue: persona.description)
        _title = State(initialValue: persona.title)
        _position = State(initialValue: persona.position)
        _depth = State(initialValue: persona.depth)
        _role = State(initialValue: persona.role)
    }

    var body: some View {
        Form {
            Section("Avatar") {
                HStack {
                    Spacer()
                    PersonaThumbnail(avatarId: persona.avatarId, size: 80)
                        .clipShape(Circle())
                    Spacer()
                }
            }

            Section("Details") {
                TextField("Name", text: $name)
                TextField("Title (optional)", text: $title)
            }

            Section("Description") {
                TextEditor(text: $description)
                    .frame(minHeight: 100)
            }

            Section("Description Position") {
                Picker("Position", selection: $position) {
                    Text("In Prompt").tag(0)
                    Text("Top AN").tag(2)
                    Text("Bottom AN").tag(3)
                    Text("At Depth").tag(4)
                    Text("None").tag(9)
                }
            }

            if position == 4 {
                Section("Depth") {
                    Stepper("Depth: \(depth)", value: $depth, in: 0...10)
                }
            }

            Section("Role") {
                Picker("Role", selection: $role) {
                    Text("System").tag(0)
                    Text("User").tag(1)
                    Text("Assistant").tag(2)
                }
            }
        }
        .navigationTitle("Edit Persona")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var updated = persona
                    updated.name = name
                    updated.description = description
                    updated.title = title
                    updated.position = position
                    updated.depth = depth
                    updated.role = role
                    onSave(updated)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

// MARK: - Equatable conformance for sheet item

extension STPersona: Equatable {}
