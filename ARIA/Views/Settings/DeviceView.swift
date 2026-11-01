import SwiftUI

/// Settings → This Device. The phone's own citizenship record: what it
/// is, what it's running, how it was installed, when its provisioning
/// profile dies, and whether Nexus knows it exists (Phase 2).
struct DeviceView: View {
    @State private var registrar = DeviceRegistrationService.shared
    @State private var push = PushNotificationService.shared

    var body: some View {
        List {
            Section("Device") {
                LabeledContent("Name") { Text(UIDevice.current.name) }
                LabeledContent("Model") { Text(DeviceRegistrationService.modelIdentifier) }
                LabeledContent("System") { Text("iOS \(UIDevice.current.systemVersion)") }
                LabeledContent("Identifier") {
                    Text(UIDevice.current.identifierForVendor?.uuidString ?? "—")
                        .font(.caption).lineLimit(1).truncationMode(.middle)
                }
            }
            .listRowBackground(ARIATheme.surface)

            Section("App") {
                LabeledContent("Version") { Text("\(AppConfig.appVersion) (\(AppConfig.appBuild))") }
                LabeledContent("Bundle ID") { Text(AppConfig.bundleID).font(.caption) }
            }
            .listRowBackground(ARIATheme.surface)

            Section("Distribution") {
                LabeledContent("Channel") { Text(channelLabel) }
                if let name = DeviceRegistrationService.profileName {
                    LabeledContent("Profile") { Text(name).font(.caption).lineLimit(1) }
                }
                if let expiry = DeviceRegistrationService.profileExpiration {
                    LabeledContent("Profile expires") {
                        Text(expiry, format: .dateTime.month().day().year())
                    }
                    LabeledContent("Time left") {
                        Text(timeLeft(expiry))
                            .foregroundStyle(daysLeft(expiry) < 60 ? ARIATheme.accentGold : ARIATheme.textSecondary)
                    }
                } else {
                    LabeledContent("Profile expires") { Text("—") }
                }
            }
            .listRowBackground(ARIATheme.surface)

            Section("Push") {
                LabeledContent("Token registered") { Text(push.deviceToken != nil ? "Yes" : "No") }
                LabeledContent("Notifications") { Text(push.isEnabled ? "Enabled" : "Disabled") }
            }
            .listRowBackground(ARIATheme.surface)

            Section {
                LabeledContent("Status") { Text(registrationStatus) }
                if let last = registrar.lastRegisteredAt {
                    LabeledContent("Last registered") {
                        Text(RelativeDateTimeFormatter().localizedString(for: last, relativeTo: Date()))
                    }
                }
                Button {
                    Task { await registrar.registerNow() }
                } label: {
                    HStack {
                        Text(registrar.isRegistering ? "Registering…" : "Register with Nexus now")
                        if registrar.isRegistering { Spacer(); ProgressView() }
                    }
                }
                .disabled(registrar.isRegistering)
            } header: {
                Text("Nexus Registration")
            } footer: {
                Text("Factotum Phase 2: the phone registers itself in Nexus like the Macs do. If the registration endpoint isn't live yet, this shows as pending and retries on its own.")
            }
            .listRowBackground(ARIATheme.surface)
        }
        .scrollContentBackground(.hidden).background(ARIATheme.background)
        .navigationTitle("This Device")
    }

    private var channelLabel: String {
        switch DeviceRegistrationService.distribution {
        case "adhoc": return "Ad Hoc (OTA page)"
        case "development": return "Development"
        case "testflight": return "TestFlight"
        case "app-store": return "App Store"
        default: return DeviceRegistrationService.distribution
        }
    }

    private func daysLeft(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
    }

    private func timeLeft(_ date: Date) -> String {
        let days = daysLeft(date)
        if days < 0 { return "expired" }
        if days == 0 { return "today" }
        return "\(days) days"
    }

    private var registrationStatus: String {
        switch registrar.state {
        case .unknown: return "Not registered yet"
        case .registered: return "Registered"
        case .pendingEndpoint: return "Pending — Nexus endpoint not live yet"
        case .failed(let message): return "Failed: \(message)"
        }
    }
}
