import Foundation
import SwiftData

/// The on-device Lens index: one derived record per analyzed photo/video,
/// in Lens's own SwiftData store (deliberately separate from the chat
/// store so the Lens schema can evolve without touching chat data).
/// Records with `postedAt == nil` are the upload outbox.
@Model
final class PhotoDerivedRecord {
    @Attribute(.unique) var assetLocalId: String
    var capturedAt: Date
    var mediaType: String
    var caption: String
    var tagsJSON: String
    var ocrText: String?
    var faceCount: Int
    var place: String?
    var durationS: Double?
    var transcript: String?
    var summary: String?
    var derivedAt: Date
    /// Photo text index stamp: set when this record's terms have
    /// been acked by POST /api/mobile/photo-terms. Nil means the
    /// terms export is still owed (or queued in the terms outbox).
    var termsExportedAt: Date?
    /// Payload v2 bridge metadata (Factotum 4.1, OB-68202): the
    /// asset's original filename and pixel dimensions, read from
    /// PhotoKit metadata with no image decode. The
    /// `metadataEnrichedAt` stamp is set once the server holds
    /// these fields — posted with the record itself on a fresh
    /// v2 analysis, or via the enrich endpoint for older
    /// records — or when the asset no longer exists on device
    /// and nothing more can be learned. Nil stamp = owed.
    var originalFilename: String? = nil
    var pixelWidth: Int? = nil
    var pixelHeight: Int? = nil
    var metadataEnrichedAt: Date? = nil
    var visionVersion: String
    var fmVersion: String
    var postedAt: Date?

    init(assetLocalId: String, capturedAt: Date, mediaType: String,
         caption: String, tags: [String], ocrText: String?, faceCount: Int,
         place: String?, durationS: Double?, transcript: String?,
         summary: String?, derivedAt: Date, visionVersion: String,
         fmVersion: String) {
        self.assetLocalId = assetLocalId
        self.capturedAt = capturedAt
        self.mediaType = mediaType
        self.caption = caption
        self.tagsJSON = (try? String(data: JSONEncoder().encode(tags), encoding: .utf8)) ?? "[]"
        self.ocrText = ocrText
        self.faceCount = faceCount
        self.place = place
        self.durationS = durationS
        self.transcript = transcript
        self.summary = summary
        self.derivedAt = derivedAt
        self.visionVersion = visionVersion
        self.fmVersion = fmVersion
        self.postedAt = nil
    }

    var tags: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? []
    }

    func wireRecord() -> PhotoIntelligenceRecord {
        let iso = ISO8601DateFormatter()
        return PhotoIntelligenceRecord(
            assetLocalId: assetLocalId,
            capturedAt: iso.string(from: capturedAt),
            mediaType: mediaType,
            caption: caption,
            tags: tags,
            ocrText: ocrText,
            faceCount: faceCount,
            place: place,
            durationS: durationS,
            transcript: transcript,
            summary: summary,
            originalFilename: originalFilename,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            derivedAt: iso.string(from: derivedAt),
            analyzerVersions: .init(vision: visionVersion, fm: fmVersion)
        )
    }
}
