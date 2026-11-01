import SwiftUI

/// One Big Thing (Factotum 4.0 W3): the morning composite at the top
/// of Today — readiness with its evidence, the 31-day cumulative
/// stress index, the body-age delta vs the owner's own 90-day self,
/// and a one-paragraph read generated on-device from the server's
/// brief seed (server fallback text when the model is unavailable).
/// Renders nothing until the endpoint answers, so Today stays clean
/// while the server slice is undeployed.
struct OneBigThingCard: View {
    let state: Loadable<MobileOneBigThing>
    @State private var paragraph: String?

    var body: some View {
        if case .loading = state {
            // Reserve the card's slot while the composite loads so the
            // stack does not re-layout mid-scroll when it lands (4.0.2).
            TodayCard(title: "One Big Thing", icon: "sun.max.fill") {
                ProgressView().frame(maxWidth: .infinity)
            }
        } else if case .loaded(let data) = state {
            TodayCard(title: "One Big Thing", icon: "sun.max.fill") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(data.forDate)
                        .font(.caption)
                        .foregroundStyle(ARIATheme.textMuted)

                    HStack(alignment: .center, spacing: 16) {
                        VStack(spacing: 0) {
                            Text("\(data.readiness.score)")
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                                .foregroundStyle(ARIATheme.textPrimary)
                            Text("readiness · \(data.readiness.confidence)")
                                .font(.caption2)
                                .foregroundStyle(ARIATheme.textMuted)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Stress \(data.cumulativeStress.index) over \(data.cumulativeStress.windowDays) days", systemImage: "waveform.path.ecg")
                                .font(.subheadline)
                                .foregroundStyle(ARIATheme.textSecondary)
                            Label("Body age \(deltaText(data.bodyAgeIndex)) vs your \(data.bodyAgeIndex.referenceWindowDays)-day self", systemImage: "person.crop.circle")
                                .font(.subheadline)
                                .foregroundStyle(ARIATheme.textSecondary)
                            if let top = data.briefSeed.topStressContributor {
                                Label("Driven by \(humanize(top))", systemImage: "arrow.up.forward.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(ARIATheme.textSecondary)
                            }
                        }
                    }

                    Text(paragraph ?? data.briefSeed.fallbackParagraph)
                        .font(.body)
                        .foregroundStyle(ARIATheme.textPrimary)
                        .task(id: data.forDate) {
                            paragraph = await MorningBriefService.shared.paragraph(for: data.briefSeed, date: data.forDate)
                        }

                    if !data.briefSeed.headlineFacts.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(data.briefSeed.headlineFacts, id: \.self) { fact in
                                Text("· \(fact)")
                                    .font(.caption)
                                    .foregroundStyle(ARIATheme.textMuted)
                            }
                        }
                    }

                    NavigationLink {
                        OneBigThingExplainerView()
                    } label: {
                        Label("How this is computed", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(ARIATheme.textSecondary)
                    }
                }
            }
        }
    }

    private func deltaText(_ bodyAge: MobileOneBigThing.BodyAgeIndex) -> String {
        let sign = bodyAge.deltaIndex > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", bodyAge.deltaIndex)) (\(bodyAge.direction))"
    }

    private func humanize(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
    }
}
