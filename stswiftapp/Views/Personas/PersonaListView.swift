import SwiftUI
import Observation

@Observable
final class PersonaListViewModel {
    var personas: [STPersona] = []
    var isLoading = false
    var errorMessage: String?
    var settingsJSON: [String: Any] = [:]

    private let client = STAPIClient.shared

    func loadPersonas() async {
        isLoading = true
        errorMessage = nil
        do {
            let data = try await client.postRaw("/api/settings/get", body: EmptyBody())
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let settingsStr = json["settings"] as? String,
                  let settingsData = settingsStr.data(using: .utf8),
                  let settings = try JSONSerialization.jsonObject(with: settingsData) as? [String: Any] else {
                throw STAPIError.decodingFailed(NSError(domain: "", code: -1))
            }
            settingsJSON = settings

            let powerUser = settings["power_user"] as? [String: Any] ?? [:]
            if let personaData = powerUser["personas"] as? [String: Any] {
                personas = personaData.map { (key, value) in
                    let dict = value as? [String: Any] ?? [:]
                    return STPersona(
                        name: key,
                        description: dict["description"] as? String ?? "",
                        avatar: dict["avatar"] as? String
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func savePersonas() async throws {
        var powerUser = settingsJSON["power_user"] as? [String: Any] ?? [:]
        var personaDict: [String: [String: String]] = [:]
        for persona in personas {
            personaDict[persona.name] = [
                "description": persona.description,
                "avatar": persona.avatar ?? ""
            ]
        }
        powerUser["personas"] = personaDict
        settingsJSON["power_user"] = powerUser

        let data = try JSONSerialization.data(withJSONObject: settingsJSON, options: .prettyPrinted)
        let jsonStr = String(data: data, encoding: .utf8) ?? "{}"
        let body = ["settings": jsonStr]
        let _: [String: String] = try await client.post("/api/settings/save", body: body)
    }

    func deletePersona(_ persona: STPersona) async {
        personas.removeAll { $0.name == persona.name }
        do {
            try await savePersonas()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PersonaListView: View {
    @State private var viewModel = PersonaListViewModel()
    @State private var showCreateSheet = false

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
                        NavigationLink {
                            PersonaEditView(persona: persona) { updatedPersona in
                                if let idx = viewModel.personas.firstIndex(where: { $0.name == persona.name }) {
                                    viewModel.personas[idx] = updatedPersona
                                }
                                Task { try? await viewModel.savePersonas() }
                            }
                        } label: {
                            PersonaRow(persona: persona)
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            Task { await viewModel.deletePersona(viewModel.personas[idx]) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Personas")
        .task { await viewModel.loadPersonas() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            PersonaCreateView { newPersona in
                viewModel.personas.append(newPersona)
                Task { try? await viewModel.savePersonas() }
            }
        }
    }
}

struct PersonaRow: View {
    let persona: STPersona

    var body: some View {
        HStack(spacing: 12) {
            STAuthAsyncImage(avatar: persona.avatar, name: persona.name, cornerRadius: 20, size: 40)
                .clipShape(Circle())

            VStack(alignment: .leading) {
                Text(persona.name).font(.headline)
                if !persona.description.isEmpty {
                    Text(persona.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct PersonaCreateView: View {
    var onCreated: (STPersona) -> Void

    @State private var name = ""
    @State private var description = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextEditorWithPlaceholder(text: $description, placeholder: "Description")
                    .frame(minHeight: 100)
            }
            .navigationTitle("New Persona")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreated(STPersona(name: name, description: description))
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

struct PersonaEditView: View {
    let persona: STPersona
    var onSave: (STPersona) -> Void

    @State private var name: String
    @State private var description: String
    @Environment(\.dismiss) private var dismiss

    init(persona: STPersona, onSave: @escaping (STPersona) -> Void) {
        self.persona = persona
        self.onSave = onSave
        _name = State(initialValue: persona.name)
        _description = State(initialValue: persona.description)
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)
            TextEditorWithPlaceholder(text: $description, placeholder: "Description")
                .frame(minHeight: 100)
        }
        .navigationTitle("Edit Persona")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(STPersona(name: name, description: description, avatar: persona.avatar))
                    dismiss()
                }
                .disabled(name.isEmpty)
            }
        }
    }
}
