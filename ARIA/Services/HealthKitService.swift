import CryptoKit
import Foundation
import HealthKit
import os

private struct HealthKitObserverCompletion: @unchecked Sendable {
    let handler: HKObserverQueryCompletionHandler

    func call() {
        handler()
    }
}

/// Streams RAW HealthKit samples to the ARIA server.
///
/// Every available HealthKit sample type (all quantity + a comprehensive set of
/// category types + blood-pressure-as-two-quantities + workouts) is read
/// INCREMENTALLY via a per-type `HKAnchoredObjectQuery` with a persisted
/// `HKQueryAnchor`, and each sample is POSTed one-per-row to
/// `/api/health-data` (backend "shape B"). Raw is lossless — curation for
/// usefulness lives DOWNSTREAM in silver/gold, never here.
///
/// Idempotency: the server dedups on the 7-column identity index added in
/// migration 1347 (record_type, source_name, start_date, end_date, value,
/// unit, device). Re-syncing the same window is a no-op, so a lost/reset anchor
/// is safe — it re-pulls the bounded window and re-POSTs, which the index drops.
///
/// The initial pull is BOUNDED to `initialWindowDays` (a start-date predicate)
/// so a first run establishes anchors without pushing millions of all-time
/// samples off the phone. Deep history (2014→) is the one-time `export.xml`
/// import's job, not the app's.
@Observable
@MainActor
final class HealthKitService: BackgroundSyncable {

    static let shared = HealthKitService()

    private let logger = Logger.shared

    // MARK: - State

