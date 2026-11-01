import Foundation
import SwiftData

/// One pending term export for the photo text index, in Lens's own
/// store alongside PhotoDerivedRecord. Rows are deleted when the
/// server acks the batch; the matching PhotoDerivedRecord's
/// termsExportedAt is stamped at the same moment, so this outbox
/// plus that stamp are the index's durable progress record.
/// `replace` is the re-OCR supersede flag (OB-67026): the server
/// deletes the asset's prior terms in the same transaction.
@Model
final class PhotoTermsOutboxRecord {
    @Attribute(.unique) var assetLocalId: String
    var capturedAt: Date
    var termsJSON: String
    var replace: Bool
    var queuedAt: Date

    init(assetLocalId: String, capturedAt: Date, terms: [String], replace: Bool) {
        self.assetLocalId = assetLocalId
        self.capturedAt = capturedAt
        self.termsJSON = (try? String(data: JSONEncoder().encode(terms), encoding: .utf8)) ?? "[]"
        self.replace = replace
        self.queuedAt = Date()
    }

    var terms: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(termsJSON.utf8))) ?? []
    }

    func wireRecord() -> PhotoTermsRecord {
        let iso = ISO8601DateFormatter()
        return PhotoTermsRecord(
            assetLocalId: assetLocalId,
            capturedAt: iso.string(from: capturedAt),
            terms: terms,
            replace: replace ? true : nil)
    }
}
