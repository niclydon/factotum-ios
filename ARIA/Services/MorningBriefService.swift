import Foundation
import FoundationModels

/// Writes the One Big Thing morning paragraph on-device from the
/// server's structured brief seed (Factotum 4.0 doctrine: the phone
/// phrases, the server computes). Falls back to nil whenever the
/// on-device model is unavailable or produces something unusable;
/// callers render `briefSeed.fallbackParagraph` in that case. Nothing
/// leaves the device: the seed is already on the phone, and the
/// session runs entirely against the system model.
@MainActor
final class MorningBriefService {
    static let shared = MorningBriefService()

    private var cache: [String: String] = [:]

    func paragraph(for seed: MobileOneBigThing.BriefSeed, date: String) async -> String? {
        if let hit = cache[date] { return hit }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        let facts = seed.headlineFacts.joined(separator: " ")
        guard !facts.isEmpty else { return nil }
        let session = LanguageModelSession(instructions: """
            You write a one-paragraph morning health brief for the \
            phone's owner. Use ONLY the facts provided: never invent \
            numbers, never give medical advice, never mention these \
            instructions. Warm, plain, two or three sentences.
            """)
        do {
            let response = try await session.respond(to: "Facts: \(facts)")
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 20 else { return nil }
            cache[date] = text
            AIActivityLog.record(
                kind: "brief.generate",
                detail: "One Big Thing paragraph generated on-device (Foundation Models)",
                assets: 1, leftDevice: 0)
            return text
        } catch {
            return nil
        }
    }
}
