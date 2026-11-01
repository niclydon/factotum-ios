import Foundation
import Photos
import Vision
import UIKit

/// Photo text index PROTOTYPE (design: DESIGN-PHOTO-TEXT-INDEX.md;
/// the author approved the bounded prototype 2026-10-20; server slice
/// OB-66960). Runs Vision OCR over a bounded selection — the April
/// 2010 window first (it holds the "LAZER ZONE" acceptance frame),
/// then the 700 newest images — tokenizes the text, exports terms to
/// POST /api/mobile/photo-terms, and measures what the full-build
/// decision needs: the LAZER verdict verbatim, throughput, thermal
/// behavior, battery cost, payload per asset, term yield, and a
/// 50-term reservoir sample for false-positive texture.
///
/// Deliberately NOT the full build: foreground-only, no backfill
/// cursor, no change-observation re-OCR, images only (video
/// transcript terms are a full-build question). Lens keeps doing its
/// own forward analysis independently; this run reads the library
/// directly and changes no Lens state.
@Observable
@MainActor
final class TextIndexPrototype {
    static let shared = TextIndexPrototype()

    struct Summary: Codable, Sendable {
        var finishedAt: Date
        var completed: Bool
        var selectedCount: Int
        var processedCount: Int
        var failedCount: Int
        var assetsWithText: Int
        var totalTerms: Int
        var durationSeconds: Double
        var millisecondsPerAsset: Double
        var batteryStartPercent: Int?
        var batteryEndPercent: Int?
        var wasCharging: Bool
        var thermalPeak: String
        var payloadBytesTotal: Int
        var payloadBytesPerAsset: Double
        var serverInserted: Int
        var serverDuplicates: Int
        var exportFailures: Int
        var lazerVerdict: String
        var termSample: [String]
    }

    private(set) var isRunning = false
    private(set) var processed = 0
    private(set) var selected = 0
    private(set) var statusLine = ""
    private(set) var summary: Summary?

    private var stopRequested = false

