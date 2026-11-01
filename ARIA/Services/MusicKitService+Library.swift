import Foundation
import MusicKit
import UIKit

/// Library and playlist fetching, split from MusicKitService.swift in
/// the Factotum 4.0 foundation pass. Sync orchestration stays in the
/// core file; these are the two paginated MusicKit reads it drives.
extension MusicKitService {
    // MARK: - Library Fetch


    /// Fetch ALL library songs by paginating through the entire library.
    /// MusicKit returns ~100 items per page; we iterate until exhausted.
    func fetchLibraryTracks() async throws -> [MusicRecord] {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        var allRecords: [MusicRecord] = []

        // MusicLibraryRequest doesn't support cursor-based pagination directly.
        // We fetch with a large limit and use offset-based pagination.
        let batchSize = 200
        var offset = 0

        while true {
            var request = MusicLibraryRequest<Song>()
            request.sort(by: \.lastPlayedDate, ascending: false)
            request.limit = batchSize
            request.offset = offset
            let response = try await request.response()

            if response.items.isEmpty { break }

            for song in response.items {
                let rating: String? = nil  // song.rating removed in iOS 26 MusicKit; track ratings would need MusicLibrarySectionedRequest
                allRecords.append(MusicRecord(
                    device_id: "\(deviceId)_\(song.id.rawValue)",
                    title: song.title,
                    artist_name: song.artistName,
                    album_title: song.albumTitle ?? "",
                    genre: song.genreNames.first,
                    played_at: song.lastPlayedDate.map { Self.isoFormatter.string(from: $0) },
                    duration_ms: song.duration.map { Int($0 * 1000) },
                    play_count: song.playCount,
                    source: "apple_music",
                    rating: rating
                ))
            }
            librarySyncProgress = "Scanning library: \(allRecords.count) tracks..."

            // If we got fewer than requested, we've reached the end
            if response.items.count < batchSize { break }
            offset += batchSize
        }

        librarySyncProgress = nil
        return allRecords
    }

    // MARK: - Playlist Fetch

    /// Fetch user's playlists with their tracks.
    func fetchPlaylists() async throws -> [PlaylistRecord] {
        let request = MusicLibraryRequest<Playlist>()
        let response = try await request.response()
        var playlists: [PlaylistRecord] = []
        for playlist in response.items.prefix(50) {
            let detailed = try await playlist.with(.tracks)
            var tracks: [PlaylistTrackRecord] = []
            if let entries = detailed.tracks {
                for (index, entry) in entries.enumerated() {
                    tracks.append(PlaylistTrackRecord(
                        device_id: entry.id.rawValue,
                        title: entry.title,
                        artist_name: entry.artistName,
                        album_title: "",
                        track_order: index
                    ))
                }
            }
            playlists.append(PlaylistRecord(
                device_id: playlist.id.rawValue,
                name: playlist.name,
                description: playlist.standardDescription,
                track_count: tracks.count,
                is_user_created: true, // MusicLibraryRequest only returns user's own playlists
                tracks: tracks
            ))
        }
        return playlists
    }

}
