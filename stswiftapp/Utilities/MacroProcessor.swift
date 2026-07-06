import Foundation

/// Substitutes {{macros}} in text matching SillyTavern's substituteParams behavior.
struct MacroProcessor {
    /// Replace known macros in the given text with their resolved values.
    /// - Parameters:
    ///   - text: The raw input string that may contain `{{macro}}` placeholders.
    ///   - characterName: The current character's display name (replaces `{{char}}`).
    ///   - userName: The current user's display name (replaces `{{user}}`).
    /// - Returns: The substituted string.
    static func substitute(_ text: String, characterName: String, userName: String) -> String {
        var result = text
        let now = Date()
        let df = DateFormatter()

        // {{time}} → current local time (HH:MM)
        df.dateFormat = "HH:mm"
        result = result.replacingOccurrences(of: "{{time}}", with: df.string(from: now))

        // {{date}} → current local date (YYYY-MM-DD, matching SillyTavern style)
        df.dateFormat = "yyyy-MM-dd"
        result = result.replacingOccurrences(of: "{{date}}", with: df.string(from: now))

        // {{weekday}} → current weekday name
        df.dateFormat = "EEEE"
        result = result.replacingOccurrences(of: "{{weekday}}", with: df.string(from: now))

        // {{char}} → character name
        result = result.replacingOccurrences(of: "{{char}}", with: characterName)

        // {{user}} → user handle (fallback to "User")
        let resolvedUser = userName.isEmpty ? "User" : userName
        result = result.replacingOccurrences(of: "{{user}}", with: resolvedUser)

        // {{original}} → empty (placeholder for original text in SillyTavern's swipe system)
        result = result.replacingOccurrences(of: "{{original}}", with: "")

        // {{group}} → empty (no group context in single-character chat)
        result = result.replacingOccurrences(of: "{{group}}", with: "")

        return result
    }
}
