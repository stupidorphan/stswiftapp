import SwiftUI
import Observation

@Observable
final class WorldInfoViewModel {
    var files: [STWorldInfoFile] = []
    var currentFile: STWorldInfo?
    var currentFileName: String = ""
    var entries: [STWorldInfoEntry] = []
    var isLoading = false
    var isSaving = false
    var errorMessage: String?

    private let client = STAPIClient.shared

    func loadFiles() async {
        isLoading = true
        errorMessage = nil
        do {
            files = try await client.postArray("/api/worldinfo/list", body: EmptyBody())
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadFile(_ name: String) async {
        do {
            let body = ["name": name]
            let data = try await client.postRaw("/api/worldinfo/get", body: body)
            currentFile = try JSONDecoder().decode(STWorldInfo.self, from: data)
            currentFileName = name
            entries = Array((currentFile?.entries ?? [:]).values).sorted { $0.order < $1.order }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveFile() async {
        guard var file = currentFile else { return }
        isSaving = true
        var entriesDict: [String: STWorldInfoEntry] = [:]
        for entry in entries {
            entriesDict[String(entry.uid)] = entry
        }
        file.entries = entriesDict
        do {
            let body = WISaveBody(name: currentFileName, data: file)
            let _: [String: String] = try await client.post("/api/worldinfo/edit", body: body)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    func deleteFile(_ file: STWorldInfoFile) async {
        do {
            let body = ["name": file.fileID]
            let _: Data = try await client.postRaw("/api/worldinfo/delete", body: body)
            await loadFiles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addEntry() {
        let newEntry = STWorldInfoEntry(
            uid: Int(Date().timeIntervalSince1970),
            key: ["new trigger"],
            keysecondary: [],
            content: "",
            comment: "",
            constant: false,
            selective: false,
            order: entries.count * 100,
            position: 0,
            disable: false,
            excludeRecursion: false,
            preventRecursion: false,
            delayUntilRecursion: false,
            probability: 100,
            useProbability: false,
            depth: 4,
            group: "",
            groupOverride: false,
            groupWeight: 100,
            scanDepth: nil,
            caseSensitive: nil,
            matchWholeWords: nil,
            useGroupScoring: false,
            automationID: "",
            role: 0,
            sticky: 0,
            cooldown: 0,
            delay: 0
        )
        entries.append(newEntry)
    }

    func updateEntry(_ entry: STWorldInfoEntry) {
        if let idx = entries.firstIndex(where: { $0.uid == entry.uid }) {
            entries[idx] = entry
        }
    }
}

struct WISaveBody: Codable {
    let name: String
    let data: STWorldInfo
}

struct WorldInfoListView: View {
    @State private var viewModel = WorldInfoViewModel()
    @State private var showCreateSheet = false
    @State private var newFileName = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.files.isEmpty {
                    ProgressView("Loading lorebooks...")
                } else if viewModel.files.isEmpty {
                    ContentUnavailableView(
                        "No Lorebooks",
                        systemImage: "book",
                        description: Text("Create a lorebook to enhance your chats with world knowledge")
                    )
                } else {
                    List {
                        ForEach(viewModel.files) { file in
                            NavigationLink {
                                WorldInfoEntryListView(viewModel: viewModel, fileName: file.fileID)
                                    .task { await viewModel.loadFile(file.fileID) }
                            } label: {
                                Label(file.name, systemImage: "book.pages")
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteFile(file) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .refreshable { await viewModel.loadFiles() }
                }
            }
            .navigationTitle("World Info")
            .task { await viewModel.loadFiles() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreateSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("New Lorebook", isPresented: $showCreateSheet) {
                TextField("Name", text: $newFileName)
                Button("Create") {
                    let newWI = STWorldInfo(entries: [:])
                    let body = WISaveBody(name: newFileName, data: newWI)
                    Task {
                        do {
                            let _: [String: String] = try await STAPIClient.shared.post("/api/worldinfo/edit", body: body)
                            newFileName = ""
                            await viewModel.loadFiles()
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Cancel", role: .cancel) { newFileName = "" }
            } message: {
                Text("Enter a name for the new lorebook")
            }
        }
    }
}

struct WorldInfoEntryListView: View {
    @Bindable var viewModel: WorldInfoViewModel
    let fileName: String

    var body: some View {
        List {
            ForEach(Bindable(viewModel).entries.indices, id: \.self) { idx in
                NavigationLink {
                    WorldInfoEntryEditView(entry: viewModel.entries[idx]) { updatedEntry in
                        viewModel.updateEntry(updatedEntry)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.entries[idx].key.joined(separator: ", "))
                            .font(.headline)
                            .lineLimit(1)
                        Text(viewModel.entries[idx].content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .onDelete { indexSet in
                viewModel.entries.remove(atOffsets: indexSet)
            }
        }
        .navigationTitle(fileName)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { viewModel.addEntry() } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Save") {
                    Task { await viewModel.saveFile() }
                }
                .disabled(viewModel.isSaving)
            }
        }
    }
}

struct WorldInfoEntryEditView: View {
    let entry: STWorldInfoEntry
    var onSave: (STWorldInfoEntry) -> Void

    @State private var keys = ""
    @State private var content = ""
    @State private var comment = ""
    @State private var constant = false
    @State private var selective = false
    @State private var depth = 4
    @State private var probability = 100
    @State private var position = 0
    @State private var useProbability = false
    @State private var group = ""
    @State private var disableEntry = false

    @Environment(\.dismiss) private var dismiss

    init(entry: STWorldInfoEntry, onSave: @escaping (STWorldInfoEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _keys = State(initialValue: entry.key.joined(separator: ", "))
        _content = State(initialValue: entry.content)
        _comment = State(initialValue: entry.comment)
        _constant = State(initialValue: entry.constant)
        _selective = State(initialValue: entry.selective)
        _depth = State(initialValue: entry.depth)
        _probability = State(initialValue: entry.probability)
        _position = State(initialValue: entry.position)
        _useProbability = State(initialValue: entry.useProbability)
        _group = State(initialValue: entry.group)
        _disableEntry = State(initialValue: entry.disable)
    }

    var body: some View {
        Form {
            Section("Triggers") {
                TextField("Keywords (comma-separated)", text: $keys)
                TextEditorWithPlaceholder(text: $content, placeholder: "Entry content")
                    .frame(minHeight: 100)
                TextEditorWithPlaceholder(text: $comment, placeholder: "Comment (optional)")
                    .frame(minHeight: 60)
            }

            Section("Behavior") {
                Toggle("Constant", isOn: $constant)
                Toggle("Selective", isOn: $selective)
                Toggle("Use Probability", isOn: $useProbability)
                if useProbability {
                    Stepper("Probability: \(probability)%", value: $probability, in: 0...100, step: 5)
                }
                Stepper("Depth: \(depth)", value: $depth, in: 0...20)
                Picker("Position", selection: $position) {
                    Text("Before").tag(0)
                    Text("After").tag(1)
                    Text("Top").tag(2)
                    Text("Bottom").tag(3)
                }
                Toggle("Disabled", isOn: $disableEntry)
                TextField("Group", text: $group)
            }
        }
        .navigationTitle("Edit Entry")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var updated = entry
                    updated.key = keys.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    updated.content = content
                    updated.comment = comment
                    updated.constant = constant
                    updated.selective = selective
                    updated.depth = depth
                    updated.probability = probability
                    updated.position = position
                    updated.useProbability = useProbability
                    updated.group = group
                    updated.disable = disableEntry
                    onSave(updated)
                    dismiss()
                }
            }
        }
    }
}
