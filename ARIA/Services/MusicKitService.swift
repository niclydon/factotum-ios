import Foundation
import MusicKit
import UIKit

/// Bridges iOS MusicKit data to the ARIA server.
///
/// Reads recently played tracks, library songs, playlists, and now-playing
/// status from Apple Music, then POSTs them as a batch to /api/device-music.
@Observable
@MainActor
final class MusicKitService {

    static let shared = MusicKitService()

    // MARK: - State

    var isAuthorized = false
    var isSyncing = false
    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "music_last_sync") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "music_last_sync") }
    }
    var syncError: String?
    var lastSyncRecordCount: Int = 0
    var lastPlaylistSyncCount: Int = 0
    var libraryTrackCount: Int = 0

    /// Whether the user has previously enabled Apple Music in settings.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "music_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "music_enabled") }
    }

    var recentTracks: [RecentTrack] = []
    var nowPlaying: String?

    /// Date of last full library + playlist sync.
    private var lastFullSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "music_last_full_sync") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "music_last_full_sync") }
    }

    /// Progress tracking for full library sync.
    var librarySyncProgress: String?

    // MARK: - Private

    nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Authorization

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        switch status {
        case .authorized:
            isAuthorized = true
            isEnabled = true
            syncError = nil
        case .denied, .restricted:
            syncError = "Apple Music access was denied. Enable it in Settings > Privacy > Media & Apple Music."
            isAuthorized = false
        case .notDetermined:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
    }

    /// Check if we previously got authorization (call on launch).
    ///
    /// When the source is already enabled, treat anything short of an EXPLICIT
    /// `.denied`/`.restricted` as still-connected. `MusicAuthorization.currentStatus`
    /// can read `.notDetermined` on a cold launch after overnight app eviction
    /// before MusicKit re-resolves; flipping `isAuthorized` to false there would
    /// surface the row as "Connect Apple Music" and stall syncs. We keep
    /// `isAuthorized` true and let the next `sync()` re-resolve silently. Only a
    /// genuine denial/restriction drops authorization.
    ///
    /// The genuine first-time-connect flow is untouched: it runs through
    /// `requestAuthorization()` (which sets `isEnabled` only on `.authorized`),
    /// so an un-enabled source still falls through the `guard` and prompts.
    func checkAuthorization() {
        guard isEnabled else { return }
        let status = MusicAuthorization.currentStatus
        if status == .denied || status == .restricted {
            isAuthorized = false
        } else {
            isAuthorized = true
        }
    }

    func disconnect() {
        isEnabled = false
        isAuthorized = false
        lastSyncDate = nil
        lastFullSyncDate = nil
        lastSyncRecordCount = 0
        lastPlaylistSyncCount = 0
        libraryTrackCount = 0
        syncError = nil
        recentTracks = []
        nowPlaying = nil
        UserDefaults.standard.removeObject(forKey: "sync_hash_music")
    }

    // MARK: - Sync

    /// Whether a full library + playlist sync is needed (first time or every 24h).
    private var needsFullSync: Bool {
        guard let lastFull = lastFullSyncDate else { return true }
        return Date().timeIntervalSince(lastFull) > 86400 // 24 hours
    }

    /// Sync music data to the server.
    func sync(force: Bool = false) async {
        guard isAuthorized, !isSyncing else { return }
        isSyncing = true
        syncError = nil
        lastSyncRecordCount = 0
        lastPlaylistSyncCount = 0

        defer { isSyncing = false }

        // Which step threw. MusicKit errors often localize to just "Unknown", so the
        // step plus the concrete error type/code is the only diagnostic a TestFlight
        // build can surface (Settings → Data Sources shows syncError verbatim).
        var stage = "recently played"
        do {
            var records: [MusicRecord] = []
            var displayTracks: [RecentTrack] = []

            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"

            // 1. Always fetch recently played tracks
            // Recently played needs Apple Music developer + user tokens; the library and
            // playlist reads below may not. So a token failure here is recorded but no
            // longer stops the rest of the sync (builds 135–137 lost all music to it).
            var recentItems: [Song] = []
            var recentError: String?
            do {
                var recentRequest = MusicRecentlyPlayedRequest<Song>()
                recentRequest.limit = 25
                recentItems = Array(try await recentRequest.response().items)
            } catch let tokenError as MusicTokenRequestError {
                // Token verdict first: the row is narrow, and the original error is always
                // MusicTokenRequestError.unknown here, so it carries no extra information.
                let diagnosis = await Self.tokenDiagnosis()
                Logger.shared.logMinimal("music", "Recently played: \(diagnosis)", String(reflecting: tokenError))
                // Fallback: the library request needs no Apple Music user token (iOS 27.2 beta 2
                // fails user-token requests), so take the 25 most recently played library songs.
                // Same Song IDs as fetchLibraryTracks(), so Nexus dedups them against the library
                // sync. Catalog-only plays that were never added to the library are not visible.
                stage = "recently played (library fallback)"
                var libraryRecents = MusicLibraryRequest<Song>()
                libraryRecents.sort(by: \.lastPlayedDate, ascending: false)
                libraryRecents.limit = 25
                recentItems = Array(try await libraryRecents.response().items).filter { $0.lastPlayedDate != nil }
                Logger.shared.log("music", "Library fallback supplied \(recentItems.count) recent tracks")
                if recentItems.isEmpty { recentError = "Recently played: \(diagnosis)" }
            }

            for song in recentItems {
                let playedAt = song.lastPlayedDate
                let recentRating: String? = nil  // song.rating removed in iOS 26 MusicKit; track ratings would need MusicLibrarySectionedRequest
                let record = MusicRecord(
                    device_id: "\(deviceId)_\(song.id.rawValue)",
                    title: song.title,
                    artist_name: song.artistName,
                    album_title: song.albumTitle ?? "",
                    genre: song.genreNames.first,
                    played_at: playedAt.map { Self.isoFormatter.string(from: $0) },
                    duration_ms: song.duration.map { Int($0 * 1000) },
                    play_count: song.playCount,
                    source: "apple_music",
                    rating: recentRating
                )
                records.append(record)

                displayTracks.append(RecentTrack(
                    id: song.id.rawValue,
                    title: song.title,
                    artist: song.artistName,
                    album: song.albumTitle ?? "",
                    playedAt: playedAt
                ))
            }

            recentTracks = displayTracks

            // 2. Check now playing
            let player = SystemMusicPlayer.shared
            if let currentEntry = player.queue.currentEntry {
                nowPlaying = currentEntry.title
            } else {
                nowPlaying = nil
            }

            // 3. Full library + playlist sync on first sync or every 24 hours
            var playlists: [PlaylistRecord]?
            if force || needsFullSync {
                stage = "library"
                let libraryTracks = try await fetchLibraryTracks()
                libraryTrackCount = libraryTracks.count
                // Merge library tracks (dedup by device_id)
                let existingIds = Set(records.map(\.device_id))
                for track in libraryTracks where !existingIds.contains(track.device_id) {
                    records.append(track)
                }

                stage = "playlists"
                playlists = try await fetchPlaylists()
                lastFullSyncDate = Date()
            }

            // 4. Sync to server in chunks of 500 tracks
            if !records.isEmpty || playlists != nil {
                if force || SyncHash.hasChanged(records, key: "music") || playlists != nil {
                    stage = "upload"
                    let chunkSize = 500
                    var totalSynced = 0

                    // First chunk includes playlists
                    let firstChunk = Array(records.prefix(chunkSize))
                    let firstRequest = MusicSyncRequest(tracks: firstChunk, playlists: playlists)
                    let firstResponse = try await APIClient.shared.syncMusicData(request: firstRequest)
                    totalSynced += firstResponse.synced
                    lastPlaylistSyncCount = firstResponse.playlists_synced ?? 0

                    // Remaining chunks (tracks only)
                    if records.count > chunkSize {
                        var offset = chunkSize
                        while offset < records.count {
                            let end = min(offset + chunkSize, records.count)
                            let chunk = Array(records[offset..<end])
                            librarySyncProgress = "Uploading: \(offset)/\(records.count) tracks..."
                            let chunkRequest = MusicSyncRequest(tracks: chunk, playlists: nil)
                            let chunkResponse = try await APIClient.shared.syncMusicData(request: chunkRequest)
                            totalSynced += chunkResponse.synced
                            offset = end
                        }
                        librarySyncProgress = nil
                    }

                    lastSyncRecordCount = totalSynced
                    SyncHash.save(records, key: "music")
                }
            }

            lastSyncDate = Date()
            // Library/playlists synced, but surface the recents failure rather than a green row.
            syncError = recentError

            // 5. After sync, pull any new Nexus DJ recommendation and
            //    materialize a "Nexus DJ" Apple Music playlist on-device.
            await syncNexusDjPlaylist()
        } catch {
            let desc = error.localizedDescription
            if desc.contains("developer token") || desc.contains("entitlement") {
                syncError = "Apple Music requires the MusicKit capability to be enabled in the Apple Developer portal for this app."
                isAuthorized = false
                isEnabled = false
            } else {
                syncError = "Sync failed (\(stage)): \(Self.diagnostic(error))"
            }
            Logger.shared.logMinimal("music", "sync failed at \(stage):", String(reflecting: error))
        }
    }

    /// Fetches the developer token and then the user token separately, bypassing the cache,
    /// to say which one MusicKit can't get. A developer-token failure points at the App ID /
    /// MusicKit service / build signature; a user-token failure at the device's Apple Music
    /// account (signed out, subscription, privacy acknowledgement, revoked consent).
    nonisolated static func tokenDiagnosis() async -> String {
        let provider = DefaultMusicTokenProvider()
        let developerToken: String
        do {
            developerToken = try await provider.developerToken(options: .ignoreCache)
        } catch {
            return "developer token FAILED: \(diagnostic(error))"
        }
        do {
            _ = try await provider.userToken(for: developerToken, options: .ignoreCache)
        } catch {
            return "developer token OK; user token FAILED: \(diagnostic(error))"
        }
        return "developer + user tokens both OK on retry"
    }

    /// `localizedDescription` plus the concrete Swift type/case and the bridged NSError
    /// domain/code, e.g. "Unknown [MusicTokenRequestError.unknown · MusicKit.MusicTokenRequestError 0]".
    nonisolated static func diagnostic(_ error: Error) -> String {
        let ns = error as NSError
        return "\(error.localizedDescription) [\(type(of: error)).\(error) · \(ns.domain) \(ns.code)]"
    }

}
