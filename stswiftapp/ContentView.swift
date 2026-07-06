import SwiftUI
import Observation
import UniformTypeIdentifiers
import OSLog


struct ContentView: View {
    @Environment(STAppViewModel.self) private var appViewModel

    var body: some View {
        Group {
            if appViewModel.isConnected {
                MainTabView()
            } else {
                ServerSettingsView()
            }
        }
        .animation(.default, value: appViewModel.isConnected)
    }
}

struct MainTabView: View {
    @Environment(STAppViewModel.self) private var appViewModel
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
                .tag(0)

            GroupListView()
                .tabItem { Label("Groups", systemImage: "person.3") }
                .tag(1)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(2)
        }
    }
}

// MARK: - Home View (characters as chat list)

@Observable
final class HomeViewModel {
    var characters: [STCharacter] = []
    var chats: [STChat] = []
    var isLoading = false
    var isRefreshing = false
    var errorMessage: String?

    private let client = STAPIClient.shared
    func homeLog(_ msg: String) { Logger(subsystem: "com.stswiftapp", category: "Home").log("\(msg)") }

    func loadAll() async {
        isLoading = true
        errorMessage = nil

        // Load from cache first for instant display
        if let cached: [STCharacter] = STDataCache.read("characters", as: [STCharacter].self) {
            characters = cached
            homeLog("Loaded \(cached.count) characters from cache")
        }
        if let cached: [STChat] = STDataCache.read("chats", as: [STChat].self) {
            chats = cached
            homeLog("Loaded \(cached.count) chats from cache")
        }

        // Then refresh from server in background
        await refreshFromServer()
        isLoading = false
    }

    func refreshFromServer() async {
        isRefreshing = true
        do {
            async let chars: [STCharacter] = client.postArray("/api/characters/all", body: EmptyBody())
            let body: [String: String] = ["metadata": "true", "max": "100"]
            async let recentChats: [STChat] = client.postArray("/api/chats/recent", body: body)

            let (loadedChars, loadedChats) = try await (chars, recentChats)
            characters = loadedChars
            chats = loadedChats
            // Cache for next launch
            STDataCache.write("characters", value: loadedChars)
            STDataCache.write("chats", value: loadedChats)
            homeLog("Loaded \(loadedChars.count) characters, \(loadedChats.count) chats")
        } catch {
            errorMessage = characters.isEmpty ? error.localizedDescription : nil
            Logger(subsystem: "com.stswiftapp", category: "Home").error("refresh failed: \(error.localizedDescription)")
        }
        isRefreshing = false
    }

    /// Characters sorted by most recent chat activity
    var sortedCharacters: [STCharacter] {
        var charMap: [String: Double] = [:]
        for chat in chats {
            // Use characterName (which includes file_name fallback) for matching
            if let name = chat.characterName, let ts = chat.lastMes?.value {
                charMap[name] = max(charMap[name] ?? 0, ts)
            }
        }
        return characters.sorted { a, b in
            let aDate = charMap[a.name] ?? a.dateLastChat ?? 0
            let bDate = charMap[b.name] ?? b.dateLastChat ?? 0
            return aDate > bDate
        }
    }

    /// Most recent chat for a given character
    func recentChat(for character: STCharacter) -> STChat? {
        // Primary match: characterName from avatar or file_name parsing
        if let match = chats.first(where: { $0.characterName == character.name }) {
            return match
        }
        // Fallback: match by file_name containing the character name
        // Handles cases where chat file naming doesn't follow "Name - timestamp.jsonl"
        return chats.first { chat in
            let fn = chat.fileID ?? (chat.fileName as NSString).deletingPathExtension
            return fn.localizedCaseInsensitiveContains(character.name)
        }
    }

    func deleteCharacter(_ character: STCharacter) async {
        do {
            let body = STCharacterDeleteBody(avatar_url: character.avatar, delete_chats: true)
            let _: [String: String] = try await client.post("/api/characters/delete", body: body)
            await loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importCharacter(from url: URL) async {
        let ext = url.pathExtension.lowercased()
        guard ext == "png" || ext == "json" else {
            errorMessage = "Unsupported file type: .\(ext)"
            return
        }
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "Cannot access file"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let fileData = try? Data(contentsOf: url) else {
            errorMessage = "Could not read file"
            return
        }

        let mimeType = ext == "png" ? "image/png" : "application/json"
        let body = STCharacterImportBody(file_type: ext, user_name: "User")

        do {
            let _ = try await client.uploadMultipart(
                "/api/characters/import",
                body: body,
                fileData: fileData,
                fileName: url.lastPathComponent,
                mimeType: mimeType
            )
            await loadAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct STCharacterDeleteBody: Codable {
    let avatar_url: String
    let delete_chats: Bool
}

struct STCharacterImportBody: Encodable {
    let file_type: String
    let user_name: String
}

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var showFileImporter = false
    @State private var showCreateCharacter = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.characters.isEmpty {
                    ProgressView("Loading...")
                } else if viewModel.characters.isEmpty {
                    ContentUnavailableView(
                        "No Characters",
                        systemImage: "person.slash",
                        description: Text("Import characters from PNG or JSON files")
                    )
                } else {
                    List {
                        ForEach(viewModel.sortedCharacters) { character in
                            let chat = viewModel.recentChat(for: character)
                            NavigationLink {
                                ChatView(character: character, chat: chat)
                            } label: {
                                CharacterChatRow(character: character, chat: chat)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteCharacter(character) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await viewModel.refreshFromServer() }
                }
            }
            .navigationTitle("Chats")
            .task { await viewModel.loadAll() }
            .alert("Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("OK") {}
            } message: { Text(viewModel.errorMessage ?? "") }
            .navigationDestination(isPresented: $showCreateCharacter) {
                CharacterEditView()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Chats").font(.headline)
                        if viewModel.isRefreshing {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showCreateCharacter = true
                        } label: {
                            Label("Create Character", systemImage: "doc.badge.plus")
                        }
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Import from File", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.png, .json],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    for url in urls {
                        Task { await viewModel.importCharacter(from: url) }
                    }
                }
            }
        }
    }
}

struct CharacterChatRow: View {
    let character: STCharacter
    let chat: STChat?

    var body: some View {
        HStack(spacing: 16) {
            STAuthAsyncImage(
                avatar: character.avatar,
                name: character.name,
                cornerRadius: 24,
                size: 52
            )
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(character.name)
                    .font(.headline)
                    .lineLimit(1)
                if let msg = chat?.mes {
                    Text(msg)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if !character.creatorNotes.isEmpty {
                    Text(creatorNotesFirstLine)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let date = chat?.lastMessageDate {
                Text(date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let added = character.dateAdded {
                Text(Date(timeIntervalSince1970: added / 1000), style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var creatorNotesFirstLine: String {
        character.creatorNotes
            .components(separatedBy: "\n")
            .first?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}

#Preview {
    ContentView()
        .environment(STAppViewModel())
}