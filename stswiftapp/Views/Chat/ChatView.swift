import SwiftUI
import Observation
import OSLog


func chatLog(_ msg: String) { Logger(subsystem: "com.stswiftapp", category: "Chat").log("\(msg)") }

struct DateHeaderView: View {
    let date: Date
    var body: some View {
        Text(formatDate(date)).font(.caption2).foregroundStyle(.secondary)
            .padding(.vertical, 8).frame(maxWidth: .infinity)
    }
    private func formatDate(_ d: Date) -> String {
        let cal = Calendar.current; let fmt = DateFormatter()
        if cal.isDateInToday(d) { return "Today" }
        else if cal.isDateInYesterday(d) { return "Yesterday" }
        fmt.dateFormat = "EEEE M/d 'at' h:mm a"; return fmt.string(from: d)
    }
}

struct MessageBubbleView: View {
    let message: STChatMessage; let isLastOutgoing: Bool
    var characterName: String = ""; var userName: String = ""
    var onCopy: (() -> Void)?; var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?; var onRegenerate: (() -> Void)?
    var isEditing: Bool = false
    var onSaveEdit: ((String) -> Void)?
    var onCancelEdit: (() -> Void)?
    var viewModel: ChatViewModel?

    @State private var editText: String = ""
    @State private var dragOffset: CGFloat = 0
    @State private var swipeAnimating = false

    var body: some View {
        HStack(alignment: .bottom) {
            if message.isUser { Spacer(minLength: 60) }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 0) {
                if isEditing {
                    VStack(spacing: 8) {
                        TextField("Edit message", text: $editText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .onAppear { editText = message.mes }
                        HStack(spacing: 12) {
                            Button("Cancel") { onCancelEdit?() }
                                .font(.caption)
                            Spacer()
                            Button("Save") { onSaveEdit?(editText) }
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.systemGray5)))
                } else {
                    MarkdownText(
                        text: message.mes,
                        characterName: characterName,
                        userName: userName
                    )
                    .font(.body)
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18).fill(message.isUser ? Color.blue : Color(.systemGray5)))
                }

                if isLastOutgoing { Text("Read").font(.caption2).foregroundStyle(.secondary).padding(.trailing, 8) }
            }
            .contextMenu {
                Button { onCopy?() } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                if message.isUser {
                    Button { onEdit?() } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
                if !message.isUser {
                    Button { onRegenerate?() } label: {
                        Label("Regenerate", systemImage: "arrow.counterclockwise")
                    }
                }
                Button(role: .destructive) { onDelete?() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            if !message.isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
        .offset(x: dragOffset)
        .opacity(swipeAnimating ? 0 : 1)
        .gesture(
            !message.isUser ? DragGesture(minimumDistance: 30)
                .onChanged { g in dragOffset = g.translation.width * 0.5 }
                .onEnded { g in
                    let endX = g.predictedEndTranslation.width
                    if endX < -80 {
                        swipeAnimating = true
                        withAnimation(.easeOut(duration: 0.25)) { dragOffset = -UIScreen.main.bounds.width }
                        Task {
                            await viewModel?.swipeRight()
                            withAnimation(.spring(response: 0.3)) { dragOffset = 0; swipeAnimating = false }
                        }
                    } else if endX > 80 {
                        swipeAnimating = true
                        withAnimation(.easeOut(duration: 0.25)) { dragOffset = UIScreen.main.bounds.width }
                        viewModel?.swipeLeft()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.spring(response: 0.3)) { dragOffset = 0; swipeAnimating = false }
                        }
                    } else {
                        withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                    }
                }
            : nil
        )
    }
}

// MARK: - Input Bar

