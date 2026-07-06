import Foundation

// MARK: - Polymorphic Date Decoder

/// Decodes a value that can be either a Double (epoch ms) or a String (ISO 8601 date).
/// Returns epoch milliseconds as Double, or nil if unreadable.
struct FlexibleTimestamp: Codable, Hashable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let num = try? container.decode(Double.self) {
            value = num
        } else if let str = try? container.decode(String.self) {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fmt.date(from: str) {
                value = date.timeIntervalSince1970 * 1000
            } else {
                let simple = ISO8601DateFormatter()
                // Parentheses fix: ?? binds tighter than *, so (val ?? 0) * 1000
                value = (simple.date(from: str)?.timeIntervalSince1970 ?? 0) * 1000
            }
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Character Model

struct STCharacter: Codable, Identifiable, Hashable {
    let name: String
    let description: String
    let personality: String
    let scenario: String
    let firstMes: String
    let mesExample: String
    let creatorNotes: String
    let systemPrompt: String
    let postHistoryInstructions: String
    let alternateGreetings: [String]
    let tags: [String]
    let creator: String
    let characterVersion: String
    let talkativeness: Double
    let fav: Bool
    let createDate: String?
    let avatar: String

    let dateAdded: Double?
    let dateLastChat: Double?
    let chatSize: Int?
    let dataSize: Int?

    let spec: String?
    let specVersion: String?

    var id: String { name }

    /// Placeholder for group chat contexts where no real character exists.
    static func groupPlaceholder(name: String, avatar: String) -> STCharacter {
        STCharacter(
            name: name, description: "", personality: "", scenario: "",
            firstMes: "", mesExample: "", creatorNotes: "", systemPrompt: "",
            postHistoryInstructions: "", alternateGreetings: [], tags: [],
            creator: "", characterVersion: "", talkativeness: 0.5, fav: false,
            createDate: nil, avatar: avatar,
            dateAdded: nil, dateLastChat: nil, chatSize: nil, dataSize: nil,
            spec: nil, specVersion: nil
        )
    }

    init(
        name: String, description: String, personality: String, scenario: String,
        firstMes: String, mesExample: String, creatorNotes: String, systemPrompt: String,
        postHistoryInstructions: String, alternateGreetings: [String], tags: [String],
        creator: String, characterVersion: String, talkativeness: Double, fav: Bool,
        createDate: String?, avatar: String,
        dateAdded: Double?, dateLastChat: Double?, chatSize: Int?, dataSize: Int?,
        spec: String?, specVersion: String?
    ) {
        self.name = name
        self.description = description
        self.personality = personality
        self.scenario = scenario
        self.firstMes = firstMes
        self.mesExample = mesExample
        self.creatorNotes = creatorNotes
        self.systemPrompt = systemPrompt
        self.postHistoryInstructions = postHistoryInstructions
        self.alternateGreetings = alternateGreetings
        self.tags = tags
        self.creator = creator
        self.characterVersion = characterVersion
        self.talkativeness = talkativeness
        self.fav = fav
        self.createDate = createDate
        self.avatar = avatar
        self.dateAdded = dateAdded
        self.dateLastChat = dateLastChat
        self.chatSize = chatSize
        self.dataSize = dataSize
        self.spec = spec
        self.specVersion = specVersion
    }

    enum CodingKeys: String, CodingKey {
        case name, description, personality, scenario
        case firstMes = "first_mes"
        case mesExample = "mes_example"
        case creatorNotes = "creator_comment"
        case systemPrompt = "system_prompt"
        case postHistoryInstructions = "post_history_instructions"
        case alternateGreetings = "alternate_greetings"
        case tags, creator
        case characterVersion = "character_version"
        case talkativeness, fav
        case createDate = "create_date"
        case avatar
        case dateAdded = "date_added"
        case dateLastChat = "date_last_chat"
        case chatSize = "chat_size"
        case dataSize = "data_size"
        case spec
        case specVersion = "spec_version"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func extract<T: Decodable>(_ key: CodingKeys) -> T? {
            try? container.decodeIfPresent(T.self, forKey: key)
        }

        name = extract(.name) ?? ""
        description = extract(.description) ?? ""
        personality = extract(.personality) ?? ""
        scenario = extract(.scenario) ?? ""
        firstMes = extract(.firstMes) ?? ""
        mesExample = extract(.mesExample) ?? ""
        creatorNotes = extract(.creatorNotes) ?? ""
        systemPrompt = extract(.systemPrompt) ?? ""
        postHistoryInstructions = extract(.postHistoryInstructions) ?? ""
        alternateGreetings = extract(.alternateGreetings) ?? []
        tags = extract(.tags) ?? []
        creator = extract(.creator) ?? ""
        characterVersion = extract(.characterVersion) ?? ""
        talkativeness = extract(.talkativeness) ?? 0.5
        fav = extract(.fav) ?? false
        createDate = extract(.createDate)
        avatar = extract(.avatar) ?? ""
        dateAdded = extract(.dateAdded)
        dateLastChat = extract(.dateLastChat)
        chatSize = extract(.chatSize)
        dataSize = extract(.dataSize)
        spec = extract(.spec)
        specVersion = extract(.specVersion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(personality, forKey: .personality)
        try container.encode(scenario, forKey: .scenario)
        try container.encode(firstMes, forKey: .firstMes)
        try container.encode(mesExample, forKey: .mesExample)
        try container.encode(creatorNotes, forKey: .creatorNotes)
        try container.encode(systemPrompt, forKey: .systemPrompt)
        try container.encode(postHistoryInstructions, forKey: .postHistoryInstructions)
        try container.encode(alternateGreetings, forKey: .alternateGreetings)
        try container.encode(tags, forKey: .tags)
        try container.encode(creator, forKey: .creator)
        try container.encode(characterVersion, forKey: .characterVersion)
        try container.encode(talkativeness, forKey: .talkativeness)
        try container.encode(fav, forKey: .fav)
        try container.encode(createDate, forKey: .createDate)
        try container.encode(avatar, forKey: .avatar)
        try container.encodeIfPresent(dateAdded, forKey: .dateAdded)
        try container.encodeIfPresent(dateLastChat, forKey: .dateLastChat)
        try container.encodeIfPresent(chatSize, forKey: .chatSize)
        try container.encodeIfPresent(dataSize, forKey: .dataSize)
        try container.encodeIfPresent(spec, forKey: .spec)
        try container.encodeIfPresent(specVersion, forKey: .specVersion)
    }
}

// MARK: - Chat Message Model

struct STChatMessage: Codable, Identifiable, Hashable {
    var id = UUID()
    let name: String
    let isUser: Bool
    let isSystem: Bool
    let sendDate: String
    var mes: String
    let extra: [String: String]
    var swipes: [String]?
    var swipeID: Int?

    enum CodingKeys: String, CodingKey {
        case name, mes, swipes
        case isUser = "is_user"
        case isSystem = "is_system"
        case sendDate = "send_date"
        case swipeID = "swipe_id"
        case extra
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        isUser = (try? container.decode(Bool.self, forKey: .isUser)) ?? false
        isSystem = (try? container.decode(Bool.self, forKey: .isSystem)) ?? false
        sendDate = (try? container.decode(String.self, forKey: .sendDate)) ?? ""
        mes = (try? container.decode(String.self, forKey: .mes)) ?? ""
        extra = (try? container.decode([String: String].self, forKey: .extra)) ?? [:]
        swipes = try? container.decodeIfPresent([String].self, forKey: .swipes)
        swipeID = try? container.decodeIfPresent(Int.self, forKey: .swipeID)
    }

    init(
        name: String,
        isUser: Bool,
        isSystem: Bool,
        sendDate: String,
        mes: String,
        extra: [String: String],
        swipes: [String]?,
        swipeID: Int?
    ) {
        self.name = name
        self.isUser = isUser
        self.isSystem = isSystem
        self.sendDate = sendDate
        self.mes = mes
        self.extra = extra
        self.swipes = swipes
        self.swipeID = swipeID
    }
}

// MARK: - Chat Model

/// Decoded from /api/chats/recent. Keys match the actual API response.
struct STChat: Codable, Identifiable, Hashable {
    let fileName: String
    let fileID: String?
    let fileSize: String?
    let avatar: String?
    let group: String?
    let mes: String?
    let lastMes: FlexibleTimestamp?
    let chatItems: Int?
    let chatMetadata: STChatMetadata?

    // Computed from avatar filename: "CharacterName.png" → "CharacterName"
    var characterName: String? {
        if let av = avatar {
            let base = (av as NSString).deletingPathExtension
            return base.isEmpty ? nil : base
        }
        // Fallback: extract from file_name "CharacterName - timestamp.jsonl"
        let fn = fileID ?? (fileName as NSString).deletingPathExtension
        // Chat files are named "CharacterName - timestamp" — take the part before " - "
        if let dashRange = fn.range(of: " - ") {
            let name = String(fn[..<dashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
        return nil
    }

    var id: String { group ?? avatar ?? fileID ?? fileName }

    var lastMessage: String? { mes }
    var messageCount: Int? { chatItems }

    var lastMessageDate: Date? {
        guard let ts = lastMes?.value else { return nil }
        return Date(timeIntervalSince1970: ts / 1000.0)
    }

    static func groupPlaceholder(id: String, name: String, avatar: String?) -> STChat {
        STChat(
            fileName: "\(id).jsonl", fileID: id, fileSize: nil,
            avatar: avatar, group: id, mes: nil, lastMes: nil,
            chatItems: nil, chatMetadata: nil
        )
    }

    init(
        fileName: String, fileID: String?, fileSize: String?, avatar: String?,
        group: String?, mes: String?, lastMes: FlexibleTimestamp?, chatItems: Int?,
        chatMetadata: STChatMetadata?
    ) {
        self.fileName = fileName
        self.fileID = fileID
        self.fileSize = fileSize
        self.avatar = avatar
        self.group = group
        self.mes = mes
        self.lastMes = lastMes
        self.chatItems = chatItems
        self.chatMetadata = chatMetadata
    }

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case fileID = "file_id"
        case fileSize = "file_size"
        case avatar, group, mes
        case lastMes = "last_mes"
        case chatItems = "chat_items"
        case chatMetadata = "chat_metadata"
    }
}

struct STChatMetadata: Codable, Hashable {}

// MARK: - Conversation Info (from /api/chats/search)

/// Decoded from /api/chats/search response — metadata for a single chat file.
struct STConversationInfo: Codable, Identifiable, Hashable {
    let fileName: String       // file_id e.g. "CharacterName - 2024-01-01"
    let fileSize: String        // human-readable e.g. "1.2 KB"
    let messageCount: Int       // number of messages in the chat
    let lastMes: FlexibleTimestamp? // last message timestamp
    let previewMessage: String?     // truncated last message text

    var id: String { fileName }

    var lastMessageDate: Date? {
        guard let ts = lastMes?.value else { return nil }
        return Date(timeIntervalSince1970: ts / 1000.0)
    }

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case fileSize = "file_size"
        case messageCount = "message_count"
        case lastMes = "last_mes"
        case previewMessage = "preview_message"
    }
}

// MARK: - Group Model

struct STGroup: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var members: [String]
    var avatarURL: String?
    var allowSelfResponses: Bool
    var activationStrategy: Int
    var generationMode: Int
    var disabledMembers: [String]
    var fav: Bool?
    var chatID: String?
    var chats: [String]
    var autoModeDelay: Int
    var generationModeJoinPrefix: String
    var generationModeJoinSuffix: String
    var dateAdded: Double?
    var dateLastChat: Double?
    var chatSize: Int?
    var createDate: String?

    enum CodingKeys: String, CodingKey {
        case id, name, members
        case avatarURL = "avatar_url"
        case allowSelfResponses = "allow_self_responses"
        case activationStrategy = "activation_strategy"
        case generationMode = "generation_mode"
        case disabledMembers = "disabled_members"
        case fav
        case chatID = "chat_id"
        case chats
        case autoModeDelay = "auto_mode_delay"
        case generationModeJoinPrefix = "generation_mode_join_prefix"
        case generationModeJoinSuffix = "generation_mode_join_suffix"
        case dateAdded = "date_added"
        case dateLastChat = "date_last_chat"
        case chatSize = "chat_size"
        case createDate = "create_date"
    }
}

// MARK: - Persona Model

struct STPersona: Codable, Identifiable, Hashable {
    var name: String
    var description: String
    var avatar: String?
    var id: String { name }
}

// MARK: - World Info / Lorebook Models

struct STWorldInfoFile: Codable, Identifiable, Hashable {
    let fileID: String
    let name: String
    let extensions: [String: String]?
    var id: String { fileID }
    enum CodingKeys: String, CodingKey {
        case fileID = "file_id"
        case name, extensions
    }
}

struct STWorldInfo: Codable {
    var entries: [String: STWorldInfoEntry]
}

struct STWorldInfoEntry: Codable, Identifiable, Hashable {
    let uid: Int
    var key: [String]
    var keysecondary: [String]
    var content: String
    var comment: String
    var constant: Bool
    var selective: Bool
    var order: Int
    var position: Int
    var disable: Bool
    var excludeRecursion: Bool
    var preventRecursion: Bool
    var delayUntilRecursion: Bool
    var probability: Int
    var useProbability: Bool
    var depth: Int
    var group: String
    var groupOverride: Bool
    var groupWeight: Int
    var scanDepth: Int?
    var caseSensitive: Bool?
    var matchWholeWords: Bool?
    var useGroupScoring: Bool
    var automationID: String
    var role: Int
    var sticky: Int
    var cooldown: Int
    var delay: Int
    var id: Int { uid }

    enum CodingKeys: String, CodingKey {
        case uid, key, keysecondary, content, comment, constant, selective
        case order, position, disable
        case excludeRecursion, preventRecursion, delayUntilRecursion
        case probability, useProbability, depth, group, groupOverride, groupWeight
        case scanDepth, caseSensitive, matchWholeWords, useGroupScoring
        case automationID = "automationId"
        case role, sticky, cooldown, delay
    }
}