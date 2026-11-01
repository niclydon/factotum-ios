import AppIntents
import Foundation

// Shortcuts personal automations call these to hand ARIA data from other apps
// (iOS 27 "Notification" trigger, Wallet "Transaction", "App" open/close, Focus,
// CarPlay, charger, NFC, …). Every intent runs in the background, queues the event
// durably, tries a short upload, and always reports success so an automation never
// shows an error on the lock screen. Setup: docs/automation-recipes.md.

enum IngestAppState: String, AppEnum {
    case opened
    case closed

    nonisolated(unsafe) static var typeDisplayRepresentation: TypeDisplayRepresentation = "App State"
    nonisolated(unsafe) static var caseDisplayRepresentations: [IngestAppState: DisplayRepresentation] = [
        .opened: "Opened",
        .closed: "Closed",
    ]
}

@MainActor
private enum IngestIntentRunner {
    static func submit(_ event: DeviceEvent) async {
        await DeviceEventQueue.shared.enqueue(DeviceEventFactory.fitted(event))
        await DeviceEventSync.shared.flush(budget: 8)
    }
}

struct LogNotificationIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Log Notification to ARIA"
    nonisolated(unsafe) static var description: IntentDescription = "Send a notification to ARIA. Use with a 'Notification' automation and pass its fields."
    static let supportedModes: IntentModes = .background

    @Parameter(title: "App") var app: String?
    @Parameter(title: "Title") var notificationTitle: String?
    @Parameter(title: "Subtitle") var subtitle: String?
    @Parameter(title: "Body") var body: String?
    @Parameter(title: "Date") var date: Date?
    @Parameter(title: "Automation", default: "Notifications") var automation: String

    func perform() async throws -> some IntentResult {
        let now = Date()
        await IngestIntentRunner.submit(DeviceEventFactory.make(
            channel: .notification, automation: automation, app: app,
            title: notificationTitle, subtitle: subtitle, body: body,
            producedAt: date ?? now, capturedAt: now))
        return .result()
    }
}

struct LogPurchaseIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Log Purchase to ARIA"
    nonisolated(unsafe) static var description: IntentDescription = "Send a Wallet tap-to-pay purchase to ARIA. Use with a 'Transaction' automation."
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Card") var card: String?
    @Parameter(title: "Merchant") var merchant: String?
    @Parameter(title: "Amount") var amount: String?
    @Parameter(title: "Name") var name: String?
    @Parameter(title: "Date") var date: Date?
    @Parameter(title: "Automation", default: "Wallet taps") var automation: String

    func perform() async throws -> some IntentResult {
        let now = Date()
        var fields: [String: EventJSON] = [:]
        if let v = DeviceEventFactory.clip(card, 256) { fields["card"] = .string(v) }
        if let v = DeviceEventFactory.clip(merchant, 256) { fields["merchant"] = .string(v) }
        if let v = DeviceEventFactory.clip(amount, 64) { fields["amount"] = .string(v) }
        if let v = DeviceEventFactory.clip(name, 256) { fields["name"] = .string(v) }
        await IngestIntentRunner.submit(DeviceEventFactory.make(
            channel: .transaction, automation: automation, app: "Wallet", fields: fields,
            producedAt: date ?? now, capturedAt: now))
        return .result()
    }
}

struct LogAppEventIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Log App Event to ARIA"
    nonisolated(unsafe) static var description: IntentDescription = "Record that an app was opened or closed. Use with an 'App' automation."
    static let supportedModes: IntentModes = .background

    @Parameter(title: "App") var app: String
    @Parameter(title: "State", default: .opened) var state: IngestAppState
    @Parameter(title: "Automation", default: "App usage") var automation: String

    func perform() async throws -> some IntentResult {
        let now = Date()
        await IngestIntentRunner.submit(DeviceEventFactory.make(
            channel: .app, automation: automation, app: app,
            fields: ["state": .string(state.rawValue)], producedAt: now, capturedAt: now))
        return .result()
    }
}

struct LogEventIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Log Event to ARIA"
    nonisolated(unsafe) static var description: IntentDescription = "Send any labelled event (Focus, CarPlay, charger, NFC, another app's output) to ARIA."
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Label") var label: String
    @Parameter(title: "Text") var text: String?
    @Parameter(title: "JSON") var json: String?
    @Parameter(title: "Automation", default: "Events") var automation: String

    func perform() async throws -> some IntentResult {
        let now = Date()
        var fields = DeviceEventFactory.jsonFields(json)
        fields["label"] = .string(DeviceEventFactory.clip(label, 64) ?? "event")
        await IngestIntentRunner.submit(DeviceEventFactory.make(
            channel: .custom, automation: automation, body: text, fields: fields,
            producedAt: now, capturedAt: now))
        return .result()
    }
}
