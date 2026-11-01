import SwiftUI

/// Life Replay tab (Factotum 4.0 W1): scrub a day's evidence pack across
/// seven families, and ask questions whose narratives cite pack items.
/// Citations render as [n] markers matching the numbered citation list —
/// every number resolves to a real pack item returned by the server.
struct ReplayView: View {
    @Environment(DeepLinkManager.self) private var deepLink
    @State private var store = ReplayStore.shared
    @State private var pickerDate = Calendar.current.startOfDay(for: Date())
    @State private var question = ""

    var body: some View {
        List {
            Section {
                HStack {
                    Button { Task { await store.shift(days: -1) } } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    DatePicker("Day", selection: $pickerDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: pickerDate) { _, newValue in
                            Task { await store.select(date: newValue) }
                        }
                    Spacer()
                    Button { Task { await store.shift(days: 1) } } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(Calendar.current.isDateInToday(store.selectedDate))
                }
            }

            packSection
            askSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ARIATheme.background)
        .navigationTitle("Replay")
        .task {
            if case .idle = store.pack {
                pickerDate = store.selectedDate
                await store.load()
            }
        }
        .onChange(of: store.selectedDate) { _, newValue in
            if pickerDate != newValue { pickerDate = newValue }
        }
        .onChange(of: deepLink.pendingReplayDateString) { _, dateString in
            consumePendingDate(dateString)
        }
    }

    /// A Show My Day intent or Spotlight tap left a date to open.
    private func consumePendingDate(_ dateString: String?) {
        guard let dateString else { return }
        deepLink.pendingReplayDateString = nil
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "America/New_York")
        parser.dateFormat = "yyyy-MM-dd"
        if let date = parser.date(from: dateString) {
            pickerDate = date
            Task { await store.select(date: date) }
        }
    }

    // MARK: - Evidence pack

    @ViewBuilder
    private var packSection: some View {
        switch store.pack {
        case .idle, .loading:
            Section {
                HStack { ProgressView(); Text("Assembling the day…") }
                    .foregroundStyle(ARIATheme.textSecondary)
            }
        case .failed(let message):
            Section {
                Text(message).foregroundStyle(.red)
                Button("Retry") { Task { await store.load() } }
            }
        case .empty:
            Section { Text("Nothing recorded this day.").foregroundStyle(ARIATheme.textSecondary) }
        case .loaded(let pack):
            Section {
                LabeledContent("Evidence items", value: "\(pack.itemCount)")
                ForEach(pack.dataNotes, id: \.self) { note in
                    Text(note).font(.caption).foregroundStyle(ARIATheme.textMuted)
                }
            }
            ForEach(pack.orderedFamilies, id: \.key) { entry in
                if entry.family.count > 0 {
                    Section {
                        ForEach(entry.family.items) { item in
                            ReplayItemRow(item: item)
                        }
                        if entry.family.truncated {
                            Text("Truncated at the family cap.")
                                .font(.caption).foregroundStyle(ARIATheme.textMuted)
                        }
                    } header: {
                        Label(Self.familyLabel(entry.key), systemImage: Self.familyIcon(entry.key))
                    }
                }
            }
        }
    }

    // MARK: - Ask

    @ViewBuilder
    private var askSection: some View {
        Section("Ask about this period") {
            Picker("Scope", selection: $store.askScope) {
                ForEach(ReplayStore.AskScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                TextField("What happened…", text: $question)
                Button("Ask") {
                    Task { await store.ask(question: question) }
                }
                .disabled(store.isAsking || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if store.isAsking {
                HStack { ProgressView(); Text("ARiA is replaying…") }
                    .foregroundStyle(ARIATheme.textSecondary)
            }
            if let error = store.askError {
                Text(error).foregroundStyle(.red)
            }
            if let response = store.askResponse {
                Text(Self.displayNarrative(response))
                    .foregroundStyle(ARIATheme.textPrimary)
                if !response.unresolvedCitations.isEmpty {
                    Text("\(response.unresolvedCitations.count) citation(s) did not resolve and were removed.")
                        .font(.caption).foregroundStyle(ARIATheme.textMuted)
                }
            }
        }
        if let response = store.askResponse, !response.citations.isEmpty {
            Section("Citations") {
                ForEach(Array(response.citations.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("[\(index + 1)]")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ARIATheme.textSecondary)
                        ReplayItemRow(item: item)
                    }
                }
            }
        }
    }

    /// Replace [cite:<id>] markers with [n] numbers matching the citations
    /// list order; unknown markers (should not survive the server) drop out.
    static func displayNarrative(_ response: ReplayAskResponse) -> String {
        var result = response.narrative
        for (index, item) in response.citations.enumerated() {
            result = result.replacingOccurrences(of: "[cite:\(item.id)]", with: "[\(index + 1)]")
        }
        while let range = result.range(of: #"\[cite:[^\]]+\]"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result
    }

    static func familyLabel(_ key: String) -> String {
        switch key {
        case "timeline": return "Timeline"
        case "visits": return "Visits"
        case "health": return "Health"
        case "workouts": return "Workouts"
        case "music": return "Music"
        case "looki": return "Looki Moments"
        case "photos": return "Photos"
        default: return key.capitalized
        }
    }

    static func familyIcon(_ key: String) -> String {
        switch key {
        case "timeline": return "calendar"
        case "visits": return "mappin.and.ellipse"
        case "health": return "heart.fill"
        case "workouts": return "figure.run"
        case "music": return "music.note"
        case "looki": return "camera.viewfinder"
        case "photos": return "photo"
        default: return "doc.text"
        }
    }
}

/// One evidence item: time + summary, with its detail fields as a caption.
struct ReplayItemRow: View {
    let item: ReplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(Self.timeLabel(item.timestamp))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ARIATheme.textSecondary)
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(ARIATheme.textPrimary)
            }
            if !item.fields.isEmpty {
                Text(item.fields.sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value.display)" }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(ARIATheme.textMuted)
                    .lineLimit(2)
            }
        }
    }

    /// Day-granular items (sleep, activity) carry a T12:00:00Z noon marker;
    /// those show no clock time.
    static func timeLabel(_ iso: String) -> String {
        if iso.hasSuffix("T12:00:00Z") || iso.hasSuffix("T12:00:00.000Z") { return "Day" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
