import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes ARIA conversations in Spotlight so they're searchable from the home screen.
enum SpotlightIndexer {

    static let domainIdentifier = "com.example.factotum.conversations"
    static let replayDomainIdentifier = "com.example.factotum.replay-days"

    /// Index one Replay day (Factotum 4.0 W6) so "Show my day" style
    /// Spotlight searches surface it; the identifier routes to the
    /// Replay tab on tap.
    static func indexReplayDay(dateString: String, label: String, itemCount: Int) {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = "Life Replay \u{2014} \(label)"
        attributes.contentDescription = "\(itemCount) evidence items recorded this day."
        attributes.keywords = ["replay", "life replay", "my day", label]
        let item = CSSearchableItem(
            uniqueIdentifier: "replay-day:\(dateString)",
            domainIdentifier: replayDomainIdentifier,
            attributeSet: attributes)
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                Logger.shared.logMinimal("spotlight: replay-day index failed \(error.localizedDescription)")
            }
        }
    }

    /// Index a batch of conversations in Spotlight.
    static func indexConversations(_ conversations: [Conversation]) {
        let items = conversations.compactMap { conv -> CSSearchableItem? in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = conv.title
            attributes.contentDescription = conv.lastMessage
            attributes.lastUsedDate = conv.updatedAt

            return CSSearchableItem(
                uniqueIdentifier: conv.id,
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
        }

        guard !items.isEmpty else { return }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                print("[SpotlightIndexer] Failed to index: \(error)")
            }
        }
    }

    /// Remove a conversation from the Spotlight index.
    static func removeConversation(id: String) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id]) { error in
            if let error {
                print("[SpotlightIndexer] Failed to remove: \(error)")
            }
        }
    }

    /// Remove all ARIA conversations from Spotlight.
    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { error in
            if let error {
                print("[SpotlightIndexer] Failed to remove all: \(error)")
            }
        }
    }
}
