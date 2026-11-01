import SwiftUI
import WidgetKit
import ActivityKit

/// Live Activity for meeting countdowns on Lock Screen and Dynamic Island.
struct MeetingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ARIAMeetingAttributes.self) { context in
            // Lock Screen / banner presentation
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    Image("ARIAProfile")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.title)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                        if !context.attributes.location.isEmpty {
                            Text(context.attributes.location)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startTime, style: .relative)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.cyan)
                        .monospacedDigit()
                }
            } compactLeading: {
                Image("ARIAProfile")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())
            } compactTrailing: {
                Text(context.state.startTime, style: .relative)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.cyan)
                    .monospacedDigit()
            } minimal: {
                Image("ARIAProfile")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<ARIAMeetingAttributes>) -> some View {
        HStack(spacing: 12) {
            Image("ARIAProfile")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                if !context.attributes.location.isEmpty {
                    Text(context.attributes.location)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(context.state.status == "now" ? "Now" : "In")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if context.state.status != "now" {
                    Text(context.state.startTime, style: .relative)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                        .monospacedDigit()
                } else {
                    Text("Active")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(16)
    }
}
