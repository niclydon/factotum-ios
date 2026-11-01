import Foundation

/// A flexible JSON value that can be a number, string, or array of objects.
/// Used for the optional `metadata` blob on a raw sample (e.g. workout
/// activity type, energy, distance).
enum HealthValue: Codable, Sendable, Hashable {
    case number(Double)
    case text(String)
    case array([[String: HealthValue]])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) {
            self = .number(d)
        } else if let s = try? container.decode(String.self) {
            self = .text(s)
        } else if let a = try? container.decode([[String: HealthValue]].self) {
            self = .array(a)
        } else {
            throw DecodingError.typeMismatch(HealthValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected number, string, or array"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let d): try container.encode(d)
        case .text(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        }
    }
}

/// One raw HealthKit sample, streamed lossless to `example_raw_healthkit` via
/// POST /api/health-data. This is the backend's "shape B" (per-measurement)
/// payload — detected server-side by the ABSENCE of a `data_type` field. Every
/// HealthKit sample (quantity, category, workout) maps to one of these; curation
/// for usefulness happens downstream in silver/gold, never here.
///
/// `record_type` is the full HealthKit type identifier
/// (e.g. "HKQuantityTypeIdentifierHeartRate", "HKCategoryTypeIdentifierSleepAnalysis",
/// "HKWorkoutTypeIdentifier") — this keeps rows OUT of the narrow legacy partial
/// index (which excludes `record_type LIKE 'HK%'`) so dedup happens only on the
/// full 7-column identity index added in migration 1347:
/// (record_type, source_name, start_date, end_date, value, unit, device).
struct RawHealthSample: Codable, Sendable {
    /// HealthKit type identifier, e.g. "HKQuantityTypeIdentifierHeartRate".
    let recordType: String
    /// ISO-8601 sample start (UTC "Z"). Postgres TIMESTAMPTZ compares by instant.
    let startDate: String
    /// ISO-8601 sample end (UTC "Z").
    let endDate: String
    /// Quantity value in `unit`, category rawValue, or workout duration (seconds).
    let value: Double?
    /// Canonical unit string for `value` ("count/min", "mg/dL", …); nil for
    /// category samples.
    let unit: String?
    /// Originating source app/device name (HKSource.name), e.g. "Apple Watch".
    let sourceName: String?
    /// Hardware device short name (HKDevice.name), e.g. "Apple Watch"; often nil
    /// for manually-entered samples.
    let device: String?
    /// Extra structured attributes (workout activity type / energy / distance).
    let metadata: [String: HealthValue]?

    enum CodingKeys: String, CodingKey {
        case recordType = "record_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case value
        case unit
        case sourceName = "source_name"
        case device
        case metadata
    }
}

/// Wrapper for the batch sync request body.
struct HealthSyncRequest: Codable, Sendable {
    let records: [RawHealthSample]
}

/// Response from POST /api/health-data. `synced` is newly-inserted rows;
/// `conflicted` is idempotent no-ops (already stored). Extra fields are optional
/// so older/newer server shapes both decode.
struct HealthSyncResponse: Codable, Sendable {
    let synced: Int
    let inserted: Int?
    let conflicted: Int?
    let errored: Int?
    let total: Int?
}
