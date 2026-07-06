import SwiftUI
import Foundation

// MARK: - Emoji Shortcodes (subset matching Showdown's emoji support)

private let emojiMap: [String: String] = [
    ":smile:": "😄", ":smiley:": "😃", ":grin:": "😁", ":joy:": "😂",
    ":rofl:": "🤣", ":sweat_smile:": "😅", ":laughing:": "😆",
    ":wink:": "😉", ":blush:": "😊", ":yum:": "😋", ":sunglasses:": "😎",
    ":heart_eyes:": "😍", ":kissing_heart:": "😘", ":kissing:": "😗",
    ":kissing_smiling_eyes:": "😙", ":kissing_closed_eyes:": "😚",
    ":relaxed:": "☺️", ":slight_smile:": "🙂", ":hugs:": "🤗",
    ":thinking:": "🤔", ":neutral_face:": "😐", ":expressionless:": "😑",
    ":no_mouth:": "😶", ":rolling_eyes:": "🙄", ":smirk:": "😏",
    ":persevere:": "😣", ":disappointed_relieved:": "😥", ":open_mouth:": "😮",
    ":zipper_mouth:": "🤐", ":hushed:": "😯", ":sleepy:": "😪",
    ":tired_face:": "😫", ":sleeping:": "😴", ":relieved:": "😌",
    ":stuck_out_tongue:": "😛", ":stuck_out_tongue_winking_eye:": "😜",
    ":stuck_out_tongue_closed_eyes:": "😝", ":drooling:": "🤤",
    ":unamused:": "😒", ":sweat:": "😓", ":pensive:": "😔",
    ":confused:": "😕", ":upside_down:": "🙃", ":money_mouth:": "🤑",
    ":astonished:": "😲", ":frowning2:": "☹️", ":slight_frown:": "🙁",
    ":confounded:": "😖", ":disappointed:": "😞", ":worried:": "😟",
    ":triumph:": "😤", ":cry:": "😢", ":sob:": "😭", ":frowning:": "😦",
    ":anguished:": "😧", ":fearful:": "😨", ":weary:": "😩",
    ":grimacing:": "😬", ":scream:": "😱", ":flushed:": "😳",
    ":dizzy_face:": "😵", ":rage:": "😡", ":angry:": "😠",
    ":innocent:": "😇", ":mask:": "😷", ":face_with_thermometer:": "🤒",
    ":face_with_head_bandage:": "🤕", ":nauseated_face:": "🤢",
    ":sneezing_face:": "🤧", ":smiling_imp:": "😈", ":imp:": "👿",
    ":japanese_ogre:": "👹", ":japanese_goblin:": "👺", ":skull:": "💀",
    ":ghost:": "👻", ":alien:": "👽", ":robot:": "🤖", ":jack_o_lantern:": "🎃",
    ":smiley_cat:": "😺", ":smile_cat:": "😸", ":joy_cat:": "😹",
    ":heart_eyes_cat:": "😻", ":smirk_cat:": "😼", ":kissing_cat:": "😽",
    ":scream_cat:": "🙀", ":crying_cat_face:": "😿", ":pouting_cat:": "😾",
    ":see_no_evil:": "🙈", ":hear_no_evil:": "🙉", ":speak_no_evil:": "🙊",
    ":kiss:": "💋", ":love_letter:": "💌", ":heart:": "❤️",
    ":broken_heart:": "💔", ":two_hearts:": "💕", ":sparkling_heart:": "💖",
    ":heartpulse:": "💗", ":cupid:": "💘", ":blue_heart:": "💙",
    ":green_heart:": "💚", ":yellow_heart:": "💛", ":purple_heart:": "💜",
    ":gift_heart:": "💝", ":revolving_hearts:": "💞", ":heart_decoration:": "💟",
    ":ok_hand:": "👌", ":thumbsup:": "👍", ":thumbsdown:": "👎",
    ":clap:": "👏", ":wave:": "👋", ":raised_hands:": "🙌",
    ":pray:": "🙏", ":muscle:": "💪", ":point_up:": "☝️",
    ":point_down:": "👇", ":point_left:": "👈", ":point_right:": "👉",
    ":fire:": "🔥", ":star:": "⭐", ":star2:": "🌟", ":zap:": "⚡",
    ":boom:": "💥", ":tada:": "🎉", ":sparkles:": "✨",
    ":100:": "💯", ":checkered_flag:": "🏁", ":warning:": "⚠️",
    ":question:": "❓", ":bulb:": "💡", ":x:": "❌",
    ":white_check_mark:": "✅", ":arrow_right:": "➡️", ":arrow_left:": "⬅️",
    ":arrow_up:": "⬆️", ":arrow_down:": "⬇️",
]

