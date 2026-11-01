import CoreLocation
import Foundation
import HealthKit

/// Pure shaping for health-file payloads (testable without HealthKit objects).
enum HealthFilePayloads {
    static func hkId(_ uuid: UUID) -> String { "hk:" + uuid.uuidString.lowercased() }

    static func ecgClassification(raw: Int) -> String {
        switch raw {
        case 1: "Sinus Rhythm"
        case 2: "Atrial Fibrillation"
        case 3: "Inconclusive Low Heart Rate"
        case 4: "Inconclusive High Heart Rate"
        case 5: "Inconclusive Poor Reading"
        case 6: "Inconclusive Other"
        case 100: "Unrecognized"
        default: "Not Set"
        }
    }

    static func symptoms(raw: Int) -> String {
        switch raw {
        case 1: "None"
        case 2: "Present"
        default: "Not Set"
        }
    }

    static func routePoint(lat: Double, lon: Double, ele: Double?, time: Date, speed: Double?, course: Double?, hAcc: Double?, vAcc: Double?) -> HealthFilesRequest.RoutePoint {
        func valid(_ v: Double?) -> Double? { v.flatMap { $0 >= 0 && $0.isFinite ? $0 : nil } }
        return .init(lat: lat, lon: lon, ele: ele.flatMap { $0.isFinite ? $0 : nil }, time: DeviceEventFactory.string(from: time),
                     speed: valid(speed), course: valid(course), hAcc: valid(hAcc), vAcc: valid(vAcc))
    }

    #if DEBUG
    static func runSelfCheck() {
        let u = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        assert(hkId(u) == "hk:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "matches the server's ^hk:<uuid>$")
        assert(ecgClassification(raw: 1) == "Sinus Rhythm" && ecgClassification(raw: 999) == "Not Set")
        let p = routePoint(lat: 37.3, lon: -122.1, ele: 12, time: Date(timeIntervalSince1970: 0), speed: -1, course: -1, hAcc: 5, vAcc: -1)
        assert(p.speed == nil && p.course == nil && p.vAcc == nil && p.hAcc == 5, "CoreLocation's -1 'invalid' becomes nil")
        let body = try! JSONEncoder().encode(HealthFilesRequest(clinical: nil, ecg: nil, routes: [.init(id: hkId(u), routeName: nil, recordedAt: p.time, points: [p])]))
        let json = String(data: body, encoding: .utf8)!
        assert(json.contains("\"routes\"") && !json.contains("\"clinical\""), "nil groups are omitted")
    }
    #endif
}

/// Collects the three file-like HealthKit categories the per-sample stream skips:
/// clinical records (FHIR), ECG waveforms and workout routes, and POSTs them to
/// /api/health-files. Each type has its own anchor, persisted only after Nexus
/// acknowledged the page. Work per run is small and fixed (these objects are heavy).
@Observable
@MainActor
final class HealthFilesSync: BackgroundSyncable {
    static let shared = HealthFilesSync()

    struct Limits {
        let clinical: Int
        let ecg: Int
        let routes: Int
        static let background = Limits(clinical: 20, ecg: 2, routes: 1)
        static let foreground = Limits(clinical: 50, ecg: 5, routes: 3)
    }

    private let logger = Logger.shared
    private let healthStore = HKHealthStore()
    private(set) var isSyncing = false
    var syncError: String?

    /// What the last completed sync actually sent, per kind (3.2.0).
    /// Persisted so the Health Files detail screen can prove the pipe
    /// works even when months pass between new clinical records.
    struct LastResult: Codable, Sendable {
        var at: Date
        var clinical: Int
        var ecg: Int
        var routes: Int
    }

