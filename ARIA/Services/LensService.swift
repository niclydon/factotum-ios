import Foundation
import Photos
import Vision
import MapKit
import FoundationModels
import SwiftData
import BackgroundTasks
import UIKit
import AVFoundation
import Speech

/// Factotum Lens (4.0 W9): on-device photo/video intelligence.
///
/// Incrementally analyzes NEW library assets with Vision (classification,
/// OCR, face count) and Foundation Models (caption, tags, video summary),
/// stores the derived records in its own SwiftData store, and uploads ONLY
/// the derived records to Nexus (POST /api/mobile/photo-intelligence,
/// OB-66559). Originals never leave the device. Heavy runs are budgeted:
/// capped per run, and the background lane is a BGProcessingTask that
/// requires external power.
@Observable
@MainActor
final class LensService: NSObject {
    static let shared = LensService()
    nonisolated static let processingTaskIdentifier = "com.example.factotum.lens"
    nonisolated static let visionVersion = "vision-1"
    nonisolated static let fmVersion = "fm-1"
    nonisolated static let perRunCap = 60

    private(set) var authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private(set) var analyzedCount = 0
    private(set) var pendingUploadCount = 0
    private(set) var termsIndexedCount = 0
    private(set) var termsPendingCount = 0
    private(set) var metadataEnrichedCount = 0
    private(set) var metadataPendingCount = 0
    private(set) var isEnriching = false
    private var enrichStopRequested = false

    /// Ask a running metadata enrichment pass to stop at its
    /// next asset. Everything already posted is durable.
    func stopMetadataEnrichment() { enrichStopRequested = true }
    private(set) var isBackfilling = false
    private(set) var backfillExamined = 0
    private(set) var backfillAnalyzed = 0
    private(set) var backfillWindowTotal = 0
    private var backfillStopRequested = false

    /// Ask a running backfill (either mode) to stop at its next
    /// checkpoint. Everything already checkpointed is durable.
    func stopTextIndexBackfill() { backfillStopRequested = true }
    private(set) var textIndexBackfillDone = UserDefaults.standard.bool(forKey: "textindex.backfillDone")
    private(set) var lastRunAt: Date?

    /// The most recent analysis, for the Settings -> Lens "Latest
    /// analysis" card (4.0.7): a proof-of-work surface showing the
    /// actual image and what Lens concluded from it. Published at
    /// most every 0.75s during a run so the card stays readable
    /// when a sweep moves fast; a run's final analysis is always
    /// force-published at run end.
    struct LastAnalyzed: Sendable {
        let thumbnailJPEG: Data?
        let caption: String
        let tags: [String]
        let place: String?
        let faceCount: Int
        let mediaType: String
        let capturedAt: Date
        let analyzedAt: Date
    }
    private(set) var lastAnalyzed: LastAnalyzed?
    private var lastAnalyzedPublishedAt = Date.distantPast