struct InputBarView: View {
    @Binding var text: String
    let isStreaming: Bool; let onSend: () -> Void; let onCancel: () -> Void
    let onRegenerate: () -> Void; let onNewChat: () -> Void; let onImpersonate: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button(action: onRegenerate) {
                    Label("Regenerate", systemImage: "arrow.counterclockwise")
                }
                Button(action: onNewChat) {
                    Label("Start New Chat", systemImage: "text.bubble")
                }
                Button(action: onImpersonate) {
                    Label("Impersonate", systemImage: "person.fill.and.arrow.left.and.arrow.right")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                TextField("Message", text: $text, axis: .vertical)
                    .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 10)
                    .lineLimit(1...5)
                    .submitLabel(.return)

                Image(systemName: "waveform")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
            }
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 22))

            if isStreaming {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                }
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            text.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.secondary
                                : Color.blue
                        )
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// MARK: - Main Chat View

struct ChatView: View {
    let character: STCharacter; let chat: STChat?
    @State private var viewModel: ChatViewModel
    @State private var inputText = ""
    @Environment(STAppViewModel.self) private var appViewModel

    init(character: STCharacter, chat: STChat?) {
        self.character = character; self.chat = chat
        _viewModel = State(initialValue: ChatViewModel(character: character, chat: chat))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groupedMessages.indices, id: \.self) { groupIdx in
                        let group = groupedMessages[groupIdx]
                        if let date = group.date { DateHeaderView(date: date) }
                        ForEach(Array(group.messages.enumerated()), id: \.element.id) { msgIdx, message in
                            let prevMsg: STChatMessage? = msgIdx > 0 ? group.messages[msgIdx - 1] : (groupIdx > 0 ? groupedMessages[groupIdx - 1].messages.last : nil)
                            let sameSender = prevMsg?.isUser == message.isUser
                            let isLastOutgoing = groupIdx == groupedMessages.count - 1 && msgIdx == group.messages.count - 1 && message.isUser
                            let isLastAI = groupIdx == groupedMessages.count - 1 && msgIdx == group.messages.count - 1 && !message.isUser

                            messageRowView(
                                message: message,
                                isLastOutgoing: isLastOutgoing,
                                sameSender: sameSender,
                                isLastAI: isLastAI,
                                isFirst: msgIdx == 0
                            )
                        }
                    }
                    if viewModel.isStreaming && !viewModel.streamedText.isEmpty {
                        MessageBubbleView(
                            message: STChatMessage(name: character.name, isUser: false, isSystem: false, sendDate: "", mes: viewModel.streamedText, extra: [:], swipes: nil, swipeID: nil),
                            isLastOutgoing: false,
                            characterName: character.name,
                            userName: appViewModel.serverConfig.userHandle
                        ).id("streaming")
                    }
                }.padding(.top, 8)
            }
            .background(Color(.systemBackground))
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last?.id { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
            }
            .onChange(of: viewModel.streamedText) { _, _ in
                withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            InputBarView(
                text: $inputText,
                isStreaming: viewModel.isStreaming,
                onSend: sendMessage,
                onCancel: { viewModel.cancelStreaming() },
                onRegenerate: { Task { await viewModel.regenerate() } },
                onNewChat: { viewModel.startNewChat() },
                onImpersonate: { Task { await viewModel.impersonate(into: $inputText) } }
            )
        }
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavigationLink { CharacterDetailView(character: character) } label: {
                    HStack(spacing: 8) {
                        STAuthCircularImage(avatar: character.avatar, name: character.name, size: 28)
                        Text(character.name).font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Task { await viewModel.fetchConversations(); viewModel.showConversationPicker = true }
                }) {
                    Image(systemName: "list.bullet.rectangle").font(.subheadline)
                }
            }
        }
        .task { await viewModel.loadMessages() }
        .sheet(isPresented: $viewModel.showConversationPicker) {
            ConversationPickerSheet(viewModel: viewModel)
        }
        .alert("Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(viewModel.errorMessage ?? "") }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""; Task { await viewModel.sendMessage(text, characterName: character.name) }
    }

    @ViewBuilder
    private func messageRowView(message: STChatMessage, isLastOutgoing: Bool, sameSender: Bool, isLastAI: Bool, isFirst: Bool) -> some View {
        MessageBubbleView(
            message: message, isLastOutgoing: isLastOutgoing,
            characterName: character.name,
            userName: appViewModel.serverConfig.userHandle,
            onCopy: { viewModel.copyMessage(message) },
            onEdit: { viewModel.beginEditing(message) },
            onDelete: { viewModel.deleteMessage(message) },
            onRegenerate: { Task { await viewModel.regenerate() } },
            isEditing: viewModel.editingMessageID == message.id,
            onSaveEdit: { viewModel.saveEdit(message, newText: $0) },
            onCancelEdit: { viewModel.cancelEdit() },
            viewModel: viewModel
        )
        .id(message.id)
        .padding(.top, isFirst ? 12 : (sameSender ? 4 : 16))
    }

    private struct MessageGroup { let date: Date?; let messages: [STChatMessage] }
    private var groupedMessages: [MessageGroup] {
        var groups: [MessageGroup] = []; var current: [STChatMessage] = []; var lastDate: Date? = nil
        for msg in viewModel.messages {
            let msgDate = parseDate(msg.sendDate)
            if let ld = lastDate, let md = msgDate, !Calendar.current.isDate(md, inSameDayAs: ld) {
                groups.append(MessageGroup(date: lastDate, messages: current)); current = [msg]
            } else { current.append(msg) }
            if msgDate != nil { lastDate = msgDate }
        }
        if !current.isEmpty { groups.append(MessageGroup(date: lastDate, messages: current)) }
        return groups
    }
    private func parseDate(_ str: String) -> Date? {
        let fmt = ISO8601DateFormatter(); fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: str) ?? ISO8601DateFormatter().date(from: str)
    }
}

