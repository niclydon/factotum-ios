import SwiftUI

struct ReviewListView: View {
    @Environment(ReviewStore.self) private var store
    @State private var mode: Mode = .open
    enum Mode: String, CaseIterable { case open = "Open", recent = "Recent" }

    var body: some View {
        Group {
            if mode == .open { openList } else { recentList }
        }
        .background(ARIATheme.background)
        .navigationTitle("Review")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) } }
                    .pickerStyle(.segmented).frame(width: 180)
            }
        }
        .refreshable { await store.load() }
        .task { await store.loadIfStale() }
    }

    @ViewBuilder private var openList: some View {
        if store.open.isEmpty {
            emptyOrError(empty: "Nothing to review", icon: "checkmark.circle")
        } else {
            List {
                ForEach(store.openByDomain, id: \.domain) { group in
                    Section {
                        ForEach(group.cards) { card in
                            NavigationLink(value: card) { ReviewRowView(card: card) }
                                .listRowBackground(ARIATheme.background)
                        }
                    } header: {
                        HStack {
                            Text(ReviewCard.domainTitle(group.domain).uppercased()).foregroundStyle(ARIATheme.textSecondary)
                            Spacer()
                            Text("\(group.cards.count)").foregroundStyle(ARIATheme.accent)
                        }
                        .font(.caption).fontWeight(.semibold)
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private var recentList: some View {
        if store.recent.isEmpty {
            emptyOrError(empty: "No recent decisions", icon: "clock")
        } else {
            List(store.recent) { card in
                NavigationLink(value: card) { ReviewRowView(card: card) }
                    .listRowBackground(ARIATheme.background)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private func emptyOrError(empty: String, icon: String) -> some View {
        if store.isLoading && store.lastLoadedAt == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = store.lastError, store.lastLoadedAt == nil {
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(ARIATheme.error)
                Text("Couldn't load review cards").foregroundStyle(ARIATheme.textPrimary)
                Text(err).font(.caption).foregroundStyle(ARIATheme.textSecondary).multilineTextAlignment(.center).padding(.horizontal)
                Button { Task { await store.load() } } label: { Label("Retry", systemImage: "arrow.clockwise") }.buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.largeTitle).foregroundStyle(ARIATheme.textSecondary)
                Text(empty).foregroundStyle(ARIATheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ReviewRowView: View {
    let card: ReviewCard
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.title).font(.subheadline).fontWeight(.semibold).foregroundStyle(ARIATheme.textPrimary).lineLimit(1)
                Spacer()
                if card.isOpen {
                    Text("\(card.actions.count)").font(.caption2).fontWeight(.bold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(ARIATheme.accent.opacity(0.2)).foregroundStyle(ARIATheme.accent).clipShape(Capsule())
                } else if let d = card.selectedDecision {
                    Label(ReviewCard.humanise(d), systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(ARIATheme.success)
                }
            }
            Text(card.body).font(.caption).foregroundStyle(ARIATheme.textSecondary).lineLimit(2)
            if let age = RelativeAge.string(fromISO: card.isOpen ? card.postedAt : card.decidedAt) {
                Text(age).font(.caption2).foregroundStyle(ARIATheme.textMuted)
            }
        }
        .padding(.vertical, 6)
    }
}

/// ISO-8601 parsing + relative age. Formatters are built per call: ISO8601DateFormatter is not
/// Sendable, so a shared static instance is rejected under Swift 6 strict concurrency.
enum RelativeAge {
    /// Accepts both fractional-second and whole-second ISO strings (Postgres ::text emits either).
    static func parse(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: iso) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: iso)
    }

    /// "3h ago" from an ISO-8601 string; nil when unparseable.
    static func string(fromISO iso: String?) -> String? {
        guard let date = parse(iso) else { return nil }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
