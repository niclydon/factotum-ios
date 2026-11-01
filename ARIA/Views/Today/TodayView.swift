import SwiftUI

struct TodayView: View {
    var onOpenReview: () -> Void
    @Environment(TodayStore.self) private var today
    @Environment(DeepLinkManager.self) private var deepLink
    @Environment(ReviewStore.self) private var review
    @State private var showSettings = false
    @State private var updater = UpdateChecker.shared
    @AppStorage("factotum_dismissed_update_version") private var dismissedUpdateVersion = ""
    @State private var showRequiredPrompt = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if case .available(let version) = updater.state, dismissedUpdateVersion != version {
                    UpdateAvailableCard(version: version, notes: updater.availableReleaseNotes) { dismissedUpdateVersion = version }
                }
                if case .required(let minimum) = updater.state {
                    UpdateAvailableCard(version: minimum, required: true, notes: updater.availableReleaseNotes) {}
                }
                OneBigThingCard(state: today.oneBigThing)
                OnThisDayCard()
                ReviewSummaryCard(store: review, onOpen: onOpenReview)
                SleepCard(state: today.sleep)
                ActivityCard(state: today.activity, todayKey: today.todayKey)
                PlacesTimelineCard(state: today.places)
            }
            .padding(16)
        }
        .novaGlassBackdrop()
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }.foregroundStyle(ARIATheme.accent)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onChange(of: deepLink.pendingSettingsPage) { _, page in
            if page != nil { showSettings = true }
        }
        .refreshable { await today.refresh(); await review.load() }
        .task { await today.refreshIfStale(); await review.loadIfStale() }
        .alert("Update required", isPresented: $showRequiredPrompt) {
            Button("Install the update") { openURL(AppConfig.otaInstallURL) }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Nexus needs Factotum \(requiredVersion) or later. Install it from the update page.")
        }
        .onChange(of: updater.state) { _, state in
            if case .required = state { showRequiredPrompt = true }
        }
        .task {
            if case .required = updater.state { showRequiredPrompt = true }
        }
    }

    private var requiredVersion: String {
        if case .required(let v) = updater.state { return v }
        return ""
    }
}

/// Shared card chrome + the three non-loaded states so each card only renders its loaded body.
struct TodayCard<Content: View>: View {
    let title: String
    let icon: String
    let content: () -> Content

    init(title: String, icon: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(ARIATheme.labelCyan)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .novaGlassCard()
    }
}

struct LoadableBody<T: Sendable, Content: View>: View {
    let state: Loadable<T>
    let emptyText: String
    let content: (T) -> Content

    init(state: Loadable<T>, emptyText: String, @ViewBuilder content: @escaping (T) -> Content) {
        self.state = state
        self.emptyText = emptyText
        self.content = content
    }
    var body: some View {
        switch state {
        case .idle, .loading: ProgressView().frame(maxWidth: .infinity)
        case .empty: Text(emptyText).font(.caption).foregroundStyle(ARIATheme.textMuted)
        case .failed(let m): Text("Couldn't load — \(m)").font(.caption).foregroundStyle(ARIATheme.error)
        case .loaded(let v): content(v)
        }
    }
}

/// Launch-visible update prompt (3.3.0). The OTA check has run since 3.2.0
/// but only surfaced as a Settings row; this puts it where the author will see it.
/// Available: a dismissible card, suppressed per version. Required: the card
/// plus an alert (see TodayView).
struct UpdateAvailableCard: View {
    let version: String
    var required: Bool = false
    var notes: String? = nil
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: required ? "exclamationmark.triangle.fill" : "arrow.down.circle.fill")
                .foregroundStyle(required ? ARIATheme.error : ARIATheme.accentGold)
            VStack(alignment: .leading, spacing: 2) {
                Text(required ? "Update required" : "Update available")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(ARIATheme.textPrimary)
                Text("Factotum \(version) is ready to install.")
                    .font(.caption).foregroundStyle(ARIATheme.textSecondary)
                if let notes {
                    Text(notes)
                        .font(.caption).foregroundStyle(ARIATheme.textSecondary)
                        .padding(.top, 2)
                }
            }
            Spacer()
            Link("Install", destination: AppConfig.otaInstallURL)
                .font(.subheadline.weight(.semibold))
            if !required {
                Button { onDismiss() } label: {
                    Image(systemName: "xmark").font(.caption).foregroundStyle(ARIATheme.textMuted)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .novaGlassCard()
    }
}
