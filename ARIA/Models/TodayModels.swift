import Foundation

struct SeriesPoint: Codable, Sendable, Hashable {
    let date: String
    let value: Double
}

/// GET /v1/health/sleep/nightly — SleepNightlyProfile (subset)
struct SleepNightlyProfile: Codable, Sendable {
    struct Bundle: Codable, Sendable { let series: [SeriesPoint] }
    let sleepHours: Bundle
    let efficiency: Bundle
    enum CodingKeys: String, CodingKey { case sleepHours = "sleep_hours", efficiency }
    var lastNight: SeriesPoint? { sleepHours.series.last }
    var lastEfficiency: Double? { efficiency.series.last?.value }
}

/// GET /v1/health/sleep/recovery — SleepRecoveryProfile (subset)
struct SleepRecoveryProfile: Codable, Sendable {
    struct Readiness: Codable, Sendable { let day: String; let readinessState: String?; let headline: String?
        enum CodingKeys: String, CodingKey { case day, headline; case readinessState = "readiness_state" } }
    struct Score: Codable, Sendable { let series: [SeriesPoint] }
    let recoveryScore: Score
    let readiness: [Readiness]
    enum CodingKeys: String, CodingKey { case recoveryScore = "recovery_score", readiness }
    var latestScore: Double? { recoveryScore.series.last?.value }
    var latestReadiness: Readiness? { readiness.first }
}

/// GET /v1/health/activity/daily — ActivityDailyProfile (subset)
struct ActivityDailyProfile: Codable, Sendable {
    struct Bundle: Codable, Sendable { let unit: String?; let series: [SeriesPoint] }
    let metrics: [String: Bundle]
    func today(_ metric: String, todayKey: String) -> Double? {
        metrics[metric]?.series.last(where: { $0.date.hasPrefix(todayKey) })?.value
    }
}

/// GET /v1/health/activity/workouts — { workouts: [WorkoutListItem] } (confirm the envelope key with
/// `grep -n "workouts" ~/projects/nexus/packages/api/src/lib/health-activity.ts`; fall back to top-level array if needed)
struct WorkoutsResponse: Codable, Sendable { let workouts: [WorkoutListItem] }
struct WorkoutListItem: Codable, Sendable, Identifiable {
    let sourceId: String
    let title: String?
    let startAt: String?
    let workoutType: String?
    let durationMinutes: Double?
    let calories: Double?
    var id: String { sourceId }
    enum CodingKeys: String, CodingKey {
        case title, calories
        case sourceId = "source_id"; case startAt = "start_at"; case workoutType = "workout_type"; case durationMinutes = "duration_minutes"
    }
}

/// GET /v1/location/visits — { visits: [...] } rows from device_visits
struct VisitsResponse: Codable, Sendable { let visits: [Visit] }
struct Visit: Codable, Sendable, Identifiable {
    let id: String
    let arrivalDate: String?
    let departureDate: String?
    let latitude: Double?
    let longitude: Double?
    enum CodingKeys: String, CodingKey { case id, latitude, longitude; case arrivalDate = "arrival_date"; case departureDate = "departure_date" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) } else { id = try c.decode(String.self, forKey: .id) }
        arrivalDate = try c.decodeIfPresent(String.self, forKey: .arrivalDate)
        departureDate = try c.decodeIfPresent(String.self, forKey: .departureDate)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
    }
}

/// GET /v1/timeline/events — { events: [...], count }
struct TimelineEventsResponse: Codable, Sendable { let events: [TimelineEvent] }
struct TimelineEvent: Codable, Sendable, Identifiable {
    let id: String
    let eventTime: String?
    let eventType: String?
    let title: String?
    let summary: String?
    enum CodingKeys: String, CodingKey { case id, title, summary; case eventTime = "event_time"; case eventType = "event_type" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) } else { id = try c.decode(String.self, forKey: .id) }
        eventTime = try c.decodeIfPresent(String.self, forKey: .eventTime)
        eventType = try c.decodeIfPresent(String.self, forKey: .eventType)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
    }
}
