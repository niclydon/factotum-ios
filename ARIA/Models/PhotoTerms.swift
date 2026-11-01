import Foundation

/// Wire types for POST /api/mobile/photo-terms (photo text index
/// prototype, OB-66960). The phone exports tokenized Vision OCR terms
/// per asset; Nexus lands them in factotum_photo_terms, a sibling of
/// the Mac leo mirror (photo_search_terms), never inside it.
struct PhotoTermsRecord: Codable, Sendable {
    let assetLocalId: String
    let capturedAt: String?
    let terms: [String]
    /// Re-OCR supersede flag (full build, OB-67026): when true the
    /// server deletes the asset's prior terms in the same
    /// transaction before inserting these. Nil (omitted) keeps the
    /// insert-only default.
    let replace: Bool?

    init(assetLocalId: String, capturedAt: String?, terms: [String], replace: Bool? = nil) {
        self.assetLocalId = assetLocalId
        self.capturedAt = capturedAt
        self.terms = terms
        self.replace = replace
    }

    enum CodingKeys: String, CodingKey {
        case assetLocalId = "asset_local_id"
        case capturedAt = "captured_at"
        case terms
        case replace
    }
}

struct PhotoTermsBatchRequest: Codable, Sendable {
    let records: [PhotoTermsRecord]
}

/// Ack for POST /api/mobile/photo-terms. Mirrors
/// fixtures/mobile-api.v1/mobile-photo-terms.json. All fields
/// optional-tolerant like the photo-intelligence ack.
struct PhotoTermsResponse: Codable, Equatable {
    let receivedTerms: Int?
    let inserted: Int?
    let duplicates: Int?

    enum CodingKeys: String, CodingKey {
        case receivedTerms = "received_terms"
        case inserted
        case duplicates
    }
}
