import Foundation

enum Loadable<T: Sendable>: Sendable {
    case idle, loading, loaded(T), empty, failed(String)
}

@Observable
@MainActor
final class TodayStore {
    static let shared = TodayStore()

    private(set) var sleep: Loadable<(SleepNightlyProfile, SleepRecoveryProfile?)> = .idle
    private(set) var activity: Loadable<(ActivityDailyProfile, [WorkoutListItem])> = .idle
    private(set) var places: Loadable<([Visit], [TimelineEvent])> = .idle
    private(set) var oneBigThing: Loadable<MobileOneBigThing> = .idle
    private(set) var lastRefreshAt: Date?

    // Refresh coordination (4.0.2): TodayView's .task is cancelled
    // whenever the view disappears, which in a TabView is every tab
    // switch, and .refreshable can overlap it. Before this guard, a
    // cancelled run wrote .failed("cancelled") into this shared store,
    // and lastRefreshAt — set at refresh START — blocked the retry
    // for ten minutes, so Sleep/Activity/Places stuck on "Couldn't
    // load — cancelled" (field report 2026-10-20). Rules now:
    // refreshes are single-flight; cancellation is never a failure
    // state (a cancelled loader restores its previous state);
    // lastRefreshAt advances only when a refresh actually completes;
    // a superseded generation never writes.
    private var inFlight: Task<Void, Never>?
    private var generation = 0

    var todayKey: String { Self.dayKey(Date()) }

    static func dayKey(_ d: Date) -> String {
        let f = DateFormatter(); f.calendar = .current; f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    func refreshIfStale(maxAge: TimeInterval = 600) async {
        if let at = lastRefreshAt, Date().timeIntervalSince(at) < maxAge { return }
        await refresh()
    }

    func refresh() async {
        if let inFlight { await inFlight.value; return }
        generation += 1
        let gen = generation
        let task = Task { await self.performRefresh(gen) }
        inFlight = task
        await task.value
        if generation == gen { inFlight = nil }
    }

    private func performRefresh(_ gen: Int) async {
        async let s: Void = loadSleep(gen)
        async let a: Void = loadActivity(gen)
        async let p: Void = loadPlaces(gen)
        async let o: Void = loadOneBigThing(gen)
        _ = await (s, a, p, o)
        if gen == generation, !Task.isCancelled { lastRefreshAt = Date() }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return Task.isCancelled
    }

    private func loadOneBigThing(_ gen: Int) async {
        let previous = oneBigThing
        if gen == generation, case .idle = oneBigThing { oneBigThing = .loading }
        do {
            let loaded = try await APIClient.shared.getOneBigThing()
            guard gen == generation, !Task.isCancelled else { return }
            oneBigThing = .loaded(loaded)
            WidgetDataService.updateOneBigThing(
                readiness: loaded.readiness.score,
                stressIndex: loaded.cumulativeStress.index,
                forDate: loaded.forDate)
        } catch {
            guard gen == generation else { return }
            if isCancellation(error) {
                oneBigThing = previous
            } else {
                // Endpoint not deployed yet (OB-66557) or offline: the card
                // renders nothing on .failed, keeping Today clean.
                oneBigThing = .failed(String(describing: error))
            }
        }
    }

    private func loadSleep(_ gen: Int) async {
        let previous = sleep
        if gen == generation { sleep = .loading }
        do {
            let nightly = try await APIClient.shared.getSleepNightly()
            let recovery = try? await APIClient.shared.getSleepRecovery()
            guard gen == generation, !Task.isCancelled else { return }
            sleep = nightly.lastNight == nil ? .empty : .loaded((nightly, recovery))
        } catch {
            guard gen == generation else { return }
            sleep = isCancellation(error) ? previous : .failed(error.localizedDescription)
        }
    }

    private func loadActivity(_ gen: Int) async {
        let previous = activity
        if gen == generation { activity = .loading }
        do {
            let daily = try await APIClient.shared.getActivityDaily()
            let workouts = (try? await APIClient.shared.getWorkouts())?.workouts ?? []
            guard gen == generation, !Task.isCancelled else { return }
            activity = daily.metrics.isEmpty ? .empty : .loaded((daily, workouts))
        } catch {
            guard gen == generation else { return }
            activity = isCancellation(error) ? previous : .failed(error.localizedDescription)
        }
    }

    private func loadPlaces(_ gen: Int) async {
        let previous = places
        if gen == generation { places = .loading }
        do {
            let start = Calendar.current.startOfDay(for: Date())
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
            let iso = ISO8601DateFormatter()
            async let v = APIClient.shared.getVisits()
            async let e = APIClient.shared.getTimelineEvents(from: iso.string(from: start), to: iso.string(from: end))
            let (visits, events) = try await (v, e)
            guard gen == generation, !Task.isCancelled else { return }
            let todays = visits.visits.filter { ($0.arrivalDate ?? "").hasPrefix(Self.dayKey(start)) }
            places = (todays.isEmpty && events.events.isEmpty) ? .empty : .loaded((todays, events.events))
        } catch {
            guard gen == generation else { return }
            places = isCancellation(error) ? previous : .failed(error.localizedDescription)
        }
    }
}
