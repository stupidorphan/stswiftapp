import SwiftUI
import Observation

@Observable
final class GroupListViewModel {
    var groups: [STGroup] = []
    var isLoading = false
    var errorMessage: String?

    private let client = STAPIClient.shared

    func loadGroups() async {
        isLoading = true
        errorMessage = nil
        do {
            groups = try await client.postArray("/api/groups/all", body: EmptyBody())
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func deleteGroup(_ group: STGroup) async {
        do {
            let body = ["id": group.id]
            let _: [String: String] = try await client.post("/api/groups/delete", body: body)
            await loadGroups()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GroupListView: View {
    @State private var viewModel = GroupListViewModel()
    @State private var showCreateSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.groups.isEmpty {
                    ProgressView("Loading groups...")
                } else if viewModel.groups.isEmpty {
                    ContentUnavailableView(
                        "No Groups",
                        systemImage: "person.3",
                        description: Text("Create a group to chat with multiple characters")
                    )
                } else {
                    List {
                        ForEach(viewModel.groups) { group in
                            NavigationLink {
                                ChatView(
                                    character: STCharacter.groupPlaceholder(name: group.name, avatar: group.avatarURL ?? ""),
                                    chat: STChat.groupPlaceholder(id: group.id, name: group.name, avatar: group.avatarURL)
                                )
                            } label: {
                                GroupRow(group: group)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteGroup(group) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await viewModel.loadGroups() }
                }
            }
            .navigationTitle("Groups")
            .task { await viewModel.loadGroups() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreateSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                GroupCreateView { await viewModel.loadGroups() }
            }
        }
    }
}

struct GroupRow: View {
    let group: STGroup

    var body: some View {
        HStack(spacing: 12) {
            STAuthAsyncImage(avatar: group.avatarURL, name: group.name, isGroup: true, cornerRadius: 24, size: 48)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)
                Text("\(group.members.count) members")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct STGroupCreateBody: Codable {
    let name: String
    let members: [String]
    let allowSelfResponses: Bool
    let activationStrategy: Int
    let generationMode: Int

    enum CodingKeys: String, CodingKey {
        case name, members
        case allowSelfResponses = "allow_self_responses"
        case activationStrategy = "activation_strategy"
        case generationMode = "generation_mode"
    }
}

struct GroupCreateView: View {
    var onCreated: () async -> Void

    @State private var name = ""
    @State private var membersInput = ""
    @State private var allowSelfResponses = false
    @State private var activationStrategy = 0
    @State private var generationMode = 0
    @State private var isCreating = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss
    private let client = STAPIClient.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Info") {
                    TextField("Group Name", text: $name)
                    TextField("Members (comma-separated avatar filenames, e.g. avatar1.png, avatar2.png)", text: $membersInput)
                }

                Section("Behavior") {
                    Toggle("Allow self-responses", isOn: $allowSelfResponses)
                    Picker("Activation Strategy", selection: $activationStrategy) {
                        Text("Natural").tag(0)
                        Text("List").tag(1)
                    }
                    Picker("Generation Mode", selection: $generationMode) {
                        Text("Joined").tag(0)
                        Text("Separate").tag(1)
                    }
                }

                if let error = errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section {
                    Button(action: create) {
                        HStack {
                            Spacer()
                            if isCreating { ProgressView() } else { Text("Create").bold() }
                            Spacer()
                        }
                    }
                    .disabled(name.isEmpty || membersInput.isEmpty || isCreating)
                }
            }
            .navigationTitle("New Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func create() {
        isCreating = true
        let members = membersInput.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        let body = STGroupCreateBody(
            name: name,
            members: members,
            allowSelfResponses: allowSelfResponses,
            activationStrategy: activationStrategy,
            generationMode: generationMode
        )

        Task {
            do {
                let _: STGroup = try await client.post("/api/groups/create", body: body)
                await MainActor.run {
                    dismiss()
                    Task { await onCreated() }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}