    func noteAnalyzed(_ analysis: LensAnalysis, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastAnalyzedPublishedAt) >= 0.75 else { return }
        lastAnalyzedPublishedAt = now
        lastAnalyzed = LastAnalyzed(
            thumbnailJPEG: analysis.thumbnailJPEG,
            caption: analysis.caption, tags: analysis.tags,
            place: analysis.place, faceCount: analysis.faceCount,
            mediaType: analysis.mediaType, capturedAt: analysis.capturedAt,
            analyzedAt: now)
    }
    private(set) var isProcessing = false

    private let logger = Logger.shared
    private var observerRegistered = false

    private let container: ModelContainer = {
        // Lens MUST use a named configuration: the default store belongs
        // to the chat container, and two schemas over one default store
        // made this container fail on device in 4.0.0. The in-memory
        // fallback then silently discarded every record and the
        // analysis watermark at app termination, so counts reset and
        // assets re-analyzed on every launch. A named config gets its
        // own Lens.store file.
        let schema = Schema([PhotoDerivedRecord.self, PhotoTermsOutboxRecord.self])
        let config = ModelConfiguration("Lens", schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // A corrupt Lens store must never take the app down with it;
            // fall back to an in-memory store (records re-derive later),
            // but say so loudly: this fallback masked the 4.0.0 defect.
            Logger.shared.log("lens", "PERSISTENT STORE FAILED, in-memory fallback: \(error)")
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memory])
        }
    }()

    private override init() {
        super.init()
        lastRunAt = UserDefaults.standard.object(forKey: "lens.lastRunAt") as? Date
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    // MARK: - Authorization + lifecycle

    func checkAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if isAuthorized {
            startObserving()
            refreshCounts()
        }
    }

    /// The one in-app ask: full library access, value stated in the
    /// Settings Lens screen and in the system prompt copy (Info.plist).
    func requestAuthorization() async {
        authorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        checkAuthorization()
    }

    func startObserving() {
        guard isAuthorized, !observerRegistered else { return }
        PHPhotoLibrary.shared().register(self)
        observerRegistered = true
    }

    func stopObserving() {
        guard observerRegistered else { return }
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        observerRegistered = false
    }

    // MARK: - Background processing lane (charging)

    nonisolated static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingTaskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            let box = LensTaskBox(value: processingTask)
            Task { @MainActor in
                LensService.shared.handle(task: box.value)
            }
        }
    }

    func scheduleProcessing() {
        guard isAuthorized else { return }
        let request = BGProcessingTaskRequest(identifier: Self.processingTaskIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        BGTaskScheduler.shared.submitTaskRequest(request) { error in
            if let error {
                self.logger.logMinimal("lens", "Failed to schedule processing:", error.localizedDescription)
            }
        }
    }

    private func handle(task: BGProcessingTask) {
        scheduleProcessing()
        let work = Task { @MainActor in
            await processNewAssets(trigger: "bg-processing")
            await runTextIndexBackfill(trigger: "bg-processing")
            await runReanalyzeSweep(trigger: "bg-processing")
            await runMetadataEnrichment(trigger: "bg-processing")
        }
        task.expirationHandler = { work.cancel() }
        Task { @MainActor in
            await work.value
            task.setTaskCompleted(success: !work.isCancelled)
        }
    }

    // MARK: - Processing

    /// Analyze assets created after the newest stored record, oldest first,
    /// capped per run; then flush the upload outbox.
    func processNewAssets(trigger: String) async {
        guard isAuthorized, !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let context = container.mainContext
        let newest = (try? context.fetch(FetchDescriptor<PhotoDerivedRecord>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])))?.first?.capturedAt

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        if let newest {
            options.predicate = NSPredicate(format: "creationDate > %@", newest as NSDate)
        }
        let fetched = PHAsset.fetchAssets(with: options)
        var ids: [String] = []
        fetched.enumerateObjects { asset, _, stop in
            ids.append(asset.localIdentifier)
            if ids.count >= Self.perRunCap { stop.pointee = true }
        }

        let progressActivity = ids.count >= 10 ? LiveActivityService() : nil
        progressActivity?.beginProgress(
            kind: "lens", label: "Lens",
            detail: "Analyzing \(ids.count) photos and videos\u{2026}")
        var inserted = 0
        var lastAnalysis: LensAnalysis? = nil
        for id in ids {
            if Task.isCancelled { break }
            guard let analysis = await Self.analyzeAsset(localId: id) else { continue }
            let record = PhotoDerivedRecord(
                assetLocalId: id, capturedAt: analysis.capturedAt,
                mediaType: analysis.mediaType, caption: analysis.caption,
                tags: analysis.tags, ocrText: analysis.ocrText,
                faceCount: analysis.faceCount, place: analysis.place,
                durationS: analysis.durationS, transcript: analysis.transcript,
                summary: analysis.summary, derivedAt: Date(),
                visionVersion: Self.visionVersion, fmVersion: Self.fmVersion)
            context.insert(record)
            record.originalFilename = analysis.originalFilename
            record.pixelWidth = analysis.pixelWidth
            record.pixelHeight = analysis.pixelHeight
            record.metadataEnrichedAt = Date()
            enqueueTerms(for: record, fullOcrText: analysis.fullOcrText,
                         transcript: analysis.transcript, replace: false, context: context)
            inserted += 1
            lastAnalysis = analysis
            noteAnalyzed(analysis)
            await progressActivity?.updateProgress(
                kind: "lens",
                detail: "Analyzed \(inserted) of \(ids.count)",
                progress: Double(inserted) / Double(ids.count))
        }
        if let lastAnalysis { noteAnalyzed(lastAnalysis, force: true) }
        await progressActivity?.endProgress(kind: "lens", detail: "\(inserted) analyzed")
        if inserted > 0 {
            try? context.save()
            logger.logMinimal("lens", "Analyzed \(inserted) assets (\(trigger))")
        }
        lastRunAt = Date()
        UserDefaults.standard.set(lastRunAt, forKey: "lens.lastRunAt")
        AIActivityLog.record(
            kind: "lens.analyze",
            detail: "Analyzed \(inserted) of \(ids.count) new assets (\(trigger))",
            assets: inserted, leftDevice: 0)
        refreshCounts()
        await flushOutbox()
        await flushTermsOutbox()
    }

    /// Upload every unposted record in batches of at most 100.
    func flushOutbox() async {
        let context = container.mainContext
        let pending = (try? context.fetch(FetchDescriptor<PhotoDerivedRecord>(
            predicate: #Predicate { $0.postedAt == nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .forward)]))) ?? []
        for chunk in pending.chunked(into: 100) {
            do {
                _ = try await APIClient.shared.postPhotoIntelligence(
                    PhotoIntelligenceBatchRequest(records: chunk.map { $0.wireRecord() }))
                let now = Date()
                for record in chunk { record.postedAt = now }
                AIActivityLog.record(
                    kind: "lens.upload",
                    detail: "Uploaded \(chunk.count) derived photo records (text only; originals stayed on device)",
                    assets: chunk.count, leftDevice: chunk.count)
                try? context.save()
            } catch {
                logger.logMinimal("lens", "Upload failed; outbox retained:", error.localizedDescription)
                break
            }
        }
        refreshCounts()
    }

    func refreshCounts() {
        let context = container.mainContext
        analyzedCount = (try? context.fetchCount(FetchDescriptor<PhotoDerivedRecord>())) ?? 0
        pendingUploadCount = (try? context.fetchCount(FetchDescriptor<PhotoDerivedRecord>(
            predicate: #Predicate { $0.postedAt == nil }))) ?? 0
        termsIndexedCount = (try? context.fetchCount(FetchDescriptor<PhotoDerivedRecord>(
            predicate: #Predicate { $0.termsExportedAt != nil }))) ?? 0
        termsPendingCount = (try? context.fetchCount(FetchDescriptor<PhotoTermsOutboxRecord>())) ?? 0
        metadataEnrichedCount = (try? context.fetchCount(FetchDescriptor<PhotoDerivedRecord>(
            predicate: #Predicate { $0.metadataEnrichedAt != nil }))) ?? 0
        metadataPendingCount = (try? context.fetchCount(FetchDescriptor<PhotoDerivedRecord>(
            predicate: #Predicate { $0.metadataEnrichedAt == nil }))) ?? 0
        // Registration observability stamp (4.1.1): DeviceRegistration
        // reads this so the server can see the pending count.
        UserDefaults.standard.set(metadataPendingCount, forKey: "lens.metadataPending")
        WidgetDataService.updateLensStatus(
            analyzed: analyzedCount, pending: pendingUploadCount, lastRun: lastRunAt)
    }

    /// Derived records from this month/day in earlier years, newest first —
    /// the On This Day Today card reads from here (fully on-device).
    func onThisDayRecords(limit: Int = 12) -> [PhotoDerivedRecord] {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        let year = calendar.component(.year, from: now)
        let all = (try? container.mainContext.fetch(FetchDescriptor<PhotoDerivedRecord>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
        return Array(all.filter {
            let c = calendar.dateComponents([.month, .day, .year], from: $0.capturedAt)
            return c.month == month && c.day == day && (c.year ?? year) < year
        }.prefix(limit))
    }

    // MARK: - Photo text index (full build, 4.0.4)

    /// Tokenize an asset's full text (OCR + video transcript) into
    /// the terms outbox. An asset with no exportable terms owes
    /// nothing and is stamped immediately — except under `replace`,
    /// where an empty export is the point (it clears stale terms
    /// server-side).
    func enqueueTerms(for record: PhotoDerivedRecord, fullOcrText: String?,
                      transcript: String?, replace: Bool, context: ModelContext) {
        let combined = [fullOcrText, transcript]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        let terms = combined.isEmpty ? [] : PhotoTermTokenizer.terms(from: combined)
        if terms.isEmpty && !replace {
            record.termsExportedAt = Date()
            return
        }
        let id = record.assetLocalId
        let existing = (try? context.fetch(FetchDescriptor<PhotoTermsOutboxRecord>(
            predicate: #Predicate { $0.assetLocalId == id })))?.first
        if let existing {
            existing.capturedAt = record.capturedAt
            existing.termsJSON = (try? String(data: JSONEncoder().encode(terms), encoding: .utf8)) ?? "[]"
            existing.replace = replace
            existing.queuedAt = Date()
        } else {
            context.insert(PhotoTermsOutboxRecord(
                assetLocalId: id, capturedAt: record.capturedAt,
                terms: terms, replace: replace))
        }
    }

    /// Post every queued term export in batches of at most 100
    /// records; on ack, stamp the records and clear the outbox.
    func flushTermsOutbox() async {
        let context = container.mainContext
        let pending = (try? context.fetch(FetchDescriptor<PhotoTermsOutboxRecord>(
            sortBy: [SortDescriptor(\.queuedAt, order: .forward)]))) ?? []
        for chunk in pending.chunked(into: 100) {
            do {
                _ = try await APIClient.shared.postPhotoTerms(
                    PhotoTermsBatchRequest(records: chunk.map { $0.wireRecord() }))
                let now = Date()
                for row in chunk {
                    let id = row.assetLocalId
                    if let record = (try? context.fetch(FetchDescriptor<PhotoDerivedRecord>(
                        predicate: #Predicate { $0.assetLocalId == id })))?.first {
                        record.termsExportedAt = now
                    }
                    context.delete(row)
                }
                AIActivityLog.record(
                    kind: "lens.terms",
                    detail: "Exported search terms for \(chunk.count) photos (text only; originals stayed on device)",
                    assets: chunk.count, leftDevice: chunk.count)
                try? context.save()
            } catch {
                logger.logMinimal("lens", "Terms upload failed; outbox retained:", error.localizedDescription)
                break
            }
        }
        refreshCounts()
    }

    /// Backfill the text index over the library the forward lane has
    /// not reached: newest-first by creation date, resumable to
    /// within a checkpoint. Two modes share this engine:
    ///
    /// - Lane mode (continuous == false): capped at 1,000 assets per
    ///   run for the charging/sync lanes, whose windows are short.
    /// - Continuous mode (continuous == true): the foreground "let
    ///   it go" run the author starts plugged in. No cap; the screen stays
    ///   awake; progress CHECKPOINTS every 25 assets — context saved,
    ///   cursor persisted — so an app kill, a reboot, or the Stop
    ///   button loses at most one checkpoint of work, and the next
    ///   run (either mode) picks up where this one stopped. Outboxes
    ///   flush to Nexus every 200 analyses, so server-side progress
    ///   lands as it goes too.
    ///
    /// Resumption is exact, not approximate: the persisted cursor is
    /// the last examined asset's creation date and resume is
    /// INCLUSIVE of it, with a record-existence skip for assets
    /// already done — so same-timestamp clusters (scans carry
    /// synthetic dates) can neither lose assets nor redo work.
    /// Every backfilled asset also gains its full Lens record, and
    /// Lens records that predate the index get their terms from
    /// their stored text first.
    func runTextIndexBackfill(trigger: String, continuous: Bool = false) async {
        guard isAuthorized, !isBackfilling else { return }
        isBackfilling = true
        backfillStopRequested = false
        backfillExamined = 0
        backfillAnalyzed = 0
        if continuous { UIApplication.shared.isIdleTimerDisabled = true }
        defer {
            isBackfilling = false
            if continuous { UIApplication.shared.isIdleTimerDisabled = false }
        }
        let context = container.mainContext
        let defaults = UserDefaults.standard

        // Catch-up: existing records whose terms were never exported.
        let owed = (try? context.fetch(FetchDescriptor<PhotoDerivedRecord>(
            predicate: #Predicate { $0.termsExportedAt == nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .forward)]))) ?? []
        for record in owed.prefix(500) {
            enqueueTerms(for: record, fullOcrText: record.ocrText,
                         transcript: record.transcript, replace: false, context: context)
        }
        if !owed.isEmpty { try? context.save() }

        if !textIndexBackfillDone {
            let cap = continuous ? Int.max : 1000
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            if let cursor = defaults.object(forKey: "textindex.cursor") as? Date {
                options.predicate = NSPredicate(format: "creationDate <= %@", cursor as NSDate)
            }
            let fetched = PHAsset.fetchAssets(with: options)
            backfillWindowTotal = fetched.count
            var candidates: [(id: String, created: Date)] = []
            fetched.enumerateObjects { asset, _, _ in
                if let created = asset.creationDate {
                    candidates.append((asset.localIdentifier, created))
                }
            }
            var sinceFlush = 0
            var processed = 0
            var lastAnalysis: LensAnalysis? = nil
            for candidate in candidates {
                if backfillStopRequested || Task.isCancelled { break }
                if processed >= cap { break }
                // Thermal pacing: serious slows the loop, critical
                // parks it (checkpointed) until the phone cools.
                let thermal = ProcessInfo.processInfo.thermalState
                if thermal == .critical {
                    var waited = 0
                    while ProcessInfo.processInfo.thermalState == .critical,
                          !backfillStopRequested, waited < 600 {
                        try? await Task.sleep(nanoseconds: 10_000_000_000)
                        waited += 10
                    }
                } else if thermal == .serious {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                processed += 1
                backfillExamined = processed
                let candidateId = candidate.id
                let exists = ((try? context.fetchCount(FetchDescriptor<PhotoDerivedRecord>(
                    predicate: #Predicate { $0.assetLocalId == candidateId }))) ?? 0) > 0
                if !exists, let analysis = await Self.analyzeAsset(localId: candidate.id) {
                    let record = PhotoDerivedRecord(
                        assetLocalId: candidate.id, capturedAt: analysis.capturedAt,
                        mediaType: analysis.mediaType, caption: analysis.caption,
                        tags: analysis.tags, ocrText: analysis.ocrText,
                        faceCount: analysis.faceCount, place: analysis.place,
                        durationS: analysis.durationS, transcript: analysis.transcript,
                        summary: analysis.summary, derivedAt: Date(),
                        visionVersion: Self.visionVersion, fmVersion: Self.fmVersion)
                    context.insert(record)
                    record.originalFilename = analysis.originalFilename
                    record.pixelWidth = analysis.pixelWidth
                    record.pixelHeight = analysis.pixelHeight
                    record.metadataEnrichedAt = Date()
                    enqueueTerms(for: record, fullOcrText: analysis.fullOcrText,
                                 transcript: analysis.transcript, replace: false, context: context)
                    backfillAnalyzed += 1
                    sinceFlush += 1
                    lastAnalysis = analysis
                    noteAnalyzed(analysis)
                }
                if processed % 25 == 0 {
                    try? context.save()
                    defaults.set(candidate.created, forKey: "textindex.cursor")
                    if sinceFlush >= 200 {
                        sinceFlush = 0
                        await flushOutbox()
                        await flushTermsOutbox()
                    }
                }
            }
            // Final checkpoint for the tail past the last %25 mark.
            try? context.save()
            if let last = candidates.prefix(processed).last {
                defaults.set(last.created, forKey: "textindex.cursor")
            }
            if processed >= candidates.count {
                textIndexBackfillDone = true
                defaults.set(true, forKey: "textindex.backfillDone")
            }
            if let lastAnalysis { noteAnalyzed(lastAnalysis, force: true) }
            logger.logMinimal("lens", "Text index backfill (\(trigger), continuous=\(continuous)): \(backfillAnalyzed) analyzed of \(processed) examined; done=\(textIndexBackfillDone)")
        }
        await flushOutbox()
        await flushTermsOutbox()
        refreshCounts()
    }

    /// Re-OCR sweep: assets edited since the last sweep (Photos
    /// bumps modificationDate on edits and re-crops) that already
    /// have a Lens record are re-analyzed, and their terms export
    /// with replace set so stale terms are superseded server-side.
    /// The watermark advances only when the sweep covered the whole
    /// window down to the old watermark.
    func runReanalyzeSweep(trigger: String) async {
        guard isAuthorized else { return }
        let context = container.mainContext
        let defaults = UserDefaults.standard
        let watermark = defaults.double(forKey: "textindex.modWatermark")
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
        options.fetchLimit = 120
        let fetched = PHAsset.fetchAssets(with: options)
        var window: [PHAsset] = []
        var covered = false
        var newestSeen: TimeInterval = watermark
        fetched.enumerateObjects { asset, _, _ in
            guard let mod = asset.modificationDate else { return }
            if mod.timeIntervalSince1970 > newestSeen { newestSeen = mod.timeIntervalSince1970 }
            if mod.timeIntervalSince1970 <= watermark { covered = true; return }
            window.append(asset)
        }
        var reanalyzed = 0
        for asset in window.prefix(60) {
            if Task.isCancelled { break }
            let id = asset.localIdentifier
            guard let record = (try? context.fetch(FetchDescriptor<PhotoDerivedRecord>(
                predicate: #Predicate { $0.assetLocalId == id })))?.first,
                  let analysis = await Self.analyzeAsset(localId: id) else { continue }
            record.caption = analysis.caption
            record.tagsJSON = (try? String(data: JSONEncoder().encode(analysis.tags), encoding: .utf8)) ?? "[]"
            record.ocrText = analysis.ocrText
            record.faceCount = analysis.faceCount
            record.place = analysis.place
            record.durationS = analysis.durationS
            record.transcript = analysis.transcript
            record.summary = analysis.summary
            record.derivedAt = Date()
            record.postedAt = nil
            record.termsExportedAt = nil
            record.originalFilename = analysis.originalFilename
            record.pixelWidth = analysis.pixelWidth
            record.pixelHeight = analysis.pixelHeight
            record.metadataEnrichedAt = Date()
            enqueueTerms(for: record, fullOcrText: analysis.fullOcrText,
                         transcript: analysis.transcript, replace: true, context: context)
            reanalyzed += 1
            noteAnalyzed(analysis)
        }
        if reanalyzed > 0 { try? context.save() }
        if covered { defaults.set(newestSeen, forKey: "textindex.modWatermark") }
        if reanalyzed > 0 {
            logger.logMinimal("lens", "Re-OCR sweep (\(trigger)): \(reanalyzed) assets re-analyzed")
            await flushOutbox()
            await flushTermsOutbox()
        }
    }

    // MARK: - Payload v2 metadata enrichment (OB-68202)

    /// One-time, resumable pass that gives pre-v2 records their
    /// bridge metadata. For every record whose metadata stamp is
    /// owed, it reads the filename and pixel dimensions straight
    /// from PhotoKit (no image decode, no re-analysis) and posts
    /// them to the enrich endpoint, which updates the stored
    /// rows server-side. Records are stamped as their chunk is
    /// acked; a record whose asset no longer exists on device is
    /// stamped locally with nothing posted (nothing more can
    /// ever be learned about it). The lane cap bounds background
    /// runs; a manual run is uncapped and stoppable.
    func runMetadataEnrichment(trigger: String, cap: Int = 500) async {
        guard isAuthorized, !isEnriching else { return }
        isEnriching = true
        enrichStopRequested = false
        defer {
            isEnriching = false
            // Registration observability stamp (4.1.1): a run happened,
            // however it ended; the server pairs this with the pending
            // count to tell a working lane from a stuck one.
            UserDefaults.standard.set(Date(), forKey: "lens.lastEnrichmentRunAt")
        }
        let context = container.mainContext
        let owed = (try? context.fetch(FetchDescriptor<PhotoDerivedRecord>(
            predicate: #Predicate { $0.metadataEnrichedAt == nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]))) ?? []
        let window = Array(owed.prefix(cap))
        var buffer: [(record: PhotoDerivedRecord, item: PhotoIntelligenceEnrichRecord)] = []
        var posted = 0

        func flush() async -> Bool {
            guard !buffer.isEmpty else { return true }
            do {
                _ = try await APIClient.shared.postPhotoIntelligenceEnrich(
                    PhotoIntelligenceEnrichBatchRequest(records: buffer.map { $0.item }))
                let now = Date()
                for entry in buffer { entry.record.metadataEnrichedAt = now }
                posted += buffer.count
                buffer.removeAll()
                try? context.save()
                return true
            } catch {
                logger.logMinimal("lens", "Enrich upload failed; pass will resume:", error.localizedDescription)
                return false
            }
        }

        var processed = 0
        for record in window {
            if enrichStopRequested || Task.isCancelled { break }
            processed += 1
            let id = record.assetLocalId
            guard let asset = PHAsset.fetchAssets(
                withLocalIdentifiers: [id], options: nil).firstObject else {
                record.metadataEnrichedAt = Date()
                continue
            }
            let metadata = Self.bridgeMetadata(for: asset)
            record.originalFilename = metadata.originalFilename
            record.pixelWidth = metadata.pixelWidth
            record.pixelHeight = metadata.pixelHeight
            buffer.append((record, PhotoIntelligenceEnrichRecord(
                assetLocalId: id,
                originalFilename: metadata.originalFilename,
                pixelWidth: metadata.pixelWidth,
                pixelHeight: metadata.pixelHeight)))
            if buffer.count >= 200 {
                if await flush() == false { break }
            }
            if processed % 25 == 0 { try? context.save() }
        }
        _ = await flush()
        try? context.save()
        if posted > 0 {
            AIActivityLog.record(
                kind: "lens.enrich",
                detail: "Posted bridge metadata (filename, dimensions) for \(posted) older records (\(trigger))",
                assets: posted, leftDevice: posted)
            logger.logMinimal("lens", "Metadata enrichment (\(trigger)): \(posted) posted of \(window.count) owed")
        }
        refreshCounts()
    }

    // MARK: - Per-asset analysis (off the main actor)

    struct LensAnalysis: Sendable {
        let capturedAt: Date
        let mediaType: String
        let caption: String
        let tags: [String]
        /// The record's stored text (capped at 1500 chars, as shipped
        /// in 4.0.0) and the FULL OCR text, which the text index
        /// tokenizes so signage and documents past the cap still
        /// become searchable.
        let ocrText: String?
        let fullOcrText: String?
        let faceCount: Int
        let place: String?
        let durationS: Double?
        let transcript: String?
        let summary: String?
        let thumbnailJPEG: Data?
        /// Payload v2 bridge metadata (OB-68202), read from the
        /// PHAsset itself; no image data is decoded for these.
        let originalFilename: String?
        let pixelWidth: Int
        let pixelHeight: Int
    }

    nonisolated static func analyzeAsset(localId: String) async -> LensAnalysis? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil).firstObject,
              let capturedAt = asset.creationDate else { return nil }
        let isVideo = asset.mediaType == .video

        var labels: [String] = []
        var ocrText: String? = nil
        var fullOcrText: String? = nil
        var faceCount = 0
        var thumbnail: Data? = nil
        if let image = await requestImage(asset: asset) {
            thumbnail = thumbnailJPEG(from: image)
            let visual = analyzeImage(image)
            labels = visual.labels
            ocrText = visual.ocrText.map { String($0.prefix(1500)) }
            fullOcrText = visual.ocrText
            faceCount = visual.faceCount
        }

        let metadata = bridgeMetadata(for: asset)
        let place = await placeName(for: asset)
        let transcript = isVideo ? await transcribe(asset: asset) : nil
        let fm = await captionAndTags(labels: labels, ocrText: ocrText, place: place,
                                      transcript: transcript, isVideo: isVideo)

        return LensAnalysis(
            capturedAt: capturedAt,
            mediaType: isVideo ? "video" : "photo",
            caption: fm.caption,
            tags: fm.tags,
            ocrText: ocrText,
            fullOcrText: fullOcrText,
            faceCount: faceCount,
            place: place,
            durationS: isVideo ? asset.duration : nil,
            transcript: transcript,
            summary: isVideo ? fm.summary : nil,
            thumbnailJPEG: thumbnail,
            originalFilename: metadata.originalFilename,
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight)
    }

    /// Bridge metadata for the W9.1 library bridge (OB-68202):
    /// the original filename from the asset's resources and the
    /// pixel dimensions from the asset itself. Pure PhotoKit
    /// metadata: nothing is decoded and nothing leaves the
    /// device beyond these three values on the derived record.
    nonisolated static func bridgeMetadata(for asset: PHAsset)
        -> (originalFilename: String?, pixelWidth: Int, pixelHeight: Int) {
        let resources = PHAssetResource.assetResources(for: asset)
        let primary = resources.first { $0.type == .photo || $0.type == .video }
            ?? resources.first { $0.type == .fullSizePhoto || $0.type == .fullSizeVideo }
            ?? resources.first
        return (primary?.originalFilename, asset.pixelWidth, asset.pixelHeight)
    }

    nonisolated private static func requestImage(asset: PHAsset) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 1024, height: 1024),
                contentMode: .aspectFit, options: options
            ) { image, info in
                if let info, (info[PHImageResultIsDegradedKey] as? Bool) == true { return }
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    /// Downscale the analysis image to a small JPEG for the
    /// last-analyzed card (4.0.7): 240px on the long edge, crisp on
    /// a settings row at a few tens of KB in memory.
    nonisolated private static func thumbnailJPEG(from cg: CGImage) -> Data? {
        let maxEdge: CGFloat = 240
        let scale = min(1, maxEdge / CGFloat(max(cg.width, cg.height)))
        let w = max(1, Int(CGFloat(cg.width) * scale))
        let h = max(1, Int(CGFloat(cg.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        return UIImage(cgImage: scaled).jpegData(compressionQuality: 0.7)
    }

    nonisolated private static func analyzeImage(_ image: CGImage)
        -> (labels: [String], ocrText: String?, faceCount: Int) {
        let classify = VNClassifyImageRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        let faces = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([classify, text, faces])

        var labels: [String] = []
        for observation in classify.results ?? [] where observation.confidence > 0.08 {
            // Identifiers can be comma-joined taxonomy paths; keep the head.
            let head = observation.identifier.split(separator: ",").first.map(String.init) ?? observation.identifier
            let label = head.trimmingCharacters(in: .whitespaces).lowercased()
            if !label.isEmpty && !labels.contains(label) { labels.append(label) }
            if labels.count >= 10 { break }
        }
        let ocr = (text.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        let faceCount = faces.results?.count ?? 0
        return (labels, ocr.isEmpty ? nil : ocr, faceCount)
    }

    nonisolated private static func placeName(for asset: PHAsset) async -> String? {
        guard let location = asset.location,
              let request = MKReverseGeocodingRequest(location: location),
              let items = try? await request.mapItems,
              let item = items.first else { return nil }
        if let name = item.name { return name }
        return item.address?.shortAddress
    }

    // MARK: - Video transcription (SpeechAnalyzer, on-device)

    nonisolated private static func transcribe(asset: PHAsset) async -> String? {
        do {
            let avBox: AVAssetBox = await withCheckedContinuation { continuation in
                let options = PHVideoRequestOptions()
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .automatic
                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { av, _, _ in
                    continuation.resume(returning: AVAssetBox(asset: av))
                }
            }
            let avAsset = avBox.asset
            guard let urlAsset = avAsset as? AVURLAsset else { return nil }
            let audioTracks = try await urlAsset.loadTracks(withMediaType: .audio)
            guard !audioTracks.isEmpty,
                  let export = AVAssetExportSession(asset: urlAsset, presetName: AVAssetExportPresetAppleM4A)
            else { return nil }
            let outURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("lens-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: outURL) }
            try await export.export(to: outURL, as: .m4a)

            let transcriber = SpeechTranscriber(locale: Locale.current, preset: .transcription)
            if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await install.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let collector = Task { () -> String in
                var text = ""
                do {
                    for try await result in transcriber.results where result.isFinal {
                        text += NSAttributedString(result.text).string + " "
                    }
                } catch { /* partial transcript is still useful */ }
                return text
            }
            let audioFile = try AVAudioFile(forReading: outURL)
            _ = try await analyzer.analyzeSequence(from: audioFile)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : String(text.prefix(4000))
        } catch {
            return nil
        }
    }

    // MARK: - Foundation Models caption / tags / summary

    @Generable
    struct LensCaption {
        @Guide(description: "One factual sentence describing what the photo or video frame shows")
        var caption: String
        @Guide(description: "Up to six short lowercase descriptive tags")
        var tags: [String]
    }

    nonisolated private static func captionAndTags(
        labels: [String], ocrText: String?, place: String?,
        transcript: String?, isVideo: Bool
    ) async -> (caption: String, tags: [String], summary: String?) {
        let fallbackCaption = labels.first.map { "Photo showing \($0)" }
            ?? (isVideo ? "Video clip" : "Photo")
        var tags = Array(labels.prefix(6))
        var caption = fallbackCaption
        var summary: String? = nil

        guard SystemLanguageModel.default.availability == .available else {
            return (caption, tags, transcript != nil ? caption : nil)
        }
        do {
            let session = LanguageModelSession(instructions:
                "You describe personal photos and videos factually and briefly. No speculation about people identities.")
            var prompt = "Vision labels: \(labels.joined(separator: ", "))."
            if let place { prompt += " Place: \(place)." }
            if let ocrText { prompt += " Text seen: \(String(ocrText.prefix(300)))" }
            let response = try await session.respond(to: prompt, generating: LensCaption.self)
            if !response.content.caption.isEmpty { caption = response.content.caption }
            let fmTags = response.content.tags.map { $0.lowercased() }.filter { !$0.isEmpty }
            if !fmTags.isEmpty { tags = Array(Set(tags + fmTags)).prefix(8).sorted() }
            if isVideo, let transcript, !transcript.isEmpty {
                let summarySession = LanguageModelSession(instructions:
                    "Summarize what happens in this video in two factual sentences, from its audio transcript.")
                let s = try await summarySession.respond(to: String(transcript.prefix(3000)))
                let text = s.content.trimmingCharacters(in: .whitespacesAndNewlines)
                summary = text.isEmpty ? nil : String(text.prefix(4000))
            }
        } catch {
            // Fall back to the Vision-derived caption/tags.
        }
        return (caption, tags, summary)
    }
}

// MARK: - SyncCoordinator participation

extension LensService: BackgroundSyncable {
    var sourceKey: String { "lens" }
    var isEnabled: Bool { isAuthorized }
    var lastSyncDate: Date? { lastRunAt }
    func backgroundSync() async {
        await processNewAssets(trigger: "sweep")
        await runTextIndexBackfill(trigger: "sweep")
        await runMetadataEnrichment(trigger: "sweep")
    }
}

private struct LensTaskBox<T>: @unchecked Sendable {
    let value: T
}

/// AVAsset is not Sendable; PhotoKit delivers it on its own queue and the
/// transcription path uses it read-only, so the hand-off is boxed.
private struct AVAssetBox: @unchecked Sendable {
    let asset: AVAsset?
}

// MARK: - Photo library change observation

extension LensService: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            LensService.shared.scheduleProcessing()
        }
    }
}