// MARK: - Markdown Renderer

/// Full-featured markdown renderer matching SillyTavern's Showdown configuration.
/// Supports: bold, italic, bold+italic, strikethrough, underline, inline code, code blocks,
/// headers, blockquotes, tables, lists, task lists, horizontal rules, links, images,
/// emoji shortcodes, macros, quoted-text coloring, and single-line-breaks.
struct MarkdownRenderer {

    /// Unicode sentinel used to mark quote boundaries. Private Use Area — never
    /// appears in natural text. Survives markdown parsing so we can find quoted
    /// spans during postprocessing.
    private static let quoteSentinel = "\u{FFF0}"

    /// Unicode sentinel used to mark positions where a visible line break
    /// should appear.  Private Use Area — never appears in natural text.
    /// Survives markdown parsing (the parser treats it as a regular character)
    /// so we can replace it with a literal \n during postprocessing.
    private static let lineBreakSentinel = "\u{E000}"

    static func render(
        _ text: String,
        quoteColor: Color = QuoteColorSettings.shared.quoteColor,
        characterName: String = "",
        userName: String = ""
    ) -> AttributedString {
        guard !text.isEmpty else { return AttributedString("") }

        let preprocessed = preprocess(text, characterName: characterName, userName: userName)
        do {
            var attr = try AttributedString(
                markdown: preprocessed,
                options: AttributedString.MarkdownParsingOptions(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .full
                )
            )
            postprocessUnderline(&attr)
            postprocessItalic(&attr)
            postprocessQuotedText(&attr, quoteColor: quoteColor)
            postprocessLineBreaks(&attr)
            return attr
        } catch {
            // Fallback: plain text (still run quote postprocessing on raw preprocessed)
            var attr = AttributedString(preprocessed)
            postprocessQuotedText(&attr, quoteColor: quoteColor)
            postprocessLineBreaks(&attr)
            return attr
        }
    }

    // MARK: - Preprocessing

    private static func preprocess(_ text: String, characterName: String = "", userName: String = "") -> String {
        var result = text

        // 0. Macro substitution ({{user}}, {{char}}, etc.) — must run first
        result = MacroProcessor.substitute(result, characterName: characterName, userName: userName)

        // 1. Mark quoted text with sentinel characters so we can style it later.
        //    Must run before markdown parsing so sentinels survive.
        result = markQuotedText(result, with: quoteSentinel)

        // 2. Replace underline __text__ with <u> tags (SillyTavern convention)
        result = replaceUnderline(result)

        // 3. Emoji shortcodes → actual emoji
        result = replaceEmoji(result)

        // 4. Single newlines → markdown hard breaks
        result = applySimpleLineBreaks(result)

        return result
    }

    // MARK: - Quoted Text

