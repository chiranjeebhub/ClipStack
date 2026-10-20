import Foundation

/// Decides whether copied text is a link, a color, code or plain text.
public enum ContentClassifier {
    public static func classify(_ string: String) -> ClipKind {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if isColor(trimmed) { return .color }
        if isLink(trimmed) { return .link }
        if isCode(string) { return .code }
        return .text
    }

    public static func isColor(_ s: String) -> Bool {
        guard s.hasPrefix("#") else { return false }
        let hex = s.dropFirst()
        guard [3, 6, 8].contains(hex.count) else { return false }
        return hex.allSatisfy(\.isHexDigit)
    }

    public static func isLink(_ s: String) -> Bool {
        guard !s.isEmpty, !s.contains(where: \.isWhitespace) else { return false }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased() else { return false }
        switch scheme {
        case "http", "https", "ftp":
            return url.host != nil
        case "mailto":
            return s.count > "mailto:".count
        default:
            return false
        }
    }

    private static let codeTokens = [
        "func ", "def ", "class ", "struct ", "import ", "return ", "const ", "let ", "var ",
        "#include", "public ", "private ", "=>", "->", "!=", "==", "&&", "||", "</", "/>", "();",
    ]

    public static func isCode(_ s: String) -> Bool {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: true)
        var score = 0
        for token in codeTokens where s.contains(token) { score += 1 }
        if s.contains("{") && s.contains("}") { score += 2 }
        let semicolonLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasSuffix(";") }.count
        if semicolonLines > 0 { score += 1 }
        let indented = lines.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") }.count
        if lines.count > 1 && indented > 0 { score += 2 }
        // Prose often contains a stray "let" or "class", so require several independent signals.
        return score >= 3
    }
}
