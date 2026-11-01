import Foundation

/// `GET /api/mobile/bootstrap` — config-only capabilities snapshot (OB-52301, contract 1.1.0).
/// No private content. Used for UI gating and degraded-state copy; never blocks chat.
/// The card-console fields (`card_surface`, `delivery_mode`, `supported_features.cards`) were
/// retired with the Matrix console (OB-53324); `review_cards` advertises the Review tab's routes.
struct MobileBootstrap: Codable, Sendable, Equatable {
    let contractVersion: String
    let serverTime: String
    let supportedFeatures: SupportedFeatures
    let push: PushCapability
    let dataSourceFreshnessThresholds: FreshnessThresholds
    let appVersion: AppVersionHints
    let routeFlags: [String: String]

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case serverTime = "server_time"
        case supportedFeatures = "supported_features"
        case push
        case dataSourceFreshnessThresholds = "data_source_freshness_thresholds"
        case appVersion = "app_version"
        case routeFlags = "route_flags"
    }

    struct SupportedFeatures: Codable, Sendable, Equatable {
        let chat: Bool
        let commandAsk: Bool
        let healthSync: Bool
        let locationSync: Bool
        let activitySync: Bool
        let musicSync: Bool
        let push: Bool
        let inbox: Bool
        let proactive: Bool
        let notificationsSettings: Bool
        /// Absent on a pre-1.1.0 server → false (Review tab shows its "unavailable" state).
        let reviewCards: Bool

        enum CodingKeys: String, CodingKey {
            case chat, push, inbox, proactive
            case commandAsk = "command_ask"
            case healthSync = "health_sync"
            case locationSync = "location_sync"
            case activitySync = "activity_sync"
            case musicSync = "music_sync"
            case notificationsSettings = "notifications_settings"
            case reviewCards = "review_cards"
        }

        init(chat: Bool, commandAsk: Bool, healthSync: Bool, locationSync: Bool, activitySync: Bool,
             musicSync: Bool, push: Bool, inbox: Bool, proactive: Bool, notificationsSettings: Bool, reviewCards: Bool) {
            self.chat = chat; self.commandAsk = commandAsk; self.healthSync = healthSync
            self.locationSync = locationSync; self.activitySync = activitySync; self.musicSync = musicSync
            self.push = push; self.inbox = inbox; self.proactive = proactive
            self.notificationsSettings = notificationsSettings; self.reviewCards = reviewCards
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            chat = try c.decode(Bool.self, forKey: .chat)
            commandAsk = try c.decode(Bool.self, forKey: .commandAsk)
            healthSync = try c.decode(Bool.self, forKey: .healthSync)
            locationSync = try c.decode(Bool.self, forKey: .locationSync)
            activitySync = try c.decode(Bool.self, forKey: .activitySync)
            musicSync = try c.decode(Bool.self, forKey: .musicSync)
            push = try c.decode(Bool.self, forKey: .push)
            inbox = try c.decode(Bool.self, forKey: .inbox)
            proactive = try c.decode(Bool.self, forKey: .proactive)
            notificationsSettings = try c.decode(Bool.self, forKey: .notificationsSettings)
            reviewCards = try c.decodeIfPresent(Bool.self, forKey: .reviewCards) ?? false
        }
    }

    struct PushCapability: Codable, Sendable, Equatable {
        let deviceTokenRegistration: Bool
        enum CodingKeys: String, CodingKey {
            case deviceTokenRegistration = "device_token_registration"
        }
    }

    struct FreshnessThresholds: Codable, Sendable, Equatable {
        let healthHours: Int
        let locationHours: Int
        let activityHours: Int
        let musicHours: Int

        enum CodingKeys: String, CodingKey {
            case healthHours = "health_hours"
            case locationHours = "location_hours"
            case activityHours = "activity_hours"
            case musicHours = "music_hours"
        }
    }

    struct AppVersionHints: Codable, Sendable, Equatable {
        let minimum: String?
        let recommended: String?
    }

    /// Conservative offline defaults when bootstrap has never succeeded.
    static let offlineDefaults = MobileBootstrap(
        contractVersion: "0.0.0",
        serverTime: "",
        supportedFeatures: SupportedFeatures(
            chat: true, commandAsk: true,
            healthSync: true, locationSync: true, activitySync: true, musicSync: true,
            push: true, inbox: false, proactive: false, notificationsSettings: false, reviewCards: true
        ),
        push: PushCapability(deviceTokenRegistration: true),
        dataSourceFreshnessThresholds: FreshnessThresholds(
            healthHours: 36, locationHours: 12, activityHours: 24, musicHours: 48
        ),
        appVersion: AppVersionHints(minimum: nil, recommended: nil),
        routeFlags: [:]
    )
}
