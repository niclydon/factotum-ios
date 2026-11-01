import AppIntents
import SwiftUI
import WidgetKit

/// Control Center controls (Factotum 4.0 W6). Values come from the App
/// Group snapshots the app publishes (WidgetDataService); tapping a control
/// opens the app. The open intents write the desired tab into the shared
/// defaults, which the app consumes when it becomes active.

private let factotumSuiteName = "group.com.example.factotum"

private func sharedDefaults() -> UserDefaults? {
    UserDefaults(suiteName: factotumSuiteName)
}

struct OpenFactotumControlIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Open Factotum"
    nonisolated(unsafe) static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        sharedDefaults()?.set("today", forKey: "factotum_pending_tab")
        return .result()
    }
}

// MARK: - One Big Thing glance

struct OneBigThingControlValue {
    let readiness: Int?
    let stressIndex: Int?
}

struct OneBigThingControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: OneBigThingControlConfigurationIntent) -> OneBigThingControlValue {
        OneBigThingControlValue(readiness: 90, stressIndex: 35)
    }

    func currentValue(configuration: OneBigThingControlConfigurationIntent) async throws -> OneBigThingControlValue {
        let data = sharedDefaults()?.dictionary(forKey: "widget_one_big_thing")
        return OneBigThingControlValue(
            readiness: data?["readiness"] as? Int,
            stressIndex: data?["stress"] as? Int)
    }
}

struct OneBigThingControlConfigurationIntent: ControlConfigurationIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "One Big Thing"
}

struct OneBigThingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: "com.example.factotum.control.onebigthing",
            provider: OneBigThingControlProvider()
        ) { value in
            ControlWidgetButton(action: OpenFactotumControlIntent()) {
                Label(
                    value.readiness.map { "Readiness \($0)" } ?? "One Big Thing",
                    systemImage: "sun.max.fill")
            }
        }
        .displayName("One Big Thing")
        .description("Today's readiness at a glance.")
    }
}

// MARK: - Lens status

struct LensControlValue {
    let analyzed: Int
    let pending: Int
}

struct LensControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: LensControlConfigurationIntent) -> LensControlValue {
        LensControlValue(analyzed: 128, pending: 0)
    }

    func currentValue(configuration: LensControlConfigurationIntent) async throws -> LensControlValue {
        let data = sharedDefaults()?.dictionary(forKey: "widget_lens_status")
        return LensControlValue(
            analyzed: data?["analyzed"] as? Int ?? 0,
            pending: data?["pending"] as? Int ?? 0)
    }
}

struct LensControlConfigurationIntent: ControlConfigurationIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Lens Status"
}

struct LensControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(
            kind: "com.example.factotum.control.lens",
            provider: LensControlProvider()
        ) { value in
            ControlWidgetButton(action: OpenFactotumControlIntent()) {
                Label(
                    value.pending > 0 ? "Lens · \(value.pending) to upload" : "Lens · \(value.analyzed) analyzed",
                    systemImage: "camera.aperture")
            }
        }
        .displayName("Lens Status")
        .description("On-device photo intelligence status.")
    }
}
