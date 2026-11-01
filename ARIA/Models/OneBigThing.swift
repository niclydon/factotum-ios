import Foundation

/// One Big Thing composites (Factotum 4.0 W3, OB-66557):
/// GET /api/mobile/one-big-thing. Every input carries its value,
/// baseline, and delta so the UI renders evidence, not just a number.
/// Missing data degrades confidence server-side (`status: "missing"`,
/// null fields) rather than being fabricated.
struct MobileOneBigThing: Codable, Sendable, Equatable {
    let contractVersion: String
    let generatedAt: String
    let forDate: String
    let readiness: Readiness
    let cumulativeStress: CumulativeStress
    let bodyAgeIndex: BodyAgeIndex
    let briefSeed: BriefSeed
    let dataNotes: [String]

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case generatedAt = "generated_at"
        case forDate = "for_date"
        case readiness
        case cumulativeStress = "cumulative_stress"
        case bodyAgeIndex = "body_age_index"
        case briefSeed = "brief_seed"
        case dataNotes = "data_notes"
    }

    struct Input: Codable, Sendable, Equatable {
        let status: String
        let value: Double?
        let baseline: Double?
        let delta: Double?
        let deltaPct: Double?
        let unit: String
        let score: Int?

        enum CodingKeys: String, CodingKey {
            case status, value, baseline, delta
            case deltaPct = "delta_pct"
            case unit, score
        }
    }

    struct Readiness: Codable, Sendable, Equatable {
        let score: Int
        let confidence: String
        let inputs: [String: Input]
    }

    /// Contributor detail values are heterogeneous (numbers and
    /// strings like a locality name), so they decode through a small
    /// sum type instead of a lossy dictionary.
    enum DetailValue: Codable, Sendable, Equatable {
        case number(Double)
        case text(String)

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let n = try? c.decode(Double.self) { self = .number(n); return }
            self = .text(try c.decode(String.self))
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .number(let n): try c.encode(n)
            case .text(let s): try c.encode(s)
            }
        }
    }

    struct Contributor: Codable, Sendable, Equatable {
        let status: String
        let score: Int?
        let detail: [String: DetailValue]
    }

    struct CumulativeStress: Codable, Sendable, Equatable {
        let index: Int
        let windowDays: Int
        let daysWithData: Int
        let contributors: [String: Contributor]

        enum CodingKeys: String, CodingKey {
            case index
            case windowDays = "window_days"
            case daysWithData = "days_with_data"
            case contributors
        }
    }

    struct Component: Codable, Sendable, Equatable {
        let status: String
        let recent: Double?
        let reference: Double?
        let delta: Double?
        let deltaPct: Double?
        let unit: String
        let contribution: Double?

        enum CodingKeys: String, CodingKey {
            case status, recent, reference, delta
            case deltaPct = "delta_pct"
            case unit, contribution
        }
    }

    struct BodyAgeIndex: Codable, Sendable, Equatable {
        /// Delta in index points vs the owner's own reference-window
        /// self. Deliberately NOT an age in years (see V4-BUILD-PLAN).
        let deltaIndex: Double
        let direction: String
        let recentWindowDays: Int
        let referenceWindowDays: Int
        let unit: String
        let components: [String: Component]

        enum CodingKeys: String, CodingKey {
            case deltaIndex = "delta_index"
            case direction
            case recentWindowDays = "recent_window_days"
            case referenceWindowDays = "reference_window_days"
            case unit, components
        }
    }

    struct BriefSeed: Codable, Sendable, Equatable {
        let headlineFacts: [String]
        let topStressContributor: String?
        let fallbackParagraph: String

        enum CodingKeys: String, CodingKey {
            case headlineFacts = "headline_facts"
            case topStressContributor = "top_stress_contributor"
            case fallbackParagraph = "fallback_paragraph"
        }
    }
}
