import Foundation

/// On-device notification persistence. Stores received push notifications
/// with read/unread state, persisted via UserDefaults.
@Observable
@MainActor
final class NotificationStore {
    static let shared = NotificationStore()

    // MARK: - State

    var notifications: [ARIANotification] = []

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    // MARK: - Persistence

    private let storageKey = "aria_notification_store"
    private let maxNotifications = 200

    private init() {
        load()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ARIANotification].self, from: data) else {
            notifications = []
            return
        }
        notifications = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notifications) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    // MARK: - Actions

    func addNotification(
        title: String,
        body: String,
        category: String,
        conversationId: String?,
        isPIEUrgent: Bool,
        insightContent: String?,
        insightId: String?
    ) {
        let notification = ARIANotification(
            id: UUID().uuidString,
            title: title,
            body: body,
            category: category,
            conversationId: conversationId,
            isPIEUrgent: isPIEUrgent,
            insightContent: insightContent,
            insightId: insightId,
            isRead: false,
            receivedAt: Date()
        )

        notifications.insert(notification, at: 0)

        // Trim if over limit
        if notifications.count > maxNotifications {
            notifications = Array(notifications.prefix(maxNotifications))
        }

        save()
    }

    func markAsRead(_ id: String) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications[index].isRead = true
        save()
    }

    func markAllAsRead() {
        for i in notifications.indices {
            notifications[i].isRead = true
        }
        save()
    }

    func clearAll() {
        notifications = []
        save()
    }

    func removeNotification(_ id: String) {
        notifications.removeAll { $0.id == id }
        save()
    }
}

// MARK: - Model

struct ARIANotification: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let body: String
    let category: String
    let conversationId: String?
    let isPIEUrgent: Bool
    let insightContent: String?
    let insightId: String?
    var isRead: Bool
    let receivedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, body, category, conversationId, isPIEUrgent
        case insightContent, insightId, isRead, receivedAt
    }

    var relativeTime: String {
        let interval = Date().timeIntervalSince(receivedAt)
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let days = hours / 24
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if hours < 24 { return "\(hours)h ago" }
        if days < 7 { return "\(days)d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: receivedAt)
    }
}
