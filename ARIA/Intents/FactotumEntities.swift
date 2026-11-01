import AppIntents
import Foundation

/// App Intents 2.0 entity schemas (Factotum 4.0 W6): Replay days, the One
/// Big Thing composite, and Estate hosts become first-class Siri/Spotlight
/// citizens. Queries fetch live data through the same APIClient the app
/// uses; failures degrade to identity-only entities, never errors.

private func replayDateLabel(_ dateString: String) -> String {
    let parser = DateFormatter()
    parser.calendar = Calendar(identifier: .gregorian)
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.timeZone = TimeZone(identifier: "America/New_York")
    parser.dateFormat = "yyyy-MM-dd"
    guard let date = parser.date(from: dateString) else { return dateString }
    return date.formatted(date: .abbreviated, time: .omitted)
}

private func replayDateString(daysAgo: Int) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/New_York")
    formatter.dateFormat = "yyyy-MM-dd"
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    return formatter.string(from: date)
}

// MARK: - Replay day

struct ReplayDayEntity: AppEntity {
    nonisolated(unsafe) static var typeDisplayRepresentation: TypeDisplayRepresentation = "Replay Day"
    nonisolated(unsafe) static var defaultQuery = ReplayDayQuery()

    var id: String   // yyyy-MM-dd
    var itemCount: Int?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(replayDateLabel(id))",
            subtitle: itemCount.map { "\($0) evidence items" } ?? "Life Replay day"
        )
    }
}

struct ReplayDayQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ReplayDayEntity] {
        var result: [ReplayDayEntity] = []
        for id in identifiers {
            let count = (try? await APIClient.shared.getReplayDay(date: id))?.itemCount
            result.append(ReplayDayEntity(id: id, itemCount: count))
        }
        return result
    }
}

extension ReplayDayQuery: EnumerableEntityQuery {
    func allEntities() async throws -> [ReplayDayEntity] {
        var result: [ReplayDayEntity] = []
        for daysAgo in 0...2 {
            let date = replayDateString(daysAgo: daysAgo)
            let count = (try? await APIClient.shared.getReplayDay(date: date))?.itemCount
            result.append(ReplayDayEntity(id: date, itemCount: count))
        }
        return result
    }
}

// MARK: - One Big Thing

struct OneBigThingEntity: AppEntity {
    nonisolated(unsafe) static var typeDisplayRepresentation: TypeDisplayRepresentation = "One Big Thing"
    nonisolated(unsafe) static var defaultQuery = OneBigThingQuery()

    var id: String   // "today"
    var readiness: Int?
    var confidence: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "One Big Thing",
            subtitle: readiness.map { "Readiness \($0)" } ?? "Today's composite"
        )
    }
}

struct OneBigThingQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [OneBigThingEntity] {
        if let obt = try? await APIClient.shared.getOneBigThing() {
            return [OneBigThingEntity(id: "today", readiness: obt.readiness.score,
                                      confidence: obt.readiness.confidence)]
        }
        return identifiers.map { OneBigThingEntity(id: $0, readiness: nil, confidence: nil) }
    }
}

extension OneBigThingQuery: EnumerableEntityQuery {
    func allEntities() async throws -> [OneBigThingEntity] {
        try await entities(for: ["today"])
    }
}

// MARK: - Estate host

struct EstateHostEntity: AppEntity {
    nonisolated(unsafe) static var typeDisplayRepresentation: TypeDisplayRepresentation = "Estate Host"
    nonisolated(unsafe) static var defaultQuery = EstateHostQuery()

    var id: String   // host key
    var stale: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(id)",
            subtitle: stale ? "Registry stale" : "Reporting"
        )
    }
}

struct EstateHostQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [EstateHostEntity] {
        guard let estate = try? await APIClient.shared.fetchMobileEstate() else {
            return identifiers.map { EstateHostEntity(id: $0, stale: true) }
        }
        return identifiers.map { id in
            let host = estate.hosts.first { $0.host == id }
            return EstateHostEntity(id: id, stale: host?.registryStale ?? true)
        }
    }
}

extension EstateHostQuery: EnumerableEntityQuery {
    func allEntities() async throws -> [EstateHostEntity] {
        guard let estate = try? await APIClient.shared.fetchMobileEstate() else { return [] }
        return estate.hosts.map { EstateHostEntity(id: $0.host, stale: $0.registryStale) }
    }
}

// MARK: - Intents over the entities

struct OpenReplayDayIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Show My Day"
    nonisolated(unsafe) static var description: IntentDescription = "Open Life Replay for a day and see its evidence pack."
    nonisolated(unsafe) static var openAppWhenRun = true

    @Parameter(title: "Day")
    var day: ReplayDayEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLinkManager.shared.pendingReplayDateString = day.id
        DeepLinkManager.shared.pendingTab = "replay"
        return .result()
    }
}

struct OneBigThingGlanceIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "One Big Thing"
    nonisolated(unsafe) static var description: IntentDescription = "Hear today's One Big Thing: readiness, cumulative stress, and the top contributor."
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let obt = try? await APIClient.shared.getOneBigThing() else {
            return .result(dialog: "I could not load today's One Big Thing. Open Factotum and pull to refresh.")
        }
        var dialog = "Readiness \(obt.readiness.score), \(obt.readiness.confidence) confidence."
        dialog += " Cumulative stress index \(obt.cumulativeStress.index) over \(obt.cumulativeStress.windowDays) days."
        if let top = obt.cumulativeStress.contributors
            .max(by: { ($0.value.score ?? 0) < ($1.value.score ?? 0) }) {
            dialog += " Top contributor: \(top.key.replacingOccurrences(of: "_", with: " "))."
        }
        return .result(dialog: "\(dialog)")
    }
}

struct LensStatusIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Lens Status"
    nonisolated(unsafe) static var description: IntentDescription = "Hear how many photos and videos Lens has analyzed on this device."
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = await MainActor.run { () -> (Bool, Int, Int, Date?) in
            let lens = LensService.shared
            return (lens.isAuthorized, lens.analyzedCount, lens.pendingUploadCount, lens.lastRunAt)
        }
        guard snapshot.0 else {
            return .result(dialog: "Lens is not enabled yet. Turn it on in Factotum, Settings, Lens.")
        }
        var dialog = "Lens has analyzed \(snapshot.1) photos and videos on this device."
        if snapshot.2 > 0 {
            dialog += " \(snapshot.2) are waiting to upload."
        }
        if let last = snapshot.3 {
            dialog += " Last run \(RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date()))."
        }
        return .result(dialog: "\(dialog)")
    }
}
