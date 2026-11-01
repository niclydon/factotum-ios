import Foundation

/// Body of POST /api/health-files: live HealthKit clinical records, ECG waveforms and
/// workout routes. Ids are "hk:" + the HKObject UUID (lowercase). Nil arrays are omitted.
struct HealthFilesRequest: Codable, Sendable {
    struct ClinicalItem: Codable, Sendable, Equatable {
        let id: String
        let resourceType: String
        let effectiveAt: String?
        let fhir: EventJSON

        enum CodingKeys: String, CodingKey {
            case id
            case resourceType = "resource_type"
            case effectiveAt = "effective_at"
            case fhir
        }
    }

    struct EcgItem: Codable, Sendable, Equatable {
        let id: String
        let recordedAt: String
        let classification: String?
        let symptoms: String?
        let device: String?
        let sampleRateHz: Double?
        let lead: String?
        let samplesUv: [Double]

        enum CodingKeys: String, CodingKey {
            case id
            case recordedAt = "recorded_at"
            case classification, symptoms, device
            case sampleRateHz = "sample_rate_hz"
            case lead
            case samplesUv = "samples_uv"
        }
    }

    struct RoutePoint: Codable, Sendable, Equatable {
        let lat: Double
        let lon: Double
        let ele: Double?
        let time: String
        let speed: Double?
        let course: Double?
        let hAcc: Double?
        let vAcc: Double?
    }

    struct RouteItem: Codable, Sendable, Equatable {
        let id: String
        let routeName: String?
        let recordedAt: String
        let points: [RoutePoint]

        enum CodingKeys: String, CodingKey {
            case id
            case routeName = "route_name"
            case recordedAt = "recorded_at"
            case points
        }
    }

    var clinical: [ClinicalItem]?
    var ecg: [EcgItem]?
    var routes: [RouteItem]?
}
