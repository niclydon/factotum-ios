import SwiftUI
import WidgetKit
import ActivityKit

/// Live Activity for long-running Factotum work (Factotum 4.0 W6): Replay
/// narrative generation and long Lens analysis sweeps.
struct FactotumProgressLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FactotumProgressAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.attributes.kind == "lens" ? "camera.aperture" : "clock.arrow.circlepath")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.label)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let progress = context.state.progress {
                    ProgressView(value: progress)
                        .frame(width: 56)
                }
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.kind == "lens" ? "camera.aperture" : "clock.arrow.circlepath")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.detail)
                        .font(.caption)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.attributes.kind == "lens" ? "camera.aperture" : "clock.arrow.circlepath")
            } compactTrailing: {
                if let progress = context.state.progress {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                }
            } minimal: {
                Image(systemName: context.attributes.kind == "lens" ? "camera.aperture" : "clock.arrow.circlepath")
            }
        }
    }
}
