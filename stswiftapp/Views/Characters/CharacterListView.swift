import SwiftUI

// MARK: - Character Detail View (collapsible, creator notes first, edit in nav bar)

struct CharacterDetailView: View {
    let character: STCharacter
    @State private var descExpanded = false
    @State private var firstMesExpanded = false
    @State private var personalityExpanded = false
    @State private var scenarioExpanded = false
    @State private var mesExampleExpanded = false
    @State private var showConversations = false
    @State private var conversationVM = ChatViewModel(character: STCharacter.groupPlaceholder(name: "", avatar: ""), chat: nil)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Avatar
                HStack {
                    Spacer()
                    STAuthAsyncImage(avatar: character.avatar, name: character.name, cornerRadius: 16, size: 100)
                    Spacer()
                }
                .padding(.top, 16)

                // Name
                VStack(spacing: 4) {
                    Text(character.name)
                        .font(.title.bold())
                    if !character.creator.isEmpty {
                        Text("by \(character.creator)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !character.tags.isEmpty {
                        Text(character.tags.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Divider()

                // Creator's Notes FIRST
                if !character.creatorNotes.isEmpty {
                    MarkdownText(text: character.creatorNotes)
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Collapsible sections
                CollapsibleTextSection(title: "Description", text: character.description, expanded: $descExpanded)
                CollapsibleTextSection(title: "Personality", text: character.personality, expanded: $personalityExpanded)
                CollapsibleTextSection(title: "Scenario", text: character.scenario, expanded: $scenarioExpanded)
                CollapsibleTextSection(title: "First Message", text: character.firstMes, expanded: $firstMesExpanded)

                if !character.mesExample.isEmpty {
                    CollapsibleTextSection(title: "Example Messages", text: character.mesExample, expanded: $mesExampleExpanded)
                }

                if !character.systemPrompt.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("System Prompt").font(.headline).foregroundStyle(.secondary)
                        Text(character.systemPrompt).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        conversationVM = ChatViewModel(character: character, chat: nil)
                        Task { await conversationVM.fetchConversations(); showConversations = true }
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    NavigationLink {
                        CharacterEditView(existingCharacter: character)
                    } label: {
                        Text("Edit")
                    }
                }
            }
        }
        .sheet(isPresented: $showConversations) {
            ConversationPickerSheet(viewModel: conversationVM)
        }
    }
}

// MARK: - Collapsible Section

struct CollapsibleTextSection: View {
    let title: String
    let text: String
    @Binding var expanded: Bool

    private let previewLines = 3

    var body: some View {
        if text.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(text)
                    .font(.body)
                    .lineLimit(expanded ? nil : previewLines)

                if textHasMore {
                    Button(expanded ? "Show less" : "Show more") {
                        withAnimation { expanded.toggle() }
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
            }
        }
    }

    private var textHasMore: Bool {
        let lines = text.components(separatedBy: "\n")
        if lines.count > previewLines { return true }
        // Rough char count
        return text.count > previewLines * 80
    }
}

// MARK: - Character Edit View

struct CharacterEditView: View {
    var existingCharacter: STCharacter?

    @State private var name = ""
    @State private var description = ""
    @State private var personality = ""
    @State private var scenario = ""
    @State private var firstMessage = ""
    @State private var mesExample = ""
    @State private var creatorNotes = ""
    @State private var tags = ""
    @State private var creator = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss
    private let client = STAPIClient.shared

    var body: some View {
        Form {
            Section("Basic Info") {
                TextField("Name", text: $name)
                TextField("Creator", text: $creator)
                TextField("Tags (comma-separated)", text: $tags)
            }
            Section("Creator's Notes (Markdown)") {
                TextEditor(text: $creatorNotes)
                    .frame(minHeight: 100)
                    .font(.body)
            }
            Section("Content") {
                TextEditorWithPlaceholder(text: $description, placeholder: "Description")
                    .frame(minHeight: 70)
                TextEditorWithPlaceholder(text: $personality, placeholder: "Personality")
                    .frame(minHeight: 70)
                TextEditorWithPlaceholder(text: $scenario, placeholder: "Scenario")
                    .frame(minHeight: 70)
                TextEditorWithPlaceholder(text: $firstMessage, placeholder: "First Message")
                    .frame(minHeight: 70)
                TextEditorWithPlaceholder(text: $mesExample, placeholder: "Example Messages")
                    .frame(minHeight: 70)
            }
            if let error = errorMessage {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section {
                Button(action: save) {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView() } else {
                            Text(existingCharacter == nil ? "Create" : "Save").bold()
                        }
                        Spacer()
                    }
                }
                .disabled(name.isEmpty || isSaving)
            }
        }
        .navigationTitle(existingCharacter == nil ? "New Character" : "Edit")
        .onAppear {
            if let char = existingCharacter {
                name = char.name
                description = char.description
                personality = char.personality
                scenario = char.scenario
                firstMessage = char.firstMes
                mesExample = char.mesExample
                creatorNotes = char.creatorNotes
                tags = char.tags.joined(separator: ", ")
                creator = char.creator
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let body: [String: String] = [
            "ch_name": name,
            "description": description,
            "personality": personality,
            "scenario": scenario,
            "first_mes": firstMessage,
            "mes_example": mesExample,
            "creator_comment": creatorNotes,
            "creator": creator,
            "tags": tags,
            "talkativeness": "0.5"
        ]
        Task {
            do {
                if let char = existingCharacter {
                    let editBody = body.merging(["avatar_url": char.avatar, "chat": "\(name) - 2024"]) { $1 }
                    let _: Data = try await client.postRaw("/api/characters/edit", body: editBody)
                } else {
                    let _: Data = try await client.uploadMultipart("/api/characters/create", body: body, fileData: nil)
                }
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

struct TextEditorWithPlaceholder: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
            }
            TextEditor(text: $text)
        }
    }
}
