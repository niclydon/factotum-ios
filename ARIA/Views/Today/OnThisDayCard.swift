import SwiftUI
import Photos

/// On This Day (Factotum 4.0 W9): photos and videos from this month/day in
/// earlier years, read from the on-device Lens index. Renders nothing when
/// Lens is off or nothing matches — Today stays clean.
struct OnThisDayCard: View {
    @State private var records: [PhotoDerivedRecord] = []

    var body: some View {
        Group {
            if !records.isEmpty {
                TodayCard(title: "On This Day", icon: "photo.on.rectangle.angled") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(records, id: \.assetLocalId) { record in
                                VStack(alignment: .leading, spacing: 6) {
                                    LensThumbnail(localId: record.assetLocalId)
                                        .frame(width: 128, height: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Text(record.capturedAt, format: .dateTime.year())
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ARIATheme.textSecondary)
                                    Text(record.caption)
                                        .font(.caption)
                                        .foregroundStyle(ARIATheme.textPrimary)
                                        .lineLimit(2)
                                        .frame(width: 128, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            let lens = LensService.shared
            guard lens.isAuthorized else { return }
            records = lens.onThisDayRecords()
        }
    }
}

/// A library thumbnail by local identifier, loaded on demand. The asset
/// itself never leaves the device; this is a local render only.
struct LensThumbnail: View {
    let localId: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(ARIATheme.textMuted.opacity(0.15))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(ARIATheme.textMuted)
            }
        }
        .clipped()
        .task {
            guard image == nil,
                  let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil).firstObject
            else { return }
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .opportunistic
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 256, height: 192),
                contentMode: .aspectFill, options: options
            ) { loaded, info in
                if let info, (info[PHImageResultIsDegradedKey] as? Bool) == true { return }
                if let loaded { image = loaded }
            }
        }
    }
}