    var isAuthorized = false
    var isSyncing = false
    var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "healthkit_last_sync") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "healthkit_last_sync") }
    }
    var syncError: String?
    var syncProgress: String?
    var lastSyncRecordCount: Int = 0
    var totalDeviceRecords: Int = 0
    var lastSyncSkipped: Bool = false

    /// Whether the user has previously enabled HealthKit in settings.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "healthkit_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "healthkit_enabled") }
    }

    // MARK: - Tuning constants

    /// Bound the FIRST pull (nil anchor) to the last N days. HKAnchoredObjectQuery
    /// with a nil anchor returns EVERYTHING matching its predicate — without this
    /// bound it would attempt to push years of samples. Applied as a rolling
    /// start-date predicate on every anchored query so an anchor RESET also
    /// re-bounds to ~30 days rather than re-pulling all-time.
    private static let initialWindowDays = 30
    /// Max samples pulled per anchored page; loop on the returned anchor until a
    /// page comes back short (drained). Bounds peak memory on the initial window.
    private static let pageLimit = 5000
    /// Max samples per POST request (bounds request body size + server work).
    private static let postChunkSize = 1000
    /// Wall-clock cap enforced INSIDE a background/observer sweep (iOS gives
    /// BGAppRefresh + HKObserver wakes only ~30s). Enforced directly in the sweep
    /// loops rather than relying on Task cancellation, because the sweep runs in a
    /// coalescing unstructured Task that does not inherit the caller's cancel.
    private static let backgroundSweepBudget: TimeInterval = 20
    /// Hard cap on anchored pages per type per sweep — a safety valve so no
    /// anchor pathology can spin the drain loop forever (200 × pageLimit = 1M).
    private static let maxPagesPerType = 200

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private var observerQueries: [String: HKObserverQuery] = [:]
    private var backgroundSyncTask: Task<Void, Never>?

    /// The full type catalog: quantity types (with a canonical read unit each),
    /// category types, and the workout type. Built once. Blood pressure is
    /// captured as its two underlying quantity types (systolic + diastolic),
    /// which HealthKit stores as independent quantity samples — so no correlation
    /// decoding is needed. `nonisolated(unsafe)`: immutable HealthKit metadata,
    /// safe to read from the nonisolated mapping helpers.
    nonisolated static let catalog = buildCatalog()

    /// All sample types we request read access to and sweep.
    private nonisolated static let allReadTypes: Set<HKSampleType> = catalog.allSampleTypes

    /// `allReadTypes` minus the types HealthKit only grants through per-object authorization.
    /// Passing medication dose events to `requestAuthorization(toShare:read:)` raises
    /// NSInvalidArgumentException ("Authorization to read the following types is disallowed")
    /// — an uncatchable crash that looped every launch of build 135. Dose-event read access
    /// comes from `requestPerObjectReadAuthorization(for: userAnnotatedMedicationType())`.
    nonisolated static let bulkAuthorizationTypes: Set<HKSampleType> =
        allReadTypes.subtracting([HKObjectType.medicationDoseEventType()])

    /// Deterministic sweep order (Set iteration order is unspecified). Combined
    /// with a persisted rotation cursor, this guarantees a time-boxed background
    /// sweep eventually covers every type rather than starving the same tail.
    private nonisolated static let sortedReadTypes: [HKSampleType] =
        allReadTypes.sorted { $0.identifier < $1.identifier }

    /// Curated high-signal subset that gets a live background-delivery observer.
    /// Registering background delivery for all ~100 types would be a battery and
    /// throttling hazard; the FULL delta sweep still runs on foreground and on
    /// the periodic BGAppRefresh, and any observer wake triggers that same full
    /// (anchor-cheap) sweep. Computed (not a stored `let`) because
    /// `HKObjectType.workoutType()` returns covariant `Self`, which cannot be
    /// referenced from a stored-property initializer.
    nonisolated private static var backgroundDeliveryTypes: [HKSampleType] {
        let types: [HKSampleType] = [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.bloodGlucose),
            HKQuantityType(.bloodPressureSystolic),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
        ]
        return types.filter { allReadTypes.contains($0) }
    }

    /// Medication concept key → display name, refreshed at the start of each sweep. Read
    /// from the nonisolated mapper (HealthKit's queue), so it is `nonisolated` and locked.
    nonisolated static let medicationNames = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    /// HKHealthConceptIdentifier has no public string form (only `domain`), so the stable
    /// key is a short SHA-256 of its secure archive. Used in record_type and the name cache.
    nonisolated static func conceptKey(_ id: HKHealthConceptIdentifier) -> String {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: id, requiringSecureCoding: true) else { return "unknown" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Authorization

    /// Bump this when the requested type set changes so existing users get
    /// re-prompted for the (now much larger) read-permission sheet and the new
    /// types get pulled from scratch.
    /// 6 → 7 (2026-08-14, OB-54163): added estimatedWorkoutEffortScore,
    /// workoutEffortScore, appleSleepingBreathingDisturbances to buildCatalog().
    /// 7 → 8 (2026-09-25, ios27 ingest spec): hypertensionEvent (26.2), stateOfMind,
    /// medication dose events (+ per-medication authorization).
    private static let authVersion = 8

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            syncError = "HealthKit is not available on this device"
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: Self.bulkAuthorizationTypes)
            isAuthorized = true
            isEnabled = true
            syncError = nil
            UserDefaults.standard.set(Self.authVersion, forKey: "healthkit_auth_version")
            logger.log("healthkit", "Authorized \(Self.allReadTypes.count) read types")
            registerBackgroundDelivery()
            do {
                try await healthStore.requestPerObjectReadAuthorization(for: HKObjectType.userAnnotatedMedicationType(), predicate: nil)
            } catch {
                logger.logMinimal("healthkit", "Medication authorization failed:", error.localizedDescription)
            }
            // Skip the cascade for a source the user explicitly disconnected — HealthKit
            // does not re-prompt once already OS-granted, so calling this unconditionally
            // would silently re-enable it with no new consent action at all.
            if !HealthFilesSync.shared.userDisabled {
                await HealthFilesSync.shared.requestAuthorization()
            }
        } catch {
            syncError = "Authorization failed: \(error.localizedDescription)"
            isAuthorized = false
        }
    }

    #if DEBUG
    /// Hands each set the app passes to `requestAuthorization(toShare:read:)` to HealthKit's
    /// own validator. `statusForAuthorizationRequest` runs the same type validation with no
    /// UI, so a set HealthKit would reject — a per-object-only type, a series type without
    /// its parent — raises the same uncatchable NSInvalidArgumentException that crash-looped
    /// build 135, at DEBUG launch instead of on a signed-in phone. Apple's rules are applied
    /// by HealthKit itself, so new ones are caught too. Needs the HealthKit entitlements
    /// (clinical types are disallowed without `health-records`), which is why
    /// `scripts/run-debug-selfchecks.sh` ad-hoc signs the simulator build.
    static func runAuthorizationSelfCheck() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[selfcheck] healthkit unavailable, authorization sets not validated")
            return
        }
        let store = HKHealthStore()
        let sets: [(String, Set<HKObjectType>)] = [
            ("HealthKitService", Set<HKObjectType>(bulkAuthorizationTypes)),
            ("HealthFilesSync", HealthFilesSync.authorizationTypes),
        ]
        for (name, types) in sets {
            do {
                _ = try await store.statusForAuthorizationRequest(toShare: [], read: types)
            } catch {
                assertionFailure("[selfcheck] \(name) authorization set failed validation: \(error.localizedDescription)")
            }
        }
    }
    #endif

    /// Check if we previously got authorization (call on launch).
    /// If the requested type set changed (authVersion bumped), re-request and
    /// reset anchors so the newly-granted types backfill their bounded window.
    func checkAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        isAuthorized = isEnabled

        if isEnabled {
            let savedVersion = UserDefaults.standard.integer(forKey: "healthkit_auth_version")
            if savedVersion < Self.authVersion {
                lastSyncDate = nil
                clearAllAnchors()
                UserDefaults.standard.removeObject(forKey: "sync_hash_health")
                Task { await requestAuthorization() }
            } else {
                registerBackgroundDelivery()
            }
        }
    }

    func disconnect() {
        stopBackgroundDelivery()
        isEnabled = false
        isAuthorized = false
        lastSyncDate = nil
        lastSyncRecordCount = 0
        totalDeviceRecords = 0
        syncError = nil
        syncProgress = nil
        clearAllAnchors()
        UserDefaults.standard.removeObject(forKey: "healthkit_auth_version")
        UserDefaults.standard.removeObject(forKey: "sync_hash_health")
    }

    // MARK: - Background delivery

    /// Register HealthKit observer queries so iOS can wake ARIA when new samples
    /// arrive while backgrounded, for the curated high-signal type subset.
    private func registerBackgroundDelivery() {
        guard HKHealthStore.isHealthDataAvailable(), isEnabled else { return }

        for sampleType in Self.backgroundDeliveryTypes {
            let identifier = sampleType.identifier
            if observerQueries[identifier] == nil {
                let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completionHandler, error in
                    if let error {
                        let errorMessage = error.localizedDescription
                        Task { @MainActor [weak self] in
                            self?.logger.logMinimal("healthkit", "Background observer failed for \(identifier):", errorMessage)
                        }
                        completionHandler()
                        return
                    }

                    let completion = HealthKitObserverCompletion(handler: completionHandler)
                    Task { @MainActor [weak self] in
                        await self?.syncFromBackgroundDelivery(trigger: identifier)
                        completion.call()
                    }
                }

                healthStore.execute(query)
                observerQueries[identifier] = query

                // Only enable delivery once per type (this whole block is guarded
                // by `== nil`); `registerBackgroundDelivery` is called on every
                // launch/reactivation, so re-issuing enable each time is wasteful.
                healthStore.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { [weak self] success, error in
                    let errorMessage = error?.localizedDescription
                    Task { @MainActor [weak self] in
                        if success {
                            self?.logger.logVerbose("healthkit", "Enabled background delivery for \(identifier)")
                        } else if let errorMessage {
                            self?.logger.logMinimal("healthkit", "Failed to enable background delivery for \(identifier):", errorMessage)
                        } else {
                            self?.logger.logMinimal("healthkit", "Failed to enable background delivery for \(identifier)")
                        }
                    }
                }
            }
        }
    }

    private func stopBackgroundDelivery() {
        backgroundSyncTask?.cancel()
        backgroundSyncTask = nil

        for query in observerQueries.values {
            healthStore.stop(query)
        }
        observerQueries.removeAll()

        healthStore.disableAllBackgroundDelivery { [weak self] success, error in
            let errorMessage = error?.localizedDescription
            Task { @MainActor [weak self] in
                if success {
                    self?.logger.logVerbose("healthkit", "Disabled background delivery")
                } else if let errorMessage {
                    self?.logger.logMinimal("healthkit", "Failed to disable background delivery:", errorMessage)
                }
            }
        }
    }

    /// Coalesce observer-triggered work: a single in-flight delta sweep absorbs
    /// concurrent triggers rather than launching one sweep per type that fired.
    /// Background/observer sweeps are time-boxed via an internal deadline (iOS
    /// gives these wakes only ~30s), enforced directly in the sweep loops — the
    /// unstructured Task below does NOT inherit the caller's cancellation, so a
    /// wall-clock deadline, not Task cancellation, is what bounds the work.
    private func syncFromBackgroundDelivery(trigger: String) async {
        if let backgroundSyncTask, !backgroundSyncTask.isCancelled {
            logger.logVerbose("healthkit", "Background sync already running; coalescing trigger \(trigger)")
            return
        }

        let deadline = Date().addingTimeInterval(Self.backgroundSweepBudget)
        backgroundSyncTask = Task { [weak self] in
            await self?.runSweep(trigger: trigger, showProgress: false, deadline: deadline)
        }
        await backgroundSyncTask?.value
        backgroundSyncTask = nil
    }

    // MARK: - BackgroundSyncable

    var sourceKey: String { "health" }

    func backgroundSync() async {
        await syncFromBackgroundDelivery(trigger: "bg-refresh")
    }

    // MARK: - Sync

    /// Foreground sync entry point. A full incremental delta sweep across every
    /// type, UNBOUNDED (deadline nil) — a user-initiated sync should finish. `force`
    /// resets all anchors first, so the "Sync Now" button re-pulls the bounded
    /// window and re-POSTs (idempotent — the server dedups it).
    func sync(force: Bool = false) async {
        guard !isSyncing else { return }
        guard isEnabled else { return }
        if force { clearAllAnchors() }
        await runSweep(trigger: force ? "manual-force" : "foreground", showProgress: true, deadline: nil)
    }

    /// The single sweep implementation shared by foreground, background-observer,
    /// and BGAppRefresh paths. Iterates read types in a deterministic order,
    /// draining each type's new samples since its persisted anchor and POSTing
    /// them in bounded chunks.
    ///
    /// `deadline` (background/observer only) is a wall-clock cap enforced between
    /// types, pages, and POST chunks. Background sweeps ROTATE through the type
    /// list via a persisted cursor, so a deadline-truncated sweep resumes where it
    /// left off next wake rather than starving the same tail of types forever.
    private func runSweep(trigger: String, showProgress: Bool, deadline: Date?) async {
        guard !isSyncing else {
            logger.logVerbose("healthkit", "Sync already running; skipping trigger \(trigger)")
            return
        }
        isSyncing = true
        syncError = nil
        syncProgress = nil
        lastSyncRecordCount = 0
        logger.log("healthkit", "Starting sweep (trigger: \(trigger))")

        defer {
            isSyncing = false
            syncProgress = nil
        }

        await refreshMedicationNames()

        // Rolling window lower bound: bounds the FIRST (nil-anchor) pull and any
        // anchor reset to ~30 days. Deliberate tradeoff: it also bounds the
        // steady-state delta, so a sample BACKDATED > 30 days that is written to
        // HealthKit after its type's anchor was established is not captured by the
        // app — that is deep history, which is the one-time export.xml import's
        // job (see class doc). Forward data is never excluded (end: nil). Passed
        // as a Date (Sendable) and turned into the NSPredicate inside the
        // nonisolated fetch, so no non-Sendable predicate crosses the boundary.
        let windowStart = Calendar.current.date(byAdding: .day, value: -Self.initialWindowDays, to: Date())!

        let ordered = Self.sortedReadTypes
        let n = ordered.count
        let rotating = deadline != nil && n > 0
        let startIndex = rotating ? (loadSweepCursor() % n) : 0

        var totalSent = 0
        var totalFetched = 0
        var firstError: Error?
        var processed = 0
        var nextCursor = startIndex

        for offset in 0..<n {
            let idx = (startIndex + offset) % n
            if Task.isCancelled {
                logger.logVerbose("healthkit", "Sweep cancelled after \(processed)/\(n) types")
                nextCursor = idx
                break
            }
            if let deadline, Date() >= deadline {
                logger.logVerbose("healthkit", "Sweep hit budget after \(processed)/\(n) types")
                nextCursor = idx
                break
            }
            let sampleType = ordered[idx]
            do {
                let (sent, fetched) = try await drainType(sampleType, windowStart: windowStart, deadline: deadline)
                totalSent += sent
                totalFetched += fetched
            } catch {
                if firstError == nil { firstError = error }
                logger.logMinimal("healthkit", "Type \(sampleType.identifier) failed:", error.localizedDescription)
            }
            processed += 1
            nextCursor = (idx + 1) % max(n, 1)
            if showProgress {
                syncProgress = "Syncing health: \(processed)/\(n) types..."
            }
        }

        if rotating { saveSweepCursor(nextCursor) } else { saveSweepCursor(0) }

        // If the sweep was cancelled (e.g. disconnect() tearing down state), do
        // NOT clobber the freshly-cleared observable state / anchors.
        if Task.isCancelled { return }

        lastSyncRecordCount = totalSent
        totalDeviceRecords = totalFetched
        lastSyncSkipped = (totalSent == 0 && firstError == nil)
        lastSyncDate = Date()
        if totalSent > 0 { SyncHash.save(totalSent, key: "health") }

        if let firstError {
            syncError = "Sync partial: \(firstError.localizedDescription)"
            logger.logMinimal("healthkit", "Sweep finished with errors: sent \(totalSent), fetched \(totalFetched)")
        } else {
            logger.log("healthkit", "Sweep complete: sent \(totalSent), fetched \(totalFetched)")
        }

        await updateWidgetHealth()
    }

    private func refreshMedicationNames() async {
        do {
            let meds = try await HKUserAnnotatedMedicationQueryDescriptor().result(for: healthStore)
            var names: [String: String] = [:]
            for med in meds {
                names[Self.conceptKey(med.medication.identifier)] = med.nickname ?? med.medication.displayText
            }
            let snapshot = names
            Self.medicationNames.withLock { $0 = snapshot }
            logger.logVerbose("healthkit", "Medication names cached: \(names.count)")
        } catch {
            logger.logVerbose("healthkit", "Medication list unavailable:", error.localizedDescription)
        }
    }

    /// Drain one type: page through its new-since-anchor samples, POST each page
    /// in bounded chunks, and persist the anchor only AFTER a page's POSTs succeed
    /// (so a mid-drain failure resumes from the last durable anchor and never skips
    /// a page). Honors cancellation and the wall-clock deadline between pages and
    /// POST chunks. Returns (sent, fetched).
    private func drainType(_ sampleType: HKSampleType, windowStart: Date, deadline: Date?) async throws -> (sent: Int, fetched: Int) {
        let key = anchorKey(sampleType.identifier)
        var anchorData = UserDefaults.standard.data(forKey: key)
        var sent = 0
        var fetched = 0
        var pages = 0

        while true {
            if Task.isCancelled { break }
            if let deadline, Date() >= deadline { break }
            if pages >= Self.maxPagesPerType {
                logger.logMinimal("healthkit", "Type \(sampleType.identifier) hit page cap; deferring rest to next sweep")
                break
            }
            pages += 1

            let page = try await fetchAnchoredPage(sampleType, anchorData: anchorData, windowStart: windowStart, limit: Self.pageLimit)
            fetched += page.fetchedCount

            for chunk in page.samples.chunked(into: Self.postChunkSize) {
                // Stop before persisting the anchor so an interrupted page is
                // re-fetched next sweep (idempotent server-side). Already-POSTed
                // chunks are counted; re-sending them is a no-op via the index.
                if Task.isCancelled { return (sent, fetched) }
                if let deadline, Date() >= deadline { return (sent, fetched) }
                let response = try await APIClient.shared.syncHealthData(records: chunk)
                sent += response.synced
            }

            // A nil returned anchor on the no-error path is anomalous. Stop
            // draining this type WITHOUT advancing the cursor (retry from the
            // current anchor next sweep) rather than resetting to a zero anchor,
            // which would re-pull the same page in a loop.
            guard let newAnchorData = page.newAnchorData else {
                logger.logMinimal("healthkit", "Nil anchor returned for \(sampleType.identifier); stopping drain")
                break
            }
            // Do not persist across a cancellation (e.g. disconnect clearing anchors).
            if Task.isCancelled { break }
            UserDefaults.standard.set(newAnchorData, forKey: key)
            anchorData = newAnchorData

            if page.fetchedCount < Self.pageLimit { break }
        }

        return (sent, fetched)
    }

    /// Run a one-shot HKAnchoredObjectQuery (no update handler → completes after
    /// the results callback) and bridge it into async/await. The samples are
    /// mapped to `RawHealthSample` INSIDE the completion (HealthKit's private
    /// queue) so no non-Sendable `HKSample`/`HKQueryAnchor` crosses back to the
    /// MainActor and the CPU-bound mapping never runs on the main thread.
    private nonisolated func fetchAnchoredPage(
        _ sampleType: HKSampleType,
        anchorData: Data?,
        windowStart: Date,
        limit: Int
    ) async throws -> AnchoredPage {
        // Build the predicate HERE (nonisolated) from the Sendable Date so no
        // non-Sendable NSPredicate is sent across the isolation boundary.
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: nil, options: [])
        let anchor: HKQueryAnchor? = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: predicate,
                anchor: anchor,
                limit: limit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let hkSamples = samples ?? []
                let mapped = hkSamples.compactMap { Self.mapToRaw($0, sampleType: sampleType) }
                let newData: Data? = newAnchor.flatMap {
                    try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
                }
                continuation.resume(returning: AnchoredPage(
                    samples: mapped,
                    fetchedCount: hkSamples.count,
                    newAnchorData: newData
                ))
            }
            healthStore.execute(query)
        }
    }

    private struct AnchoredPage: Sendable {
        let samples: [RawHealthSample]
        /// Raw HKSample count for this page (drives pagination + device-record UI).
        let fetchedCount: Int
        /// Archived HKQueryAnchor (Sendable); nil only on an anomalous no-error page.
        let newAnchorData: Data?
    }

    // MARK: - Anchor + cursor persistence

    private func anchorKey(_ identifier: String) -> String { "hk_anchor_\(identifier)" }

    private func clearAllAnchors() {
        for sampleType in Self.allReadTypes {
            UserDefaults.standard.removeObject(forKey: anchorKey(sampleType.identifier))
        }
        UserDefaults.standard.removeObject(forKey: "hk_sweep_cursor")
    }

    /// Round-robin start index for the next background sweep (see `runSweep`).
    private func loadSweepCursor() -> Int { UserDefaults.standard.integer(forKey: "hk_sweep_cursor") }
    private func saveSweepCursor(_ index: Int) { UserDefaults.standard.set(index, forKey: "hk_sweep_cursor") }

    // MARK: - Widget summary (today)

    private func updateWidgetHealth() async {
        let dayStart = Calendar.current.startOfDay(for: Date())
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

        let steps = await querySum(.stepCount, unit: .count(), start: dayStart, end: dayEnd)
        let energy = await querySum(.activeEnergyBurned, unit: .kilocalorie(), start: dayStart, end: dayEnd)
        let hr = await queryMostRecent(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: dayStart, end: dayEnd)

        let sleepStart = Calendar.current.date(byAdding: .hour, value: -12, to: dayStart)!
        let sleepMinutes = await querySleepMinutes(start: sleepStart, end: dayEnd)
        let sleepHours = sleepMinutes / 60.0

        let distance = await querySum(.distanceWalkingRunning, unit: .mile(), start: dayStart, end: dayEnd)

        WidgetDataService.updateHealthSummary(
            steps: steps.map { Int($0) },
            sleepHours: sleepHours > 0 ? sleepHours : nil,
            heartRate: hr.map { Int($0) },
            activeCalories: energy.map { Int($0) },
            distance: distance.map { round($0 * 10) / 10 }
        )
    }

    private nonisolated func querySum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        let quantityType = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private nonisolated func queryMostRecent(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Double? {
        let quantityType = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    /// Total asleep minutes for the widget (any "asleep*" stage).
    private nonisolated func querySleepMinutes(start: Date, end: Date) async -> Double {
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: 0)
                    return
                }
                var minutes: Double = 0
                for sample in samples {
                    switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                    case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
                        minutes += sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    default:
                        break
                    }
                }
                continuation.resume(returning: minutes)
            }
            healthStore.execute(query)
        }
    }


}

// MARK: - Array chunking

extension Array {
    /// Split into consecutive sub-arrays of at most `size` elements.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