    private static let summaryKey = "textindex_proto_summary_v1"
    private static let newestCount = 700
    private static let flushEvery = 100

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.summaryKey),
           let decoded = try? JSONDecoder().decode(Summary.self, from: data) {
            summary = decoded
        }
    }

    func stop() { stopRequested = true }

    func run() async {
        guard !isRunning else { return }
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            statusLine = "Photos full access is not granted."
            return
        }
        isRunning = true
        stopRequested = false
        processed = 0
        defer { isRunning = false }

        // Selection: April 2010 window first (acceptance), then newest.
        let assets = Self.selectAssets()
        selected = assets.count
        guard !assets.isEmpty else {
            statusLine = "No assets selected."
            return
        }

        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryStart = Self.batteryPercent()
        let wasCharging = UIDevice.current.batteryState == .charging
            || UIDevice.current.batteryState == .full

        let started = Date()
        var failed = 0
        var withText = 0
        var totalTerms = 0
        var allTerms: [String] = []
        var buffer: [PhotoTermsRecord] = []
        var payloadBytes = 0
        var serverInserted = 0
        var serverDuplicates = 0
        var exportFailures = 0
        var thermalPeak = ProcessInfo.processInfo.thermalState
        var lazerVerdict: String?

        func flush() async {
            guard !buffer.isEmpty else { return }
            let batch = PhotoTermsBatchRequest(records: buffer)
            buffer = []
            if let data = try? JSONEncoder().encode(batch) {
                payloadBytes += data.count
            }
            do {
                let ack = try await APIClient.shared.postPhotoTerms(batch)
                serverInserted += ack.inserted ?? 0
                serverDuplicates += ack.duplicates ?? 0
            } catch {
                exportFailures += 1
            }
        }

        for (index, asset) in assets.enumerated() {
            if stopRequested { break }
            if index % 25 == 0 {
                let now = ProcessInfo.processInfo.thermalState
                if now.rawValue > thermalPeak.rawValue { thermalPeak = now }
            }
            statusLine = "Processing \(index + 1) of \(assets.count)…"
            guard let image = await Self.requestImage(asset: asset) else {
                failed += 1
                processed = index + 1
                continue
            }
            let text = Self.recognizeText(in: image)
            if let text, !text.isEmpty {
                withText += 1
                if lazerVerdict == nil,
                   text.uppercased().contains("LAZER") {
                    let line = text.split(separator: "\n")
                        .first { $0.uppercased().contains("LAZER") }
                        .map(String.init) ?? "LAZER"
                    let when = asset.creationDate?
                        .formatted(date: .abbreviated, time: .shortened) ?? "unknown date"
                    lazerVerdict = "HIT — \u{201C}\(line)\u{201D} (photo from \(when))"
                }
                let terms = Self.tokenize(text)
                totalTerms += terms.count
                allTerms.append(contentsOf: terms)
                if !terms.isEmpty {
                    buffer.append(PhotoTermsRecord(
                        assetLocalId: asset.localIdentifier,
                        capturedAt: asset.creationDate.map {
                            ISO8601DateFormatter().string(from: $0)
                        },
                        terms: terms))
                }
            }
            processed = index + 1
            if buffer.count >= Self.flushEvery { await flush() }
        }
        await flush()

        let duration = Date().timeIntervalSince(started)
        let done = !stopRequested && processed >= assets.count
        let result = Summary(
            finishedAt: Date(),
            completed: done,
            selectedCount: assets.count,
            processedCount: processed,
            failedCount: failed,
            assetsWithText: withText,
            totalTerms: totalTerms,
            durationSeconds: duration,
            millisecondsPerAsset: processed > 0
                ? duration * 1000 / Double(processed) : 0,
            batteryStartPercent: batteryStart,
            batteryEndPercent: Self.batteryPercent(),
            wasCharging: wasCharging,
            thermalPeak: Self.thermalName(thermalPeak),
            payloadBytesTotal: payloadBytes,
            payloadBytesPerAsset: processed > 0
                ? Double(payloadBytes) / Double(processed) : 0,
            serverInserted: serverInserted,
            serverDuplicates: serverDuplicates,
            exportFailures: exportFailures,
            lazerVerdict: lazerVerdict
                ?? "No \u{201C}LAZER\u{201D} found in the OCR text of \(processed) processed photos.",
            termSample: Array(allTerms.shuffled().prefix(50)))
        summary = result
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: Self.summaryKey)
        }
        statusLine = done ? "Prototype run complete." : "Prototype run stopped early."
        Logger.shared.log("textindex", "prototype done processed=\(processed) terms=\(totalTerms) lazer=\(lazerVerdict != nil)")
    }

    // MARK: - Selection

    private static func selectAssets() -> [PHAsset] {
        var seen = Set<String>()
        var ordered: [PHAsset] = []

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let aprilStart = utc.date(from: DateComponents(year: 2010, month: 4, day: 1))!
        let mayStart = utc.date(from: DateComponents(year: 2010, month: 5, day: 1))!
        let windowOptions = PHFetchOptions()
        windowOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        windowOptions.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@",
            PHAssetMediaType.image.rawValue, aprilStart as NSDate, mayStart as NSDate)
        let window = PHAsset.fetchAssets(with: .image, options: windowOptions)
        window.enumerateObjects { asset, _, _ in
            if seen.insert(asset.localIdentifier).inserted { ordered.append(asset) }
        }

        let newestOptions = PHFetchOptions()
        newestOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        newestOptions.fetchLimit = newestCount
        newestOptions.predicate = NSPredicate(
            format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let newest = PHAsset.fetchAssets(with: .image, options: newestOptions)
        newest.enumerateObjects { asset, _, _ in
            if seen.insert(asset.localIdentifier).inserted { ordered.append(asset) }
        }
        return ordered
    }

    // MARK: - OCR (mirrors LensService's image request + Vision setup)

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

    nonisolated private static func recognizeText(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    /// The prototype originally tokenized privately; the full
    /// build's shared tokenizer (same v1 rules + stopword filter)
    /// is the single implementation now.
    nonisolated private static func tokenize(_ text: String) -> [String] {
        PhotoTermTokenizer.terms(from: text)
    }

    // MARK: - Device metrics

    private static func batteryPercent() -> Int? {
        let level = UIDevice.current.batteryLevel
        return level >= 0 ? Int((level * 100).rounded()) : nil
    }

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
