import Foundation

/// Sanitize text for user-facing display.
/// Strips JSON fragments, XML/HTML tags, markdown artifacts,
/// and normalizes whitespace.
enum TextSanitizer {
    static func sanitize(_ text: String?) -> String {
        guard var s = text, !s.isEmpty else { return "" }

        // Strip XML/HTML tags
        s = s.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)

        // Strip markdown headers
        s = s.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)

        // Strip code fences
        s = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)

        // Strip inline code markers
        s = s.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)

        // Normalize whitespace
        s = s.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