// MARK: - ViewModel

@Observable
final class ChatViewModel {
    var messages: [STChatMessage] = []; var isLoading = false; var isStreaming = false
    var streamedText = ""; var errorMessage: String?
    var character: STCharacter; var chat: STChat?
    var conversations: [STConversationInfo] = []
    var showConversationPicker = false
    private let client = STAPIClient.shared; private var streamingTask: Task<Void, Never>?

    init(character: STCharacter, chat: STChat?) { self.character = character; self.chat = chat }

    // MARK: - Conversations

    /// Fetch all conversations for this character from /api/chats/search.
    func fetchConversations() async {
        do {
            let body: [String: String] = ["avatar_url": character.avatar]
            let results: [STConversationInfo] = try await client.postArray("/api/chats/search", body: body)
            conversations = results.sorted { ($0.lastMes?.value ?? 0) > ($1.lastMes?.value ?? 0) }
            chatLog("Fetched \(conversations.count) conversations for \(character.name)")
        } catch {
            chatLog("Failed to fetch conversations: \(error.localizedDescription)")
        }
    }

    /// Select a conversation by file name, set it as the current chat, and load messages.
    func selectConversation(_ info: STConversationInfo) {
        chat = STChat(
            fileName: info.fileName + ".jsonl",
            fileID: info.fileName,
            fileSize: info.fileSize,
            avatar: character.avatar,
            group: nil,
            mes: info.previewMessage,
            lastMes: info.lastMes,
            chatItems: info.messageCount,
            chatMetadata: nil
        )
        messages = []
        showConversationPicker = false
        Task { await loadMessages() }
    }

    /// Rename a conversation file on the server.
    func renameConversation(_ info: STConversationInfo, to newBaseName: String) async {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { errorMessage = "Name cannot be empty"; return }
        do {
            let body: [String: String] = [
                "avatar_url": character.avatar,
                "original_file": info.fileName + ".jsonl",
                "renamed_file": trimmed + ".jsonl",
            ]
            let _: [String: String] = try await client.post("/api/chats/rename", body: body)
            chatLog("Renamed '\(info.fileName)' → '\(trimmed)'")
            await fetchConversations()
        } catch {
            errorMessage = "Rename failed: \(error.localizedDescription)"
        }
    }

