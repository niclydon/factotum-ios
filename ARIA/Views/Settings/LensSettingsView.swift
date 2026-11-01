import SwiftUI
import Photos
import UIKit

/// Settings → Lens (Factotum 4.0 W9). The PhotoKit full-access ask lives
/// here: one tap, with the value and the privacy posture stated up front.
struct LensSettingsView: View {
    @State private var lens = LensService.shared

    var body: some View {
        List {
            Section {
                Text("Lens analyzes your photos and videos on this iPhone — what is in them, text they contain, and short summaries — to power your timeline, On This Day, and photo search. Analysis uses the on-device Vision and language models. Your originals never leave this phone; only the short text descriptions sync to Nexus.")
                    .font(.subheadline)
                    .foregroundStyle(ARIATheme.textSecondary)
            }

            Section("Status") {
                LabeledContent("Photos access", value: accessLabel)
                if lens.isAuthorized {
                    LabeledContent("Analyzed", value: "\(lens.analyzedCount)")
                    LabeledContent("Waiting to upload", value: "\(lens.pendingUploadCount)")
                    LabeledContent("Last run", value: lens.lastRunAt.map {
                        $0.formatted(date: .abbreviated, time: .shortened)
                    } ?? "Never")
                }
            }

            if let last = lens.lastAnalyzed {
                Section("Latest analysis") {
                    HStack(alignment: .top, spacing: 12) {
                        if let data = last.thumbnailJPEG, let ui = UIImage(data: data) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            Image(systemName: last.mediaType == "video" ? "video" : "photo")
                                .font(.largeTitle)
                                .foregroundStyle(ARIATheme.textMuted)
                                .frame(width: 76, height: 76)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(last.caption)
                                .font(.subheadline)
                                .lineLimit(3)
                            if !last.tags.isEmpty {
                                Text(last.tags.prefix(6).joined(separator: " \u{00B7} "))
                                    .font(.caption)
                                    .foregroundStyle(ARIATheme.textSecondary)
                                    .lineLimit(2)
                            }
                            Text(latestMetaLine(last))
                                .font(.caption2)
                                .foregroundStyle(ARIATheme.textMuted)
                        }
                    }
                }
            }

            if lens.isAuthorized {
                Section("Library bridge") {
                    LabeledContent("Metadata enriched",
                                   value: "\(lens.metadataEnrichedCount) of \(lens.metadataEnrichedCount + lens.metadataPendingCount)")
                    if lens.metadataPendingCount > 0 {
                        if lens.isEnriching {
                            HStack { ProgressView(); Text("Enriching…") }
                            Button("Stop enrichment", role: .destructive) {
                                lens.stopMetadataEnrichment()
                            }
                        } else {
                            Button("Enrich \(lens.metadataPendingCount) older photos now") {
                                Task { await lens.runMetadataEnrichment(trigger: "manual", cap: Int.max) }
                            }
                        }
                    }
                    Text("Newer Nexus features match these photos against your Mac library using each photo's filename and dimensions, which older analyses did not record. Enrichment reads only that metadata from PhotoKit — no image is decoded and nothing new leaves this phone beyond those values on the records Nexus already holds.")
                        .font(.caption)
                        .foregroundStyle(ARIATheme.textSecondary)
                }
            }

            Section {
                switch lens.authorizationStatus {
                case .notDetermined:
                    Button("Enable Lens") {
                        Task { await lens.requestAuthorization() }
                    }
                case .denied, .restricted:
                    Link("Open Settings to grant Photos access",
                         destination: URL(string: UIApplication.openSettingsURLString)!)
                case .authorized, .limited:
                    Button {
                        Task { await lens.processNewAssets(trigger: "manual") }
                    } label: {
                        if lens.isProcessing {
                            HStack { ProgressView(); Text("Analyzing…") }
                        } else {
                            Text("Analyze new photos now")
                        }
                    }
                    .disabled(lens.isProcessing)
                    if lens.pendingUploadCount > 0 {
                        Button("Upload \(lens.pendingUploadCount) pending") {
                            Task { await lens.flushOutbox() }
                        }
                    }
                    TextIndexPrototypeSection()
                @unknown default:
                    EmptyView()
                }
            }
        }
        .navigationTitle("Lens")
        .task { lens.checkAuthorization() }
    }

    private func latestMetaLine(_ last: LensService.LastAnalyzed) -> String {
        var parts = [last.capturedAt.formatted(date: .abbreviated, time: .shortened)]
        if let place = last.place { parts.append(place) }
        if last.faceCount > 0 {
            parts.append(last.faceCount == 1 ? "1 face" : "\(last.faceCount) faces")
        }
        parts.append(last.mediaType == "video" ? "Video" : "Photo")
        return parts.joined(separator: " \u{00B7} ")
    }

    private var accessLabel: String {
        switch lens.authorizationStatus {
        case .authorized: return "Full access"
        case .limited: return "Limited access"
        case .notDetermined: return "Not enabled"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }
}
