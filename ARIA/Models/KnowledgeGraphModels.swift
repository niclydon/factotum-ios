import Foundation
import SwiftUI

// MARK: - Owner Profile Facts

struct OwnerProfileResponse: Codable, Sendable {
    let facts: [OwnerProfileFact]
    let total: Int
    let domains: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case facts, total, domains
    }
}

struct OwnerProfileFact: Codable, Sendable, Identifiable {
    let id: Int
    let domain: String
    let category: String
    let key: String
    let value: String
    let confidence: Double
    let evidence_count: Int
    let sources: [String]?
    let first_observed_at: String?
    let last_confirmed_at: String
    let valid_from: String?
    let valid_until: String?

    enum CodingKeys: String, CodingKey {
        case id, domain, category, key, value, confidence
        case evidence_count, sources, first_observed_at, last_confirmed_at
        case valid_from, valid_until
    }

    var displayKey: String {
        key.replacingOccurrences(of: "_", with: " ")
    }

    var confidencePercent: Int {
        Int((confidence * 100).rounded())
    }

    var confidenceColor: Color {
        if confidence < 0.4 { return .red }
        if confidence < 0.7 { return .yellow }
        return .green
    }

    var domainColor: Color {
        Self.colorForDomain(domain)
    }

    var formattedDate: String {
        Self.formatDate(last_confirmed_at)
    }

    var formattedDateTime: String {
        Self.formatDateTime(last_confirmed_at)
    }

    // MARK: - Domain Colors

    static func colorForDomain(_ domain: String) -> Color {
        switch domain {
        case "people": .blue
        case "preferences": .purple
        case "places": .green
        case "career": .orange
        case "health": .red
        case "events": .yellow
        case "communication": .cyan
        case "interests": .pink
        case "lifestyle": .teal
        default: .gray
        }
    }

    // MARK: - Date Formatting

    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    static func parseDate(_ iso: String) -> Date? {
        isoFormatter.date(from: iso) ?? isoFormatterNoFrac.date(from: iso)
    }

    static func formatDate(_ iso: String) -> String {
        guard let date = parseDate(iso) else { return iso }
        return dateFormatter.string(from: date)
    }

    static func formatDateTime(_ iso: String) -> String {
        guard let date = parseDate(iso) else { return iso }
        return dateTimeFormatter.string(from: date)
    }
}

// MARK: - Profile Summary

struct ProfileSummaryResponse: Codable, Sendable {
    let sections: [ProfileSection]
    let stats: ProfileStats

    enum CodingKeys: String, CodingKey {
        case sections, stats
    }
}

struct ProfileSection: Codable, Sendable, Identifiable {
    let label: String
    let items: [ProfileSectionItem]

    var id: String { label }

    var inferredDomain: String {
        let lower = label.lowercased()
        if lower.contains("people") || lower.contains("relationship") { return "people" }
        if lower.contains("career") { return "career" }
        if lower.contains("preference") { return "preferences" }
        if lower.contains("interest") { return "interests" }
        if lower.contains("lifestyle") { return "lifestyle" }
        if lower.contains("place") || lower.contains("location") { return "places" }
        if lower.contains("health") { return "health" }
        if lower.contains("communication") { return "communication" }
        if lower.contains("event") { return "events" }
        return "people"
    }
}

struct ProfileSectionItem: Codable, Sendable, Identifiable {
    let key: String
    let value: String
    let confidence: Double
    let sources: [String]

    var id: String { key }

    var displayKey: String {
        key.replacingOccurrences(of: "_", with: " ")
    }

    var confidencePercent: Int {
        Int((confidence * 100).rounded())
    }
}

struct ProfileStats: Codable, Sendable {
    let active_facts: Int
    let superseded_facts: Int
    let domains: Int
    let sources: [String]?
    let last_updated: String?

    enum CodingKeys: String, CodingKey {
        case active_facts, superseded_facts, domains, sources, last_updated
    }
}

// MARK: - iMessage Extractions

struct ImessageExtractionsResponse: Codable, Sendable {
    let watermark: [String: AnyCodableValue]?
    let recent_extractions: [ImessageExtraction]
    let recent_jobs: [ImessageJob]

    enum CodingKeys: String, CodingKey {
        case watermark, recent_extractions, recent_jobs
    }
}

struct ImessageExtraction: Codable, Sendable, Identifiable {
    let id: String
    let category: String
    let key: String
    let value: String
    let version: Int
    let created_at: String

    enum CodingKeys: String, CodingKey {
        case id, category, key, value, version, created_at
    }

    var displayKey: String {
        key.replacingOccurrences(of: "_", with: " ")
    }

    var formattedDateTime: String {
        OwnerProfileFact.formatDateTime(created_at)
    }
}

struct ImessageJob: Codable, Sendable, Identifiable {
    let id: Int
    let status: String
    let created_at: String
    let completed_at: String?
    let result: [String: AnyCodableValue]?

    enum CodingKeys: String, CodingKey {
        case id, status, created_at, completed_at, result
    }

    var formattedCreatedAt: String {
        OwnerProfileFact.formatDateTime(created_at)
    }

    var formattedCompletedAt: String? {
        guard let completed_at else { return nil }
        return OwnerProfileFact.formatDateTime(completed_at)
    }

    var statusColor: Color {
        switch status {
        case "completed": .green
        case "failed": .red
        case "processing": .blue
        default: .gray
        }
    }
}

/// A simple any-value wrapper for JSON dictionaries with mixed value types.
enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if container.decodeNil() { self = .null; return }
        self = .string("?")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    var displayString: String {
        switch self {
        case .string(let v): return v
        case .int(let v): return "\(v)"
        case .double(let v): return String(format: "%.1f", v)
        case .bool(let v): return v ? "true" : "false"
        case .null: return "null"
        }
    }
}
