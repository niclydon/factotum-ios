import Foundation

/// One derived photo/video intelligence record — the ONLY thing Lens ever
/// sends to Nexus (Factotum 4.0 W9, OB-66559). Analysis runs entirely on
/// device (Vision + Foundation Models); photo and video ORIGINALS never
/// leave the phone. The server enforces a strict field allowlist matching
/// this shape and rejects anything else.
struct PhotoIntelligenceRecord: Codable, Equatable {
    let assetLocalId: String
    let capturedAt: String        // ISO 8601
    let mediaType: String         // "photo" | "video"
    let caption: String
    let tags: [String]
    let ocrText: String?
    let faceCount: Int
    let place: String?
    let durationS: Double?
    let transcript: String?
    let summary: String?
    /// Payload v2 (Factotum 4.1, OB-68202): bridge metadata for
    /// the W9.1 library bridge. Optional: builds before 4.1 omit
    /// them (nil encodes as absent), and the server accepts both.
    let originalFilename: String?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let derivedAt: String         // ISO 8601
    let analyzerVersions: AnalyzerVersions

    struct AnalyzerVersions: Codable, Equatable {
        let vision: String
        let fm: String
    }

    enum CodingKeys: String, CodingKey {
        case assetLocalId = "asset_local_id"
        case capturedAt = "captured_at"
        case mediaType = "media_type"
        case caption
        case tags
        case ocrText = "ocr_text"
        case faceCount = "face_count"
        case place
        case durationS = "duration_s"
        case transcript
        case summary
        case originalFilename = "original_filename"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
        case derivedAt = "derived_at"
        case analyzerVersions = "analyzer_versions"
    }
}

/// Batch envelope for POST /api/mobile/photo-intelligence (max 100 records).
struct PhotoIntelligenceBatchRequest: Encodable {
    let records: [PhotoIntelligenceRecord]
}

/// Ingest response. Decoded leniently: the app only needs the counts for
/// its own bookkeeping; the contract fixture pins the server's real shape.
struct PhotoIntelligenceResponse: Codable, Equatable {
    let received: Int?
    let inserted: Int?
    let duplicates: Int?
}

/// One asset's bridge metadata for POST
/// /api/mobile/photo-intelligence/enrich (Factotum 4.1, OB-68202):
/// the filename and pixel dimensions that let Nexus bridge this
/// device's Lens records to the Mac library corpus. At least one
/// field is non-nil by construction: pixel dimensions always
/// exist for a live asset.
struct PhotoIntelligenceEnrichRecord: Codable, Equatable {
    let assetLocalId: String
    let originalFilename: String?
    let pixelWidth: Int?
    let pixelHeight: Int?

    enum CodingKeys: String, CodingKey {
        case assetLocalId = "asset_local_id"
        case originalFilename = "original_filename"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
    }
}

/// Batch envelope for the enrich endpoint (max 200 records).
struct PhotoIntelligenceEnrichBatchRequest: Encodable {
    let records: [PhotoIntelligenceEnrichRecord]
}

/// Enrich ack: `updated` counts records that matched at least
/// one stored row server-side; the rest are `not_found`.
struct PhotoIntelligenceEnrichResponse: Codable, Equatable {
    let received: Int?
    let updated: Int?
    let notFound: Int?

    enum CodingKeys: String, CodingKey {
        case received
        case updated
        case notFound = "not_found"
    }
}
