import Foundation

/// Turns Slack's message markup ("mrkdwn") into plain text for the Panel (ITM-2).
public enum SlackText {
    /// How much of a message the Panel shows.
    public static let excerptLength = 100

    /// Plain text with user, channel and link markup resolved, formatting removed and
    /// whitespace collapsed.
    public static func plain(_ text: String, userNames: [String: String] = [:]) -> String {
        var result = replaceAngleTokens(in: text, userNames: userNames)
        result = stripFormatting(result)
        result = result
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The first ~100 characters of `text`, cut at a word where possible, with "…" if shortened.
    public static func excerpt(_ text: String, length: Int = excerptLength) -> String {
        guard text.count > length else { return text }
        var cut = String(text.prefix(length))
        if let space = cut.lastIndex(of: " "), cut.distance(from: space, to: cut.endIndex) < 20 {
            cut = String(cut[..<space])
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// User IDs mentioned in `text` as `<@U123>`.
    public static func mentionedUserIDs(in text: String) -> [String] {
        tokens(in: text).compactMap { token in
            guard token.hasPrefix("@") else { return nil }
            return String(token.dropFirst().split(separator: "|").first ?? "")
        }
    }

    // MARK: - Private

    private static func tokens(in text: String) -> [String] {
        var tokens: [String] = []
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            tokens.append(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return tokens
    }

    private static func replaceAngleTokens(in text: String, userNames: [String: String]) -> String {
        var output = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            output += rest[..<open]
            output += render(token: String(rest[rest.index(after: open)..<close]), userNames: userNames)
            rest = rest[rest.index(after: close)...]
        }
        return output + rest
    }

    private static func render(token: String, userNames: [String: String]) -> String {
        let parts = token.split(separator: "|", maxSplits: 1).map(String.init)
        let target = parts.first ?? ""
        let label = parts.count > 1 ? parts[1] : nil

        switch target.first {
        case "@":
            let id = String(target.dropFirst())
            return "@" + (userNames[id] ?? label ?? "someone")
        case "#":
            return "#" + (label ?? "channel")
        case "!":
            let command = String(target.dropFirst())
            if let label { return label }
            if ["here", "channel", "everyone"].contains(command) { return "@" + command }
            return ""
        default:
            if let label { return label }
            return target.hasPrefix("mailto:") ? String(target.dropFirst("mailto:".count)) : target
        }
    }

    private static func stripFormatting(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "```", with: " ")
        result = result.replacingOccurrences(of: "`", with: "")
        // *bold*, _italic_, ~strike~ around a word or phrase.
        for marker in ["*", "_", "~"] {
            let m = NSRegularExpression.escapedPattern(for: marker)
            let pattern = "(^|[\\s(])\(m)([^\(m)\\n]+?)\(m)(?=$|[\\s).,!?:;])"
            result = result.replacingOccurrences(of: pattern, with: "$1$2", options: .regularExpression)
        }
        // Block quotes.
        result = result.replacingOccurrences(of: "(?m)^&gt;\\s?", with: "", options: .regularExpression)
        return result
    }
}
