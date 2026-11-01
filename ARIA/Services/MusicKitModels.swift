import Foundation

/// Music sync and Nexus DJ model types, split from MusicKitService.swift
/// in the Factotum 4.0 foundation pass.

// MARK: - Supporting Types

struct RecentTrack: Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let playedAt: Date?
}

// MARK: - Nexus DJ Recommendations

struct MusicRecommendation: Codable, Sendable {
    let id: String
    let created_at: String
    let state: BehavioralStateDTO
    let steer_direction: String?
    let track_count: Int
    let ios_playlist_created: Bool
    let tracks: [RecommendationTrack]
}

struct BehavioralStateDTO: Codable, Sendable {
    let energy: String
    let cognitive: String
    let emotional: String
    let social: String
}

struct RecommendationTrack: Codable, Sendable {
    let track_order: Int
    let title: String
    let artist_name: String
    let album_title: String?
    let duration_ms: Int?
}

struct MusicRecommendationConfirmRequest: Codable, Sendable {
    let apple_music_url: String?
}

struct MusicRecommendationConfirmResponse: Codable, Sendable {
    let ok: Bool
    let id: String
}

struct MusicRecord: Codable, Sendable {
    let device_id: String
    let title: String
    let artist_name: String
    let album_title: String
    let genre: String?
    let played_at: String?
    let duration_ms: Int?
    let play_count: Int?
    let source: String
    let rating: String?
}

struct PlaylistRecord: Codable, Sendable {
    let device_id: String
    let name: String
    let description: String?
    let track_count: Int
    let is_user_created: Bool
    let tracks: [PlaylistTrackRecord]
}

struct PlaylistTrackRecord: Codable, Sendable {
    let device_id: String
    let title: String
    let artist_name: String
    let album_title: String
    let track_order: Int
}

struct MusicSyncRequest: Codable, Sendable {
    let tracks: [MusicRecord]
    let playlists: [PlaylistRecord]?
}

struct MusicSyncResponse: Codable, Sendable {
    let synced: Int
    let playlists_synced: Int?
}
