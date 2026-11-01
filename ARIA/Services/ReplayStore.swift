import Foundation

/// State for the Replay tab (Factotum 4.0 W1): the selected day's evidence
/// pack plus ask-a-question narratives over a Day / Week / Month scope
/// ending on the selected day.
@Observable
@MainActor
final class ReplayStore {
    static let shared = ReplayStore()

    enum AskScope: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"

        var days: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 31
            }
        }
    }

    private(set) var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    private(set) var pack: Loadable<ReplayDayPack> = .idle
    var askScope: AskScope = .day
    private(set) var isAsking = false
    private(set) var askResponse: ReplayAskResponse?
    private(set) var askError: String?

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func dateString(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    func select(date: Date) async {
        selectedDate = Calendar.current.startOfDay(for: date)
        await load()
    }

    func shift(days: Int) async {
        let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
        await select(date: next)
    }

    func load() async {
        pack = .loading
        do {
            let loaded = try await APIClient.shared.getReplayDay(date: dateString(selectedDate))
            pack = .loaded(loaded)
            SpotlightIndexer.indexReplayDay(
                dateString: loaded.date,
                label: selectedDate.formatted(date: .abbreviated, time: .omitted),
                itemCount: loaded.itemCount)
        } catch {
            pack = .failed(error.localizedDescription)
        }
    }

    func ask(question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAsking else { return }
        isAsking = true
        askError = nil
        let activity = LiveActivityService()
        activity.beginProgress(kind: "replay", label: "Life Replay", detail: "Assembling evidence\u{2026}")
        defer { isAsking = false }
        let to = selectedDate
        let from = Calendar.current.date(byAdding: .day, value: -(askScope.days - 1), to: to) ?? to
        do {
            askResponse = try await APIClient.shared.postReplayAsk(
                question: trimmed, from: dateString(from), to: dateString(to))
            await activity.endProgress(kind: "replay", detail: "Narrative ready")
        } catch {
            askError = error.localizedDescription
            await activity.endProgress(kind: "replay", detail: "Replay failed")
        }
    }
}
