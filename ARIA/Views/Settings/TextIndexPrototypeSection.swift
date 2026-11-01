import SwiftUI

/// Settings → Lens section for the photo text index
/// (DESIGN-PHOTO-TEXT-INDEX.md). The full build (4.0.4) indexes
/// automatically: Lens analysis emits terms, the charging lane
/// backfills the library behind a cursor, edited photos re-export
/// with replace. This section is the status surface plus a manual
/// backfill trigger. The October 20 prototype summary stays below
/// as the measurement record the full build was approved on.
struct TextIndexPrototypeSection: View {
    @State private var lens = LensService.shared
    @State private var proto = TextIndexPrototype.shared

    var body: some View {
        Section("Photo Text Index") {
            LabeledContent("Photos indexed", value: "\(lens.termsIndexedCount)")
            LabeledContent("Waiting to export", value: "\(lens.termsPendingCount)")
            LabeledContent("Backfill", value: lens.textIndexBackfillDone
                ? "Complete"
                : (lens.isBackfilling ? "Running…" : "In progress (charging lane)"))
            if lens.isBackfilling {
                if lens.backfillWindowTotal > 0 {
                    ProgressView(value: Double(lens.backfillExamined),
                                 total: Double(lens.backfillWindowTotal))
                }
                LabeledContent("This run", value: "\(lens.backfillAnalyzed) analyzed · \(lens.backfillExamined) of \(lens.backfillWindowTotal) checked")
                Text("Progress is saved every 25 photos. Stopping, closing the app, or a reboot loses nothing — the next run picks up at the last checkpoint.")
                    .font(.caption)
                    .foregroundStyle(ARIATheme.textSecondary)
                Button("Stop backfill", role: .destructive) {
                    lens.stopTextIndexBackfill()
                }
            } else if !lens.textIndexBackfillDone {
                Button("Start full backfill") {
                    Task { await lens.runTextIndexBackfill(trigger: "manual", continuous: true) }
                }
                Text("Runs until the library is done or you stop it. Plug in first: the screen stays awake while it runs, and progress is saved every 25 photos, so you can stop anytime and resume later exactly where it left off. The charging lane also advances it 1,000 photos at a time on its own.")
                    .font(.caption)
                    .foregroundStyle(ARIATheme.textSecondary)
            }
            Text("Search terms from photo text, recognized on this phone and exported to Nexus. New and edited photos index as Lens analyzes them.")
                .font(.caption)
                .foregroundStyle(ARIATheme.textSecondary)
        }

        Section("Prototype — Oct 20, 2026") {
            if proto.isRunning {
                HStack { ProgressView(); Text(proto.statusLine) }
                    .font(.subheadline)
                LabeledContent("Processed", value: "\(proto.processed) of \(proto.selected)")
                Button("Stop run", role: .destructive) { proto.stop() }
            } else {
                Button("Re-run the bounded prototype") {
                    Task { await proto.run() }
                }
            }

            if let s = proto.summary {
                LabeledContent("LAZER ZONE check", value: s.lazerVerdict)
                LabeledContent("Last run", value: s.finishedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Completed", value: s.completed ? "Yes" : "Stopped early")
                LabeledContent("Photos processed", value: "\(s.processedCount) of \(s.selectedCount) (\(s.failedCount) failed)")
                LabeledContent("Photos with text", value: "\(s.assetsWithText)")
                LabeledContent("Terms exported", value: "\(s.totalTerms) (\(s.serverInserted) new on server)")
                LabeledContent("Time", value: "\(Int(s.durationSeconds))s · \(Int(s.millisecondsPerAsset)) ms/photo")
                LabeledContent("Battery", value: batteryText(s))
                LabeledContent("Thermal peak", value: s.thermalPeak)
                LabeledContent("Payload", value: "\(s.payloadBytesTotal) bytes · \(Int(s.payloadBytesPerAsset))/photo")
                if !s.termSample.isEmpty {
                    Text("Sample terms: \(s.termSample.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(ARIATheme.textMuted)
                }
            }
        }
    }

    private func batteryText(_ s: TextIndexPrototype.Summary) -> String {
        guard let start = s.batteryStartPercent, let end = s.batteryEndPercent else {
            return "Unavailable"
        }
        return "\(start)% → \(end)%\(s.wasCharging ? " (charging)" : "")"
    }
}