    /// Delete a conversation file on the server.
    func deleteConversation(_ info: STConversationInfo) async {
        do {
            let body: [String: String] = [
                "avatar_url": character.avatar,
                "chatfile": info.fileName + ".jsonl",
            ]
            let _: [String: String] = try await client.post("/api/chats/delete", body: body)
            chatLog("Deleted conversation '\(info.fileName)'")
            await fetchConversations()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Messages

    func loadMessages() async {
        // Auto-load the latest conversation if none is preselected
        if chat == nil {
            await fetchConversations()
            if let latest = conversations.first {
                selectConversation(latest)
                return
            }
            // No existing conversations — show the character's first message
            if !character.firstMes.isEmpty {
                messages = [STChatMessage(
                    name: character.name, isUser: false, isSystem: false,
                    sendDate: character.createDate ?? ISO8601DateFormatter().string(from: Date()),
                    mes: character.firstMes, extra: [:], swipes: nil, swipeID: nil
                )]
            }
            isLoading = false
            return
        }
        isLoading = true; errorMessage = nil
        // Use chat.avatar, falling back to character.avatar so the server finds
        // the correct chats/<CharacterName>/ directory even when the chat record
        // has no avatar (root-level or legacy chats).
        let avatarURL = chat?.avatar ?? character.avatar
        chatLog("Loading messages for \(self.character.name) — chat: \(chat?.fileName ?? "nil") avatar: \(avatarURL)")
        do {
            if let group = chat?.group {
                let msg: [STChatMessage] = try await client.postArray("/api/chats/group/get", body: ["id": group]); messages = Array(msg.dropFirst())
            } else if let c = chat {
                let clean = c.fileName.replacingOccurrences(of: ".jsonl", with: "")
                let msg: [STChatMessage] = try await client.postArray("/api/chats/get", body: ["avatar_url": avatarURL, "file_name": clean]); messages = Array(msg.dropFirst())
            }
            // If chat is empty (new chat), show first message
            if messages.isEmpty && !character.firstMes.isEmpty {
                messages = [STChatMessage(
                    name: character.name, isUser: false, isSystem: false,
                    sendDate: character.createDate ?? ISO8601DateFormatter().string(from: Date()),
                    mes: character.firstMes, extra: [:], swipes: nil, swipeID: nil
                )]
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func sendMessage(_ text: String, characterName: String, userName: String = "User") async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        messages.append(STChatMessage(name: userName, isUser: true, isSystem: false, sendDate: ISO8601DateFormatter().string(from: Date()), mes: text, extra: [:], swipes: nil, swipeID: nil))
        await generateResponse(characterName: characterName, userName: userName)
    }

    enum GenerateMode { case normal, swipe, impersonate }

    private func generateResponse(characterName: String, userName: String, mode: GenerateMode = .normal) async {
        isStreaming = true; streamedText = ""
        let config = loadAPIConfig()
        guard let config = config else { errorMessage = "No API config. Go to Settings → API."; isStreaming = false; return }

        // Create a new chat if none exists
        if chat == nil {
            let fname = "\(characterName) - \(ISO8601DateFormatter().string(from: Date()))"
            let clean = fname.replacingOccurrences(of: ".jsonl", with: "")
            chat = STChat(fileName: fname, fileID: clean, fileSize: nil, avatar: character.avatar, group: nil, mes: nil, lastMes: nil, chatItems: nil, chatMetadata: nil)
        }

        let typeStr = mode == .swipe ? "swipe" : mode == .impersonate ? "impersonate" : "normal"
        let body = STGenerateRequest(type: typeStr,
            messages: buildPrompt(for: characterName, user: userName, skipLastAssistant: mode == .swipe),
            model: config.model, temperature: config.temperature,
            maxTokens: config.maxTokens, maxCompletionTokens: config.maxCompletionTokens,
            stream: true, topP: config.topP, topK: config.topK,
            frequencyPenalty: config.frequencyPenalty, presencePenalty: config.presencePenalty,
            stop: config.stop, seed: config.seed,
            reverseProxy: config.reverseProxy, customURL: config.customURL,
            proxyPassword: config.proxyPassword,
            customIncludeBody: config.customIncludeBody, customIncludeHeaders: config.customIncludeHeaders,
            customExcludeBody: config.customExcludeBody,
            chatCompletionSource: config.chatCompletionSource,
            userName: userName, charName: characterName)
        let stream = client.streamSSE("/api/backends/chat-completions/generate", body: body)
        streamingTask = Task {
            var full = ""
            do { for try await e in stream { full += parseChunk(e.data); await MainActor.run { streamedText = full } } }
            catch { if !Task.isCancelled { await MainActor.run { let msg = error.localizedDescription; errorMessage = msg; chatLog("STREAM ERROR: \(msg)") } } }
            await MainActor.run {
                isStreaming = false
                if !full.isEmpty {
                    let now = ISO8601DateFormatter().string(from: Date())
                    switch mode {
                    case .normal:
                        messages.append(STChatMessage(name: characterName, isUser: false, isSystem: false, sendDate: now, mes: full, extra: [:], swipes: [full], swipeID: 0))
                    case .swipe:
                        // Append to swipes array on the last message (replace element for @Observable)
                        if let lastIdx = messages.indices.last {
                            var last = messages[lastIdx]
                            var swipes = last.swipes ?? [last.mes]
                            swipes.append(full)
                            last.mes = full
                            last.swipes = swipes
                            last.swipeID = swipes.count - 1
                            // Replace in array to trigger @Observable update
                            messages[lastIdx] = STChatMessage(
                                name: last.name, isUser: last.isUser, isSystem: last.isSystem,
                                sendDate: last.sendDate, mes: full,
                                extra: last.extra, swipes: swipes, swipeID: swipes.count - 1
                            )
                        }
                    case .impersonate:
                        break // handled separately via impersonateText callback
                    }
                    streamedText = ""
                    chatLog("Message received: \(full.prefix(50))...")
                    Task { await save() }
                }
            }
        }
    }

    func cancelStreaming() { streamingTask?.cancel(); isStreaming = false }

    /// Called by + menu or swipe-right to regenerate an alternate response
    func regenerate() async {
        guard let lastUserMsg = messages.last(where: { $0.isUser }) else { return }
        // Remove the last AI message
        if messages.last(where: { !$0.isUser }) != nil { messages.removeLast() }
        await generateResponse(characterName: lastUserMsg.name, userName: lastUserMsg.name == character.name ? "User" : lastUserMsg.name)
    }

    // MARK: - Swipe

    /// Swipe left (previous alternate) on the last AI message
    func swipeLeft() {
        guard let idx = messages.indices.last, !messages[idx].isUser else { return }
        let msg = messages[idx]
        let swipes = msg.swipes ?? [msg.mes]
        let currentID = msg.swipeID ?? 0
        guard currentID > 0, currentID - 1 < swipes.count else { return }
        let newID = currentID - 1
        // Replace in array to trigger @Observable update
        messages[idx] = rebuild(msg, mes: swipes[newID], swipes: swipes, swipeID: newID)
    }

    /// Swipe right (next alternate or generate new) on the last AI message
    func swipeRight() async {
        guard let idx = messages.indices.last, !messages[idx].isUser else { return }
        let msg = messages[idx]
        let swipes = msg.swipes ?? [msg.mes]
        let currentID = msg.swipeID ?? 0
        chatLog("swipeRight: idx=\(idx) currentID=\(currentID) swipes.count=\(swipes.count)")
        if currentID + 1 < swipes.count {
            let newID = currentID + 1
            messages[idx] = rebuild(msg, mes: swipes[newID], swipes: swipes, swipeID: newID)
            chatLog("swipeRight: showing alternate \(newID)")
        } else if currentID + 1 >= swipes.count {
            chatLog("swipeRight: generating new swipe")
            guard let lastUserMsg = messages.last(where: { $0.isUser }) else { return }
            await generateResponse(characterName: msg.name, userName: lastUserMsg.name, mode: .swipe)
        }
    }

    /// Return a fresh STChatMessage copy — needed so @Observable picks up the mutation.
    private func rebuild(_ m: STChatMessage, mes: String, swipes: [String], swipeID: Int) -> STChatMessage {
        STChatMessage(name: m.name, isUser: m.isUser, isSystem: m.isSystem,
                      sendDate: m.sendDate, mes: mes, extra: m.extra,
                      swipes: swipes, swipeID: swipeID)
    }

    // MARK: - New Chat

    func startNewChat() {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd@HH'h'mm'm'ss's'SSS'ms'"
        let newName = "\(character.name) - \(df.string(from: Date()))"
        let clean = newName.replacingOccurrences(of: ".jsonl", with: "")

        messages = []
        chat = STChat(fileName: newName, fileID: clean, fileSize: nil, avatar: character.avatar, group: nil, mes: nil, lastMes: nil, chatItems: nil, chatMetadata: nil)
        streamedText = ""
        isStreaming = false
        streamingTask?.cancel()

        Task {
            // Initialize new chat on server
            let _ = try? await client.postRaw("/api/chats/get", body: ["ch_name": character.name, "file_name": clean, "avatar_url": character.avatar])
            // Update character's active chat to new file
            let _ = try? await client.postRaw("/api/characters/edit", body: ["avatar_url": character.avatar, "chat": clean])
            await loadMessages()
        }
    }

    // MARK: - Impersonate

    /// Generates a message as the user and puts the result into the input field.
    func impersonate(into inputBinding: Binding<String>) async {
        guard let lastMsg = messages.last else { return }
        isStreaming = true; streamedText = ""
        guard let config = loadAPIConfig() else { errorMessage = "No API config."; isStreaming = false; return }

        let userName = lastMsg.isUser ? lastMsg.name : "User"
        var prompt = buildPrompt(for: character.name, user: userName)
        // Append impersonation instruction (matching frontend format)
        prompt.append(STPromptMessage(role: "system", content: "[Write your next reply from the point of view of \(userName), using the chat history so far as a guideline for the writing style of \(userName). Don't write as \(character.name) or system. Don't describe actions of \(character.name).]"))

        let body = STGenerateRequest(
            type: "impersonate",
            messages: prompt, model: config.model, temperature: config.temperature,
            maxTokens: config.maxTokens, maxCompletionTokens: config.maxCompletionTokens,
            stream: false, topP: config.topP, topK: config.topK,
            frequencyPenalty: config.frequencyPenalty, presencePenalty: config.presencePenalty,
            stop: config.stop, seed: config.seed,
            reverseProxy: config.reverseProxy, customURL: config.customURL,
            proxyPassword: config.proxyPassword,
            customIncludeBody: config.customIncludeBody, customIncludeHeaders: config.customIncludeHeaders,
            customExcludeBody: config.customExcludeBody,
            chatCompletionSource: config.chatCompletionSource,
            userName: userName, charName: character.name
        )
        do {
            let data = try await client.postRaw("/api/backends/chat-completions/generate", body: body)
            // Parse non-streaming response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                inputBinding.wrappedValue = content
                chatLog("Impersonate ready: \(content.prefix(50))...")
            }
        } catch {
            let msg = error.localizedDescription; errorMessage = msg; chatLog("IMPERSONATE ERROR: \(msg)")
        }
        isStreaming = false
    }

    // MARK: - Message Actions

    var editingMessageID: UUID?

    func copyMessage(_ message: STChatMessage) {
        UIPasteboard.general.string = message.mes
    }

    func deleteMessage(_ message: STChatMessage) {
        messages.removeAll { $0.id == message.id }
        if editingMessageID == message.id { editingMessageID = nil }
    }

    func beginEditing(_ message: STChatMessage) {
        editingMessageID = message.id
    }

    func saveEdit(_ message: STChatMessage, newText: String) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index] = STChatMessage(
            name: message.name, isUser: message.isUser, isSystem: message.isSystem,
            sendDate: message.sendDate, mes: newText,
            extra: message.extra, swipes: message.swipes, swipeID: message.swipeID
        )
        editingMessageID = nil
        Task { await save() }
    }

    func cancelEdit() {
        editingMessageID = nil
    }

    private func parseChunk(_ d: String) -> String {
        struct C: Codable { let delta: D }; struct D: Codable { let content: String? }; struct R: Codable { let choices: [C] }
        guard let j = d.data(using: .utf8), let r = try? JSONDecoder().decode(R.self, from: j), let c = r.choices.first?.delta.content else { return "" }; return c
    }
    private func save() async {
        guard !messages.isEmpty, let c = chat else { return }
        chatLog("Saving \(self.messages.count) messages to chat \(c.fileName)")
        let h = STChatMessage(name: "h", isUser: false, isSystem: true, sendDate: "", mes: "", extra: [:], swipes: nil, swipeID: nil)
        let av = c.avatar ?? character.avatar
        do {
            if let g = c.group {
                let _ = try await client.postRaw("/api/chats/group/save", body: STSaveGroupChatBody(id: g, chat: [h] + messages))
            } else {
                let clean = c.fileName.replacingOccurrences(of: ".jsonl", with: "")
                let _ = try await client.postRaw("/api/chats/save", body: STSaveChatBody(avatar_url: av, file_name: clean, chat: [h] + messages))
            }
        } catch { errorMessage = "Save failed: \(error.localizedDescription)" }
    }
    private func loadAPIConfig() -> STAPIConfig? {
        let store = SettingsStore.shared
        return STAPIConfig(
            chatCompletionSource: store.chatCompletionSource,
            model: store.model,
            temperature: store.temperature,
            maxTokens: store.maxTokens,
            maxCompletionTokens: store.maxCompletionTokens > 0 ? store.maxCompletionTokens : nil,
            topP: store.topP,
            topK: store.topK > 0 ? store.topK : nil,
            frequencyPenalty: store.frequencyPenalty,
            presencePenalty: store.presencePenalty,
            stop: store.stopSequences.isEmpty ? nil : store.stopSequences.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            seed: store.seed > 0 ? store.seed : nil,
            reverseProxy: store.reverseProxy.isEmpty ? nil : store.reverseProxy,
            customURL: store.customURL.isEmpty ? nil : store.customURL,
            proxyPassword: store.proxyPassword.isEmpty ? nil : store.proxyPassword,
            customIncludeBody: store.customIncludeBody.isEmpty ? nil : store.customIncludeBody,
            customIncludeHeaders: store.customIncludeHeaders.isEmpty ? nil : store.customIncludeHeaders,
            customExcludeBody: store.customExcludeBody.isEmpty ? nil : store.customExcludeBody
        )
    }
    private func buildPrompt(for name: String, user: String, skipLastAssistant: Bool = false) -> [STPromptMessage] {
        var m: [STPromptMessage] = []
        let sp = systemPrompt()
        m.append(STPromptMessage(role: "system", content: sp.isEmpty ? "You are \(name)." : sp))
        var msgs = Array(messages.suffix(20))
        if skipLastAssistant, let last = msgs.last, !last.isUser {
            msgs.removeLast()
        }
        for msg in msgs {
            m.append(STPromptMessage(role: msg.isUser ? "user" : "assistant", content: msg.mes))
        }
        return m
    }
    private func systemPrompt() -> String {
        var p: [String] = []
        if !character.description.isEmpty { p.append(character.description) }
        if !character.personality.isEmpty { p.append("Personality: \(character.personality)") }
        if !character.scenario.isEmpty { p.append("Scenario: \(character.scenario)") }
        if !character.systemPrompt.isEmpty { p.append(character.systemPrompt) }
        if !character.postHistoryInstructions.isEmpty { p.append(character.postHistoryInstructions) }
        return p.joined(separator: "\n")
    }
}

// MARK: - Conversation Picker Sheet

struct ConversationPickerSheet: View {
    let viewModel: ChatViewModel
    @State private var renameTarget: STConversationInfo?
    @State private var renameText = ""
    @State private var deleteTarget: STConversationInfo?
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.conversations.isEmpty {
                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a conversation in the chat to see it here.")
                    )
                }
                ForEach(viewModel.conversations) { info in
                    Button {
                        viewModel.selectConversation(info)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(info.fileName)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                Spacer()
                                if let date = info.lastMessageDate {
                                    Text(date, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let preview = info.previewMessage, !preview.isEmpty {
                                Text(preview)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            HStack(spacing: 8) {
                                Label("\(info.messageCount) msgs", systemImage: "text.bubble")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Label(info.fileSize, systemImage: "doc")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteTarget = info
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            renameTarget = info
                            renameText = info.fileName
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await viewModel.fetchConversations() }
        }
        .alert("Rename Conversation", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("New name", text: $renameText)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                guard let target = renameTarget else { return }
                Task { await viewModel.renameConversation(target, to: renameText) }
                renameTarget = nil
            }
        } message: {
            Text("Enter a new name for \"\(renameTarget?.fileName ?? "")\"")
        }
        .alert("Delete Conversation?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                guard let target = deleteTarget else { return }
                Task { await viewModel.deleteConversation(target) }
                deleteTarget = nil
            }
        } message: {
            Text("This will permanently delete \"\(deleteTarget?.fileName ?? "")\" and all its messages.")
        }
    }
}

// MARK: - Config & Request types

struct STAPIConfig {
    let chatCompletionSource: String; let model: String; let temperature: Double; let maxTokens: Int
    let maxCompletionTokens: Int?; let topP: Double?; let topK: Int?
    let frequencyPenalty: Double?; let presencePenalty: Double?; let stop: [String]?; let seed: Int?
    let reverseProxy: String?; let customURL: String?; let proxyPassword: String?
    let customIncludeBody: String?; let customIncludeHeaders: String?; let customExcludeBody: String?
}
struct STGenerateRequest: Codable {
    let type: String; let messages: [STPromptMessage]; let model: String
    let temperature: Double; let maxTokens: Int; let maxCompletionTokens: Int?; let stream: Bool
    let topP: Double?; let topK: Int?; let frequencyPenalty: Double?; let presencePenalty: Double?
    let stop: [String]?; let seed: Int?; let reverseProxy: String?; let customURL: String?
    let proxyPassword: String?; let customIncludeBody: String?; let customIncludeHeaders: String?; let customExcludeBody: String?
    let chatCompletionSource: String; let userName: String; let charName: String
    enum CodingKeys: String, CodingKey {
        case type, messages, model, temperature, stream, stop, seed
        case chatCompletionSource = "chat_completion_source"; case maxTokens = "max_tokens"; case maxCompletionTokens = "max_completion_tokens"
        case topP = "top_p"; case topK = "top_k"; case frequencyPenalty = "frequency_penalty"; case presencePenalty = "presence_penalty"
        case reverseProxy = "reverse_proxy"; case customURL = "custom_url"; case proxyPassword = "proxy_password"
        case customIncludeBody = "custom_include_body"; case customIncludeHeaders = "custom_include_headers"; case customExcludeBody = "custom_exclude_body"
        case userName = "user_name"; case charName = "char_name"
    }
}
struct STPromptMessage: Codable { let role: String; let content: String }
struct STSaveChatBody: Codable { let avatar_url: String; let file_name: String; let chat: [STChatMessage] }
struct STSaveGroupChatBody: Codable { let id: String; let chat: [STChatMessage] }
struct EmptyBody: Codable {}