    var lastResult: LastResult? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "health_files_last_result") else { return nil }
            return try? JSONDecoder().decode(LastResult.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "health_files_last_result")
            } else {
                UserDefaults.standard.removeObject(forKey: "health_files_last_result")
            }
        }
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "health_files_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "health_files_enabled") }
    }

    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "health_files_last_sync") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "health_files_last_sync") }
    }

    var sourceKey: String { "health_files" }

    /// True once the user has explicitly disconnected this source, so a later
    /// unrelated HealthKit `authVersion` bump (HealthKitService.checkAuthorization)
    /// does not silently re-enable it. HealthKit does not re-prompt once the OS has
    /// already granted a type, so without this flag the cascade re-authorization
    /// would flip `isEnabled` back to true with no new consent action at all.
    var userDisabled: Bool {
        get { UserDefaults.standard.bool(forKey: "health_files_user_disabled") }
        set { UserDefaults.standard.set(newValue, forKey: "health_files_user_disabled") }
    }

    nonisolated static let clinicalIdentifiers: [HKClinicalTypeIdentifier] = [
        .allergyRecord, .clinicalNoteRecord, .conditionRecord, .coverageRecord, .immunizationRecord,
        .labResultRecord, .medicationRecord, .procedureRecord, .vitalSignRecord,
    ]

    /// Everything `requestAuthorization()` asks for. Static so the DEBUG
    /// `HealthKitService.runAuthorizationSelfCheck()` can validate the exact set.
    static var authorizationTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>(Self.clinicalIdentifiers.compactMap { HKObjectType.clinicalType(forIdentifier: $0) })
        set.insert(HKObjectType.electrocardiogramType())
        set.insert(HKSeriesType.workoutRoute())
        // HealthKit raises NSInvalidArgumentException (an uncatchable launch crash) if
        // workoutRoute is requested without its parent workout type in the same call.
        set.insert(HKObjectType.workoutType())
        return set
    }

    /// Called both from the user's own "Connect" tap in Data Sources and from
    /// HealthKitService's authVersion re-authorization cascade. Reaching this
    /// function at all is what clears `userDisabled` — the cascade caller is
    /// expected to check `userDisabled` itself and skip the call otherwise.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.authorizationTypes)
            isEnabled = true
            userDisabled = false
            syncError = nil
            logger.log("health-files", "Authorized clinical records, ECG and workout routes")
        } catch {
            syncError = "Authorization failed: \(error.localizedDescription)"
            logger.logMinimal("health-files", "Authorization failed:", error.localizedDescription)
        }
    }

    func disconnect() {
        isEnabled = false
        userDisabled = true
        lastSyncDate = nil
        syncError = nil
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("hf_anchor_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func backgroundSync() async {
        await sync(foreground: false)
    }

    func sync(foreground: Bool = true) async {
        guard isEnabled, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let limits = foreground ? Limits.foreground : Limits.background
        var firstError: Error?
        var sent = 0
        var clinicalSent = 0, ecgSent = 0, routesSent = 0

        for identifier in Self.clinicalIdentifiers {
            // Re-checked after every await: `sync()` suspends across each HealthKit
            // fetch + network POST, and `disconnect()` runs synchronously on this
            // same MainActor, so a disconnect tapped mid-sync must stop further
            // per-type drains rather than keep uploading after consent was revoked.
            guard isEnabled else {
                logger.logVerbose("health-files", "Sync stopped: disconnected mid-sync")
                return
            }
            guard let type = HKObjectType.clinicalType(forIdentifier: identifier) else { continue }
            do { let n = try await drainClinical(type, limit: limits.clinical); sent += n; clinicalSent += n } catch { firstError = firstError ?? error }
        }
        guard isEnabled else {
            logger.logVerbose("health-files", "Sync stopped: disconnected mid-sync")
            return
        }
        do { let n = try await drainEcg(limit: limits.ecg); sent += n; ecgSent += n } catch { firstError = firstError ?? error }
        guard isEnabled else {
            logger.logVerbose("health-files", "Sync stopped: disconnected mid-sync")
            return
        }
        do { let n = try await drainRoutes(limit: limits.routes); sent += n; routesSent += n } catch { firstError = firstError ?? error }

        // A disconnect that lands exactly between the last drain and here must not
        // stamp a fresh lastSyncDate for a source the user just turned off.
        guard isEnabled else { return }
        lastSyncDate = Date()
        lastResult = LastResult(at: Date(), clinical: clinicalSent, ecg: ecgSent, routes: routesSent)
        if let firstError {
            syncError = "Sync partial: \(firstError.localizedDescription)"
            logger.logMinimal("health-files", "Sync finished with errors:", firstError.localizedDescription)
        } else {
            syncError = nil
            logger.log("health-files", "Sync complete: \(sent) object(s) accepted")
        }
    }

    // MARK: - Anchors + settle

    /// One fetched page: Sendable DTOs plus the archived next anchor. HealthKit objects
    /// never leave the nonisolated fetchers (same boundary rule as HealthKitService).
    private struct Page<Item: Sendable>: Sendable {
        let items: [Item]
        let anchor: Data?
    }

    private nonisolated static func archive(_ anchor: HKQueryAnchor) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    private nonisolated static func unarchive(_ data: Data?) -> HKQueryAnchor? {
        data.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
    }

    private nonisolated static func lastThirtyDays() -> NSPredicate {
        HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .day, value: -30, to: Date()), end: nil)
    }

    private func saveAnchor(_ data: Data?, key: String) {
        guard let data else { return }
        UserDefaults.standard.set(data, forKey: "hf_anchor_\(key)")
    }

    /// Fetch a page, POST it, and advance the anchor only when Nexus's ack covers every
    /// item. Rejections are logged + reported; retrying a rejected object would loop forever.
    private func drain<Item: Sendable>(
        key: String,
        fetch: (Data?) async throws -> Page<Item>,
        request: ([Item]) -> HealthFilesRequest
    ) async throws -> Int {
        let page = try await fetch(UserDefaults.standard.data(forKey: "hf_anchor_\(key)"))
        guard !page.items.isEmpty else {
            saveAnchor(page.anchor, key: key)
            return 0
        }
        let ack = try await APIClient.shared.syncHealthFiles(request(page.items))
        for r in ack.rejected {
            logger.logMinimal("health-files", "Rejected \(r.id ?? "?"):", r.error)
            Task { await MobileErrorTelemetry.shared.record(path: "/api/health-files", status: 200, failureKind: .http4xx, errorCode: "item_rejected") }
        }
        if ack.accepted.count + ack.duplicate.count + ack.rejected.count >= page.items.count {
            saveAnchor(page.anchor, key: key)
        }
        logger.logVerbose("health-files", "\(key): \(ack.accepted.count) new, \(ack.duplicate.count) duplicate")
        return ack.accepted.count
    }

    private func drainClinical(_ type: HKClinicalType, limit: Int) async throws -> Int {
        try await drain(key: "clinical_\(type.identifier)",
                        fetch: { try await self.clinicalPage(type, anchor: $0, limit: limit) },
                        request: { HealthFilesRequest(clinical: $0, ecg: nil, routes: nil) })
    }

    private func drainEcg(limit: Int) async throws -> Int {
        try await drain(key: "ecg",
                        fetch: { try await self.ecgPage(anchor: $0, limit: limit) },
                        request: { HealthFilesRequest(clinical: nil, ecg: $0, routes: nil) })
    }

    private func drainRoutes(limit: Int) async throws -> Int {
        try await drain(key: "route",
                        fetch: { try await self.routePage(anchor: $0, limit: limit) },
                        request: { HealthFilesRequest(clinical: nil, ecg: nil, routes: $0) })
    }

    // MARK: - Nonisolated fetchers (HealthKit objects stay in here)

    private nonisolated func clinicalPage(_ type: HKClinicalType, anchor: Data?, limit: Int) async throws -> Page<HealthFilesRequest.ClinicalItem> {
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [.clinicalRecord(type: type)], anchor: Self.unarchive(anchor), limit: limit)
        let result = try await descriptor.result(for: healthStore)
        let items: [HealthFilesRequest.ClinicalItem] = result.addedSamples.compactMap { record in
            guard let fhir = record.fhirResource,
                  let json = try? JSONDecoder().decode(EventJSON.self, from: fhir.data) else { return nil }
            return .init(id: HealthFilePayloads.hkId(record.uuid), resourceType: fhir.resourceType.rawValue,
                         effectiveAt: DeviceEventFactory.string(from: record.startDate), fhir: json)
        }
        return Page(items: items, anchor: Self.archive(result.newAnchor))
    }

    private nonisolated func ecgPage(anchor: Data?, limit: Int) async throws -> Page<HealthFilesRequest.EcgItem> {
        let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [.electrocardiogram(Self.lastThirtyDays())], anchor: Self.unarchive(anchor), limit: limit)
        let result = try await descriptor.result(for: healthStore)
        var items: [HealthFilesRequest.EcgItem] = []
        for ecg in result.addedSamples {
            var samples: [Double] = []
            for try await m in HKElectrocardiogramQueryDescriptor(ecg).results(for: healthStore) {
                if let v = m.quantity(for: .appleWatchSimilarToLeadI)?.doubleValue(for: .voltUnit(with: .micro)) { samples.append(v) }
            }
            items.append(.init(
                id: HealthFilePayloads.hkId(ecg.uuid),
                recordedAt: DeviceEventFactory.string(from: ecg.startDate),
                classification: HealthFilePayloads.ecgClassification(raw: ecg.classification.rawValue),
                symptoms: HealthFilePayloads.symptoms(raw: ecg.symptomsStatus.rawValue),
                device: ecg.device?.name,
                sampleRateHz: ecg.samplingFrequency?.doubleValue(for: .hertz()),
                lead: "Lead I",
                samplesUv: samples))
        }
        return Page(items: items, anchor: Self.archive(result.newAnchor))
    }

    private nonisolated func routePage(anchor: Data?, limit: Int) async throws -> Page<HealthFilesRequest.RouteItem> {
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: Self.lastThirtyDays())],
            anchor: Self.unarchive(anchor), limit: limit)
        let result = try await descriptor.result(for: healthStore)
        var items: [HealthFilesRequest.RouteItem] = []
        for case let route as HKWorkoutRoute in result.addedSamples {
            var points: [HealthFilesRequest.RoutePoint] = []
            for try await loc in HKWorkoutRouteQueryDescriptor(route).results(for: healthStore) {
                points.append(HealthFilePayloads.routePoint(
                    lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, ele: loc.altitude, time: loc.timestamp,
                    speed: loc.speed, course: loc.course, hAcc: loc.horizontalAccuracy, vAcc: loc.verticalAccuracy))
                if points.count >= 50_000 { break }
            }
            items.append(.init(id: HealthFilePayloads.hkId(route.uuid), routeName: nil,
                               recordedAt: DeviceEventFactory.string(from: route.startDate), points: points))
        }
        return Page(items: items, anchor: Self.archive(result.newAnchor))
    }
}
