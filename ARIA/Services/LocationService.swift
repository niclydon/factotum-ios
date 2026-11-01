import Foundation
import CoreLocation
import MapKit

/// Bridges iOS location to the ARIA server.
///
/// Gets the current location on demand (not continuous tracking)
/// and POSTs it with reverse-geocoded place info to /api/device-location.
///
/// Also monitors:
/// - CLVisit (OS-detected venue arrivals/departures)
/// - Significant location changes (cell-tower-level, very low battery cost)
@Observable
@MainActor
final class LocationService: NSObject {

    private let logger = Logger.shared

    // MARK: - State

    var isAuthorized = false
    var isSyncing = false
    var syncError: String?
    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "location_last_sync") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "location_last_sync") }
    }
    var lastLocationDescription: String?

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "location_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "location_enabled") }
    }

    /// Whether background monitoring (visits + significant changes) is active.
    private(set) var isBackgroundMonitoringActive = false

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    private nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Init

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Authorization

    func requestAuthorization() {
        let status = locationManager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            // Already have OS permission -- just re-enable
            isAuthorized = true
            isEnabled = true
            syncError = nil
            startBackgroundMonitoring()
        } else {
            // Need to ask the OS
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func checkAuthorization() {
        let status = locationManager.authorizationStatus
        isAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        // Only clear the persisted enable on an EXPLICIT denial/restriction.
        // A transient `.notDetermined` blip on a cold launch (after overnight
        // app eviction the OS hasn't re-resolved permission yet) must NOT
        // wipe `location_enabled` or tear down background monitoring.
        if isEnabled && (status == .denied || status == .restricted) {
            isEnabled = false
            stopBackgroundMonitoring()
        }
    }

    // MARK: - Background Monitoring

    /// Starts visit monitoring and significant-change location monitoring.
    /// Both run in the background with minimal battery cost.
    func startBackgroundMonitoring() {
        guard isAuthorized, isEnabled, !isBackgroundMonitoringActive else { return }

        // CLVisit -- OS automatically detects venue arrivals/departures.
        // Requires Always authorization ideally, but works with WhenInUse too
        // (just won't fire from background as often).
        locationManager.startMonitoringVisits()
        logger.logVerbose("location", "Started visit monitoring")

        // Significant-change monitoring -- fires didUpdateLocations when the
        // user moves between cell towers. Extremely low battery cost.
        locationManager.startMonitoringSignificantLocationChanges()
        logger.logVerbose("location", "Started significant-change monitoring")

        isBackgroundMonitoringActive = true
        logger.log("location", "Background monitoring active (visits + significant changes)")
    }

    /// Stops visit monitoring and significant-change monitoring.
    func stopBackgroundMonitoring() {
        guard isBackgroundMonitoringActive else { return }

        locationManager.stopMonitoringVisits()
        locationManager.stopMonitoringSignificantLocationChanges()
        isBackgroundMonitoringActive = false
        logger.log("location", "Background monitoring stopped")
    }

    // MARK: - Legacy geofence cleanup

    /// Geofencing was retired 2026-09-25 — `/api/geofences*` has no Nexus handler.
    /// OS region monitoring persists across launches and app updates, so a device
    /// that ever enabled geofencing can still hold `aria_geofence_*` regions that
    /// wake the app on every crossing. Monitored regions are shared by all of the
    /// app's location managers, so they can be stopped from here. Idempotent.
    func retireLegacyGeofenceRegions() {
        let legacy = locationManager.monitoredRegions.filter { $0.identifier.hasPrefix("aria_geofence_") }
        for region in legacy {
            locationManager.stopMonitoring(for: region)
        }
        UserDefaults.standard.removeObject(forKey: "geofence_enabled")
        if !legacy.isEmpty {
            logger.log("location", "Stopped \(legacy.count) legacy geofence region(s)")
        }
    }

    // MARK: - Sync

    func disconnect() {
        stopBackgroundMonitoring()
        isEnabled = false
        isAuthorized = false
        lastSyncDate = nil
        lastLocationDescription = nil
        syncError = nil
    }

    func sync() async {
        guard !isSyncing else { return }

        // A cold launch can transiently report .notDetermined before the OS
        // re-resolves permission. requestLocation() would just burn its 12s
        // deadline and surface a misleading "timed out" banner — skip instead.
        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            logger.logVerbose("location", "Sync skipped — authorization not resolved yet")
            return
        }

        isSyncing = true
        syncError = nil

        defer { isSyncing = false }

        do {
            // requestLocation() now self-imposes a 12s deadline (see below)
            // — without that, CLLocationManager has been seen to silently
            // never call either delegate, leaving the UI on "Syncing..."
            // forever (TestFlight build 105 incident, 2026-04-26).
            guard let location = await requestLocation() else {
                syncError = "Could not determine location (timed out)"
                return
            }

            // Reverse geocode for place name (MapKit; CLGeocoder is
            // deprecated in iOS 26). Geocoding has no client-side timeout
            // and stalls under rate limits / weak network — same
            // incident's secondary suspect. Bound it at 5s and just skip
            // the place-name fields if it's slow. The lat/lon record is
            // the load-bearing payload; placeName/locality/etc. are
            // nice-to-have decorations.
            //
            // Note: the MKReverseGeocodingRequest is constructed fresh
            // inside the addTask closure, so no shared geocoder state
            // crosses actors. CLLocation is Sendable as of iOS 17.
            let placemark: CLPlacemark? = await withTaskGroup(of: CLPlacemark?.self) { group in
                group.addTask {
                    // Deliberate compat read: MKAddress exposes no country
                    // field, and the record's country comes from the placemark.
                    // Acquisition is modern (MKReverseGeocodingRequest); only
                    // the field read stays on the deprecated member.
                    guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
                    let items = try? await request.mapItems
                    return items?.first?.placemark as CLPlacemark?
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    return nil
                }
                let result = await group.next() ?? nil
                group.cancelAll()
                return result
            }

            // Extract speed/course if available (CLLocation provides these)
            let speed = location.speed >= 0 ? location.speed : nil
            let course = location.course >= 0 ? location.course : nil

            let record = LocationRecord(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy,
                timestamp: Self.iso8601Formatter.string(from: location.timestamp),
                placeName: placemark?.name,
                locality: placemark?.locality,
                administrativeArea: placemark?.administrativeArea,
                country: placemark?.country,
                speed: speed,
                course: course
            )

            let response = try await APIClient.shared.syncLocation(location: record)
            logger.logVerbose("location", "Location update: \(record.latitude), \(record.longitude)" +
                (speed != nil ? " speed=\(String(format: "%.1f", speed!))m/s" : "") +
                (course != nil ? " course=\(String(format: "%.0f", course!))deg" : ""))
            if response.saved {
                lastSyncDate = Date()
                let locationDesc = [placemark?.locality, placemark?.administrativeArea]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                lastLocationDescription = locationDesc

                // Update activity widget with location
                WidgetDataService.updateActivityStatus(
                    activity: "Location updated",
                    location: locationDesc.isEmpty ? nil : locationDesc
                )
            }

            // Ensure background monitoring is running after a successful sync
            startBackgroundMonitoring()
        } catch {
            logger.logMinimal("location", "Sync failed:", error.localizedDescription)
            syncError = "Sync failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Visit Sync

    /// Syncs a CLVisit to the server.
    private func syncVisit(arrival: Date, departure: Date?, lat: Double, lon: Double, accuracy: Double) async {
        let record = VisitRecord(
            arrivalDate: Self.iso8601Formatter.string(from: arrival),
            departureDate: departure.map { Self.iso8601Formatter.string(from: $0) },
            latitude: lat,
            longitude: lon,
            accuracy: accuracy >= 0 ? accuracy : nil
        )

        do {
            let response = try await APIClient.shared.syncVisit(visit: record)
            logger.logVerbose("location", "Visit synced: \(lat), \(lon) " +
                "arrival=\(record.arrivalDate) " +
                "departure=\(record.departureDate ?? "ongoing") " +
                "saved=\(response.saved)")
            // A successful background sync proves the pipeline is healthy —
            // heal any stale error banner left by an earlier manual sync.
            syncError = nil
        } catch {
            logger.logMinimal("location", "Visit sync failed:", error.localizedDescription)
        }
    }

    // MARK: - Significant-Change Location Sync

    /// Syncs a location update from significant-change monitoring.
    /// Does not use the continuation-based requestLocation flow.
    private func syncSignificantChangeLocation(_ location: CLLocation) async {
        // Same 5s geocode bound as sync() — geocoding has no client-side
        // timeout and stalls under rate limits / weak network. Fresh
        // MKReverseGeocodingRequest per call, constructed in the closure.
        let placemark: CLPlacemark? = await withTaskGroup(of: CLPlacemark?.self) { group in
            group.addTask {
                // Deliberate compat read: MKAddress exposes no country
                // field, and the record's country comes from the placemark.
                // Acquisition is modern (MKReverseGeocodingRequest); only
                // the field read stays on the deprecated member.
                guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
                let items = try? await request.mapItems
                return items?.first?.placemark as CLPlacemark?
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }

        let speed = location.speed >= 0 ? location.speed : nil
        let course = location.course >= 0 ? location.course : nil

        let record = LocationRecord(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            timestamp: Self.iso8601Formatter.string(from: location.timestamp),
            placeName: placemark?.name,
            locality: placemark?.locality,
            administrativeArea: placemark?.administrativeArea,
            country: placemark?.country,
            speed: speed,
            course: course
        )

        do {
            let response = try await APIClient.shared.syncLocation(location: record)
            if response.saved {
                lastSyncDate = Date()
                syncError = nil
                let locationDesc = [placemark?.locality, placemark?.administrativeArea]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                lastLocationDescription = locationDesc
                logger.logVerbose("location", "Significant-change update: \(locationDesc.isEmpty ? "\(record.latitude), \(record.longitude)" : locationDesc)")
            }
        } catch {
            logger.logMinimal("location", "Significant-change sync failed:", error.localizedDescription)
        }
    }

    // MARK: - Core Location

    private func requestLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
            // Belt-and-suspenders timeout. CLLocationManager's documented
            // ~10s internal timeout has been observed to silently no-op,
            // leaving the continuation hanging. After 12s, resume nil
            // ourselves; whichever path (delegate or timer) wins, the
            // continuation gets a single resume because the other path
            // sees locationContinuation == nil and skips.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard let self, let pending = self.locationContinuation else { return }
                self.locationContinuation = nil
                pending.resume(returning: nil)
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // If there's a pending continuation (from requestLocation()), fulfill it
        if let continuation = locationContinuation {
            continuation.resume(returning: locations.last)
            locationContinuation = nil
            return
        }

        // Otherwise this is from significant-change monitoring -- sync each location
        guard let location = locations.last else { return }
        logger.logDebug("location", "Significant-change didUpdateLocations: " +
            "\(location.coordinate.latitude), \(location.coordinate.longitude) " +
            "speed=\(location.speed) course=\(location.course)")
        Task {
            await syncSignificantChangeLocation(location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.logDebug("location", "didFailWithError:", error.localizedDescription)
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let arrival = visit.arrivalDate
        let departure = visit.departureDate == Date.distantFuture ? nil : visit.departureDate
        let lat = visit.coordinate.latitude
        let lon = visit.coordinate.longitude
        let accuracy = visit.horizontalAccuracy

        logger.log("location", "CLVisit detected: \(lat), \(lon) " +
            "arrival=\(Self.iso8601Formatter.string(from: arrival)) " +
            "departure=\(departure.map { Self.iso8601Formatter.string(from: $0) } ?? "ongoing")")

        Task {
            await syncVisit(arrival: arrival, departure: departure, lat: lat, lon: lon, accuracy: accuracy)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        isAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        if isAuthorized && !isEnabled {
            isEnabled = true
            syncError = nil
        }
        if isAuthorized && isEnabled {
            startBackgroundMonitoring()
        } else {
            stopBackgroundMonitoring()
        }
    }
}
