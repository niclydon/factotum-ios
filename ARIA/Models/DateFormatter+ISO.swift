import Foundation

extension DateFormatter {
    /// Parses ISO 8601 timestamps from the ARIA API (e.g. "2025-01-15T09:00:00.000Z").
    static let iso8601Full: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// Fallback for timestamps without milliseconds.
    static let iso8601NoMs: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}

extension String {
    /// Parse an ISO 8601 date string, trying full precision first then fallback.
    var iso8601Date: Date? {
        DateFormatter.iso8601Full.date(from: self) ?? DateFormatter.iso8601NoMs.date(from: self)
    }
}
