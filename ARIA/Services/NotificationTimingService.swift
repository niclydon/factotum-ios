import Foundation
import UserNotifications

/// Scores notification receptiveness based on context signals.
/// Used by PushNotificationService to delay non-urgent notifications
/// when the user is likely busy, driving, or sleeping.
@MainActor
@Observable
final class NotificationTimingService {
    static let shared = NotificationTimingService()

    // MARK: - Receptiveness Scoring

    /// Score 0.0 (worst time) to 1.0 (best time) for notification delivery.
    /// Uses time-of-day and day-of-week heuristics as primary signals.
    func currentReceptivenessScore() -> Double {
        var score = 0.5 // baseline

        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let weekday = Calendar.current.component(.weekday, from: now)

        // Factor 1: Time of day
        if hour >= 8 && hour <= 21 {
            score += 0.15 // waking hours
        }
        if hour >= 23 || hour < 7 {
            score -= 0.3 // sleeping
        }

        // Factor 2: Business hours on weekdays (likely in meetings)
        let isBusinessHours = weekday >= 2 && weekday <= 6 && hour >= 9 && hour <= 17
        if isBusinessHours {
            score -= 0.1 // possibly in meetings
        }

        return max(0, min(1, score))
    }

    /// Determine if a non-urgent notification should be delayed.
    /// Returns the recommended delay in seconds, or 0 if no delay needed.
    func recommendedDelay(urgency: String) -> TimeInterval {
        // Never delay urgent notifications
        if urgency == "urgent" { return 0 }

        let score = currentReceptivenessScore()

        // If score is low, delay the notification
        if score < 0.3 {
            let delayMinutes = 15.0 + (1.0 - score / 0.3) * 15.0
            return delayMinutes * 60
        }

        return 0
    }
}
