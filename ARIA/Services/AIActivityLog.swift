import Foundation

/// One entry in the on-device AI log (Factotum 4.0 W7, Trust Ledger):
/// every time on-device intelligence runs, what it processed, and exactly
/// how much left the device because of it.
struct AIActivityEntry: Codable, Identifiable, Equatable {
    let id: String
    let at: Date
    /// lens.analyze | lens.upload | lens.terms | lens.enrich | brief.generate
    let kind: String
    let detail: String
    /// Assets/items the run processed on-device.
    let assets: Int
    /// Records that left the device as a result (0 for pure on-device work).
    let leftDevice: Int
}

/// A small durable ring buffer (UserDefaults JSON, newest last, capped)
/// backing the Trust Ledger's AI log. Written by LensService (analysis
/// runs and uploads) and MorningBriefService (on-device paragraph
/// generation); read by TrustLedgerView.
enum AIActivityLog {
    private static let key = "ai_activity_log_v1"
    private static let cap = 100

    static func record(kind: String, detail: String, assets: Int, leftDevice: Int) {
        var entries = load()
        entries.append(AIActivityEntry(
            id: UUID().uuidString, at: Date(), kind: kind,
            detail: detail, assets: assets, leftDevice: leftDevice))
        if entries.count > cap {
            entries.removeFirst(entries.count - cap)
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Newest first, for display.
    static func entries() -> [AIActivityEntry] {
        load().reversed()
    }

    private static func load() -> [AIActivityEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([AIActivityEntry].self, from: data)
        else { return [] }
        return entries
    }
}
