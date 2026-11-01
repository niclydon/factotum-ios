import AppIntents
import Foundation

// MARK: - Ask ARIA Intent

struct AskARIAIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Ask ARIA"
    nonisolated(unsafe) static var description: IntentDescription = "Ask ARIA a question and get a response."
    nonisolated(unsafe) static var openAppWhenRun = false

    @Parameter(title: "Question")
    var question: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let serverURL = KeychainManager.getServerURL(),
              let token = KeychainManager.getToken(),
              let url = URL(string: "\(serverURL)/api/chat") else {
            return .result(value: "Not signed in to ARIA.", dialog: "Not signed in to ARIA. Open the app first.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["content": question])
        request.timeoutInterval = 30

        let (data, _) = try await URLSession.shared.data(for: request)
        let responseText = Self.parseSSEResponse(data)

        if responseText.isEmpty {
            return .result(value: "ARIA didn't respond.", dialog: "ARIA didn't respond. Try again.")
        }

        return .result(value: responseText, dialog: "\(responseText)")
    }

    private static func parseSSEResponse(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        var result = ""
        for line in text.split(separator: "\n") {
            if line.hasPrefix("data: ") {
                let payload = String(line.dropFirst(6))
                if let data = payload.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let type = json["type"] as? String,
                   type == "chunk",
                   let chunk = json["text"] as? String {
                    result += chunk
                }
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Log a Thought Intent

struct LogThoughtIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Log a Thought"
    nonisolated(unsafe) static var description: IntentDescription = "Send a quick thought or note to ARIA."
    nonisolated(unsafe) static var openAppWhenRun = false

    @Parameter(title: "Thought")
    var thought: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let serverURL = KeychainManager.getServerURL(),
              let token = KeychainManager.getToken(),
              let url = URL(string: "\(serverURL)/api/chat") else {
            return .result(dialog: "Not signed in to ARIA.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "content": "I want to log a thought: \(thought)"
        ])
        request.timeoutInterval = 30

        let _ = try await URLSession.shared.data(for: request)
        return .result(dialog: "Logged with ARIA.")
    }
}

// MARK: - Check My Day Intent

struct CheckMyDayIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Check My Day"
    nonisolated(unsafe) static var description: IntentDescription = "Ask ARIA what your day looks like."
    nonisolated(unsafe) static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            DeepLinkManager.shared.pendingPrompt = "What does my day look like today?"
        }
        return .result()
    }
}

// MARK: - Sync Now Intent (Factotum 3.2)

struct SyncNowIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Sync Factotum"
    nonisolated(unsafe) static var description: IntentDescription = "Run a Factotum sync sweep now: device events, health, motion, music, health records."
    static let supportedModes: IntentModes = .background

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await SyncCoordinator.shared.runSweep(trigger: "shortcut")
        return .result(dialog: "Factotum sync complete.")
    }
}

// MARK: - Factotum Status Intent (Factotum 3.2)

struct FactotumStatusIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Factotum Status"
    nonisolated(unsafe) static var description: IntentDescription = "Hear how Factotum's sync pipes are doing."
    nonisolated(unsafe) static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = SyncFreshness.load()
        let dayAgo = Date().addingTimeInterval(-24 * 3600)
        let fresh = snapshot.sources.values.filter { $0 > dayAgo }.count
        let total = snapshot.sources.count
        guard total > 0 else {
            return .result(dialog: "No syncs recorded yet. Open Factotum once so it can check in.")
        }
        let bg = snapshot.lastBackgroundRun.map {
            RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date())
        } ?? "never"
        return .result(dialog: "\(fresh) of \(total) sources synced in the last day. Last background run \(bg).")
    }
}

// MARK: - App Shortcuts Provider

struct ARIAShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskARIAIntent(),
            phrases: [
                "Ask \(.applicationName) a question",
                "Ask \(.applicationName)",
                "Hey \(.applicationName)",
            ],
            shortTitle: "Ask ARIA",
            systemImageName: "bubble.left.fill"
        )
        AppShortcut(
            intent: LogThoughtIntent(),
            phrases: [
                "Log a thought with \(.applicationName)",
                "Tell \(.applicationName) something",
                "Note to \(.applicationName)",
            ],
            shortTitle: "Log a Thought",
            systemImageName: "pencil.line"
        )
        AppShortcut(
            intent: SyncNowIntent(),
            phrases: [
                "Sync \(.applicationName)",
                "Sync with \(.applicationName)",
            ],
            shortTitle: "Sync Factotum",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        AppShortcut(
            intent: OpenReplayDayIntent(),
            phrases: [
                "Show my day with \(.applicationName)",
                "Replay my day in \(.applicationName)",
            ],
            shortTitle: "Show My Day",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: OneBigThingGlanceIntent(),
            phrases: [
                "One Big Thing in \(.applicationName)",
                "My readiness in \(.applicationName)",
            ],
            shortTitle: "One Big Thing",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: LensStatusIntent(),
            phrases: [
                "Lens status in \(.applicationName)",
            ],
            shortTitle: "Lens Status",
            systemImageName: "camera.aperture"
        )
        AppShortcut(
            intent: FactotumStatusIntent(),
            phrases: [
                "\(.applicationName) status",
                "Status from \(.applicationName)",
            ],
            shortTitle: "Factotum Status",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: CheckMyDayIntent(),
            phrases: [
                "Check my day with \(.applicationName)",
                "\(.applicationName) what's my day like",
            ],
            shortTitle: "Check My Day",
            systemImageName: "calendar"
        )
    }
}