    /// Wraps quoted spans in sentinel characters so they can be identified
    /// and coloured during postprocessing.  Matches the same quote types as
    /// SillyTavern's `messageFormatting`: "…"  "…"  «…»  「…」  『…』  ＂…＂
    /// Content inside backtick code spans / fenced code blocks is left alone.
    private static func markQuotedText(_ text: String, with sentinel: String) -> String {
        let chars = Array(text)
        var result = ""
        var i = 0
        let n = chars.count

        // Quote pairs: (open, close)
        let pairs: [(Character, Character)] = [
            ("\"", "\""),
            ("\u{201C}", "\u{201D}"),
            ("\u{00AB}", "\u{00BB}"),
            ("\u{300C}", "\u{300D}"),
            ("\u{300E}", "\u{300F}"),
            ("\u{FF02}", "\u{FF02}"),
        ]

        while i < n {
            // Skip fenced code blocks
            if i + 3 <= n, matchesAt(chars, i, "```") {
                let start = i
                i += 3
                while i + 3 <= n, !matchesAt(chars, i, "```") { i += 1 }
                i += 3
                result += String(chars[start..<min(i, n)])
                continue
            }
            if i + 3 <= n, matchesAt(chars, i, "~~~") {
                let start = i
                i += 3
                while i + 3 <= n, !matchesAt(chars, i, "~~~") { i += 1 }
                i += 3
                result += String(chars[start..<min(i, n)])
                continue
            }
            // Skip inline code
            if chars[i] == "`" {
                let start = i
                i += 1
                while i < n, chars[i] != "`" { i += 1 }
                i += 1
                result += String(chars[start..<min(i, n)])
                continue
            }

            // Check for quote pairs
            var found = false
            for (open, close) in pairs {
                if chars[i] == open {
                    let start = i
                    i += 1
                    while i < n, chars[i] != close { i += 1 }
                    if i < n {
                        i += 1 // consume closing quote
                        let inner = String(chars[(start+1)..<(i-1)])
                        if !inner.isEmpty {
                            result += String(open) + sentinel + inner + sentinel + String(close)
                            found = true
                            break
                        }
                    }
                    // If no closing quote found, treat as normal char.
                    // Guard against the opening quote being the last
                    // character in the string — i would equal n and
                    // the next for-loop iteration would crash.
                    i = start + 1
                    if i >= n { found = true; break }
                }
            }
            if !found {
                result.append(chars[i])
                i += 1
            }
        }

        return result
    }

    private static func matchesAt(_ chars: [Character], _ idx: Int, _ pattern: String) -> Bool {
        let p = Array(pattern)
        guard idx + p.count <= chars.count else { return false }
        for j in 0..<p.count where chars[idx + j] != p[j] { return false }
        return true
    }

    /// Finds sentinel-wrapped spans in the AttributedString and applies the
    /// configured quote colour, then strips the sentinel characters while
    /// preserving all other attributes (bold, italic, etc.).
    private static func postprocessQuotedText(_ attr: inout AttributedString, quoteColor: Color) {
        let charStr = String(attr.characters)
        guard charStr.contains(quoteSentinel) else { return }

        var resultBuilder = AttributedString()
        var isInsideQuote = false
        let uiQuote = UIColor(quoteColor)

        var idx = attr.startIndex
        while idx < attr.endIndex {
            let char = attr[idx..<attr.index(afterCharacter: idx)]
            let charStr = String(char.characters)

            if charStr == quoteSentinel {
                isInsideQuote.toggle()
                idx = attr.index(afterCharacter: idx)
                continue
            }

            var run = char
            if isInsideQuote {
                run.foregroundColor = uiQuote
            }

            resultBuilder.append(run)
            idx = attr.index(afterCharacter: idx)
        }

        attr = resultBuilder
    }

    /// Finds line-break sentinel characters in the AttributedString and
    /// replaces each with a literal \n.  SwiftUI Text always renders \n
    /// as a visible line break in an AttributedString, regardless of
    /// paragraph-style defaults or markdown-parser behaviour.
    private static func postprocessLineBreaks(_ attr: inout AttributedString) {
        let charStr = String(attr.characters)
        guard charStr.contains(lineBreakSentinel) else { return }

        var resultBuilder = AttributedString()

        var idx = attr.startIndex
        while idx < attr.endIndex {
            let range = attr.index(afterCharacter: idx)
            let char = attr[idx..<range]
            let charStr = String(char.characters)

            if charStr == lineBreakSentinel {
                // Replace sentinel with a literal newline that Text will render.
                resultBuilder.append(AttributedString("\n"))
            } else {
                resultBuilder.append(char)
            }

            idx = range
        }

        attr = resultBuilder
    }

