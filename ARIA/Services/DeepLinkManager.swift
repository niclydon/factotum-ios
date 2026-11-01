import Foundation

/// Centralized deep-link routing for Quick Actions, Spotlight, notifications, and Share Extension.
@Observable
@MainActor
final class DeepLinkManager {
    static let shared = DeepLinkManager()

    /// Set this to navigate to a specific conversation.
    var pendingConversationId: String?

    /// Set this to pre-fill the chat input with a prompt.
    var pendingPrompt: String?

    /// Set this to navigate to a specific settings page.
    var pendingRoute: AppRoute?

    /// Set this (from a review-digest push tap) to open the Review tab, optionally on one card.
    var pendingReviewCardId: String?

    /// Set this (Factotum 4.0 W6: Show My Day intent, Spotlight replay days)
    /// with a yyyy-MM-dd date to open the Replay tab on that day.
    var pendingReplayDateString: String?

    enum AppRoute {
        case pushSettings
        case dataSources
    }

    /// Quick Action identifiers.
    enum QuickAction: String {
        case quickQuestion = "com.example.factotum.quick-question"
        case logThought = "com.example.factotum.log-thought"
        case checkMyDay = "com.example.factotum.check-my-day"
    }

    func handleQuickAction(_ action: QuickAction) {
        switch action {
        case .quickQuestion:
            pendingConversationId = nil
            pendingPrompt = nil // Just open a fresh conversation, ready to type
        case .logThought:
            pendingConversationId = nil
            pendingPrompt = "I want to log a thought: "
        case .checkMyDay:
            pendingConversationId = nil
            pendingPrompt = "What does my day look like today?"
        }
    }

    func handleSpotlightConversation(id: String) {
        pendingConversationId = id
    }

    // MARK: - aria:// URL routing (3.2.0)

    /// Settings pages a deep link can target. Consumed by SettingsView's
    /// NavigationStack path; RootTabView switches to Today (the tab whose
    /// toolbar presents Settings) when one is pending.
    enum SettingsPage: Hashable {
        case root, device, dataSources, diagnostics, automations
    }

    /// Tab a deep link wants selected ("today" | "review" | "ask" | "chat").
    var pendingTab: String?

    /// Settings page a deep link wants open (also triggers the sheet).
    var pendingSettingsPage: SettingsPage?

    /// Routes `aria://` URLs: tab names select tabs; settings pages open
    /// Settings on Today; `aria://sync` runs a sweep; `aria://test-event`
    /// proves the Shortcuts pipe. Unknown routes are ignored.
    func handle(url: URL) {
        guard url.scheme == "aria" else { return }
        let route = (url.host ?? "") + url.path
        switch route {
        case "today": pendingTab = "today"
        case "review": pendingTab = "review"
        case "ask": pendingTab = "ask"
        case "chat": pendingTab = "chat"
        case "sync":
            pendingTab = "today"
            Task { await SyncCoordinator.shared.runSweep(trigger: "deeplink") }
        case "settings": pendingSettingsPage = .root
        case "device", "settings/device": pendingSettingsPage = .device
        case "data-sources", "settings/data-sources": pendingSettingsPage = .dataSources
        case "estate", "settings/estate": pendingTab = "estate"
        case "diagnostics", "settings/diagnostics": pendingSettingsPage = .diagnostics
        case "automations", "settings/automations": pendingSettingsPage = .automations
        case "test-event":
            Task { _ = await DeviceEventSync.shared.sendTestEvent() }
        default:
            break
        }
    }
}
