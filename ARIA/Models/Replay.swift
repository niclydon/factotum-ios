import Foundation

/// Life Replay DTOs (Factotum 4.0 W1, OB-66560). The day pack assembles one
/// day of the owner's recorded life across seven families; every item
/// carries a stable id so ask narratives can cite it, and the ask response
/// resolves citations server-side (unknown ids are stripped from the
/// narrative and reported in unresolvedCitations).
struct ReplayDayPack: Codable, Equatable, Sendable {
    let contractVersion: String
    let date: String
    let generatedAt: String
    let families: [String: ReplayFamily]
    let counts: [String: Int]
    let itemCount: Int
    let dataNotes: [String]

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case date
        case generatedAt = "generated_at"
        case families
        case counts
        case itemCount = "item_count"
        case dataNotes = "data_notes"
    }

    /// Families in display order.
    static let familyOrder = ["timeline", "visits", "health", "workouts", "music", "looki", "photos"]

    var orderedFamilies: [(key: String, family: ReplayFamily)] {
        Self.familyOrder.compactMap { key in
            families[key].map { (key, $0) }
        }
    }
}

struct ReplayFamily: Codable, Equatable, Sendable {
    let count: Int
    let truncated: Bool
    let items: [ReplayItem]
}

struct ReplayItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let family: String
    let source: String
    let timestamp: String
    let summary: String
    let fields: [String: ReplayFieldValue]
}

/// Heterogeneous per-family item fields (numbers, strings, bools, nested).
enum ReplayFieldValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([ReplayFieldValue])
    case object([String: ReplayFieldValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ReplayFieldValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ReplayFieldValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported field value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Compact display form for the item detail rows.
    var display: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(value)) : String(format: "%.1f", value)
        case .bool(let value): return value ? "yes" : "no"
        case .null: return "—"
        case .array(let values): return values.map(\.display).joined(separator: ", ")
        case .object(let dict):
            return dict.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.display)" }.joined(separator: ", ")
        }
    }
}

struct ReplayAskRequest: Encodable {
    let question: String
    let range: Range

    struct Range: Encodable {
        let from: String
        let to: String
    }
}

struct ReplayAskResponse: Codable, Equatable, Sendable {
    let contractVersion: String
    let generatedAt: String
    let question: String
    let range: Range
    let narrative: String
    let citations: [ReplayItem]
    let unresolvedCitations: [String]
    let pack: PackSummary

    struct Range: Codable, Equatable, Sendable {
        let from: String
        let to: String
    }

    struct PackSummary: Codable, Equatable, Sendable {
        let itemCount: Int
        let counts: [String: Int]
        let truncated: Bool
        let truncatedFamilies: [String]
        let dataNotes: [String]

        enum CodingKeys: String, CodingKey {
            case itemCount = "item_count"
            case counts
            case truncated
            case truncatedFamilies = "truncated_families"
            case dataNotes = "data_notes"
        }
    }

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case generatedAt = "generated_at"
        case question
        case range
        case narrative
        case citations
        case unresolvedCitations = "unresolved_citations"
        case pack
    }
}