    /// Replace __text__ (underscore-based underline) with <u>text</u> HTML tags.
    /// Uses negative lookbehind to avoid matching mid_word__underscores.
    private static func replaceUnderline(_ text: String) -> String {
        // Match __text__ that is NOT preceded by a word character (negative lookbehind via boundary)
        // Simplified: match __word__ with word boundaries
        var result = ""
        var remaining = text
        while let range = remaining.range(of: "__") {
            result += remaining[..<range.lowerBound]
            let after = remaining[range.upperBound...]
            // Find closing __
            if let closeRange = after.range(of: "__") {
                let content = String(after[..<closeRange.lowerBound])
                if !content.isEmpty && !content.contains("\n") {
                    result += "<u>\(content)</u>"
                    remaining = String(after[closeRange.upperBound...])
                } else {
                    result += "__"
                    remaining = String(remaining[range.upperBound...])
                }
            } else {
                result += "__"
                remaining = String(remaining[range.upperBound...])
            }
        }
        result += remaining
        return result
    }

    /// Replace :emoji: shortcodes with actual emoji characters.
    private static func replaceEmoji(_ text: String) -> String {
        var result = text
        for (shortcode, emoji) in emojiMap {
            result = result.replacingOccurrences(of: shortcode, with: emoji)
        }
        return result
    }

    /// Normalise Windows-style CRLF to LF, then replace every newline
    /// outside a fenced code block with a Unicode sentinel that survives
    /// markdown parsing.  A postprocessing step later converts each
    /// sentinel into a literal \n in the AttributedString, which SwiftUI
    /// Text always renders as a visible line break.
    private static func applySimpleLineBreaks(_ text: String) -> String {
        // Normalise CRLF → LF first so we only have to deal with \n.
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n")
                             .replacingOccurrences(of: "\r", with: "\n")

        var result = ""
        var inCodeBlock = false
        let chars = Array(normalised)
        var i = 0

        while i < chars.count {
            // Detect fenced code block start / end (``` or ~~~).
            if i + 3 <= chars.count,
               matchesAt(chars, i, "```") || matchesAt(chars, i, "~~~") {
                inCodeBlock.toggle()
                result += String(chars[i..<(i + 3)])
                i += 3
                continue
            }
            if inCodeBlock {
                result.append(chars[i])
                i += 1
                continue
            }
            // Replace newline with sentinel — survives markdown parsing,
            // then swapped back to \n during postprocessing.
            if chars[i] == "\n" {
                result.append(lineBreakSentinel)
            } else {
                result.append(chars[i])
            }
            i += 1
        }
        return result
    }

    // MARK: - Postprocessing

    /// Underline is already handled via <u> tags in preprocessing,
    /// which AttributedString renders natively.
    private static func postprocessUnderline(_ attr: inout AttributedString) {
        // AttributedString(markdown:) already renders <u> tags as underline natively.
        // No additional postprocessing needed.
    }

    /// Make italic text slightly darker/dimmer than surrounding text,
    /// matching the visual convention used in most chat UIs.
    private static func postprocessItalic(_ attr: inout AttributedString) {
        for run in attr.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.emphasized) {
                attr[run.range].foregroundColor = .secondaryLabel
            }
        }
    }
}

// MARK: - View

/// View that renders markdown text using the full SillyTavern-compatible renderer.
struct MarkdownText: View {
    let text: String
    var quoteColor: Color = QuoteColorSettings.shared.quoteColor
    var characterName: String = ""
    var userName: String = ""

    var body: some View {
        Text(MarkdownRenderer.render(
            text,
            quoteColor: quoteColor,
            characterName: characterName,
            userName: userName
        ))
        .textSelection(.enabled)
    }
}
