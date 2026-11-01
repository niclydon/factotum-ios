import Foundation
import ActivityKit

/// Manages Live Activities for meeting countdowns and active conversations.
@Observable
@MainActor
final class LiveActivityService {

    /// Start a meeting countdown Live Activity.
    func startMeetingCountdown(title: String, startTime: Date, location: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = ARIAMeetingAttributes(title: title, location: location ?? "")
        let state = ARIAMeetingAttributes.ContentState(
            startTime: startTime,
            status: startTime > Date() ? "upcoming" : "now"
        )

        do {
            let _ = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: startTime.addingTimeInterval(3600)),
                pushType: nil
            )
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    /// Update a meeting status (e.g., from "upcoming" to "now").
    func updateMeetingStatus(_ status: String) {
        Task {
            for activity in Activity<ARIAMeetingAttributes>.activities {
                let state = ARIAMeetingAttributes.ContentState(
                    startTime: activity.content.state.startTime,
                    status: status
                )
                await activity.update(.init(state: state, staleDate: nil))
            }
        }
    }

    /// End all meeting activities.
    func endAllMeetings() {
        Task {
            for activity in Activity<ARIAMeetingAttributes>.activities {
                let finalState = ARIAMeetingAttributes.ContentState(
                    startTime: activity.content.state.startTime,
                    status: "ended"
                )
                await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(60)))
            }
        }
    }

// MARK: - Factotum progress activities (4.0 W6)

    /// Progress activities are tracked through the system registry
    /// (Activity.activities filtered by kind), the same pattern the
    /// meeting activities use, so short-lived service instances can
    /// update an activity another instance started.
    func beginProgress(kind: String, label: String, detail: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard !Activity<FactotumProgressAttributes>.activities.contains(where: { $0.attributes.kind == kind }) else {
            Task { await updateProgress(kind: kind, detail: detail, progress: nil) }
            return
        }
        let attributes = FactotumProgressAttributes(kind: kind, label: label)
        let state = FactotumProgressAttributes.ContentState(phase: "working", detail: detail, progress: nil)
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(3600)),
                pushType: nil)
        } catch {
            print("[LiveActivity] progress start failed: \(error)")
        }
    }

    func updateProgress(kind: String, detail: String, progress: Double?) async {
        let state = FactotumProgressAttributes.ContentState(phase: "working", detail: detail, progress: progress)
        for activity in Activity<FactotumProgressAttributes>.activities where activity.attributes.kind == kind {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func endProgress(kind: String, detail: String) async {
        let state = FactotumProgressAttributes.ContentState(phase: "done", detail: detail, progress: 1)
        for activity in Activity<FactotumProgressAttributes>.activities where activity.attributes.kind == kind {
            await activity.end(.init(state: state, staleDate: nil),
                               dismissalPolicy: .after(.now.addingTimeInterval(30)))
        }
    }
}

// MARK: - Progress Activity Attributes

struct FactotumProgressAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: String
        var detail: String
        var progress: Double?
    }

    var kind: String   // "replay" | "lens"
    var label: String  // "Life Replay" | "Lens"
}

// MARK: - Meeting Activity Attributes

struct ARIAMeetingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startTime: Date
        var status: String // "upcoming", "now", "ended"
    }

    var title: String
    var location: String
}
