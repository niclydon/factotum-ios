import SwiftUI

/// The Command Line "ask anything" surface — a read-only natural-language query over your whole
/// Nexus. Type a question; ARIA grounds an answer in your corpus (messages, emails, events, notes).
/// Nothing here can write or send — it's read-only by construction on the backend.
struct AskView: View {
    @State private var query = ""
    @State private var answer: AttributedString?
    @State private var consulted: [String] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var lastQuestion = ""
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "What's coming up this week?",
        "Who have I been in touch with lately?",
        "Summarize my recent emails",
        "What did I last discuss with a friend?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if loading {
                        HStack(spacing: 10) {
                            ProgressView().tint(ARIATheme.accent)
                            Text("Searching your Nexus…").foregroundStyle(ARIATheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)
                    } else if let answer {
                        if !lastQuestion.isEmpty {
                            Text(lastQuestion).font(.headline).foregroundStyle(ARIATheme.textPrimary)
                        }
                        Text(answer).foregroundStyle(ARIATheme.textPrimary).textSelection(.enabled)
                        if !consulted.isEmpty {
                            Text("consulted: " + consulted.joined(separator: ", "))
                                .font(.caption2).foregroundStyle(ARIATheme.textSecondary)
                        }
                    } else if let errorText {
                        Text(errorText).foregroundStyle(ARIATheme.error)
                    } else {
                        emptyState
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            inputBar
        }
        .background(ARIATheme.background)
        .navigationTitle("Ask")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.largeTitle).foregroundStyle(ARIATheme.accent)
            Text("Ask anything about your Nexus")
                .font(.title3).fontWeight(.semibold).foregroundStyle(ARIATheme.textPrimary)
            Text("Your messages, emails, events, and notes — grounded answers, read-only. ARIA can't change anything from here.")
                .font(.subheadline).foregroundStyle(ARIATheme.textSecondary)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        query = s
                        inputFocused = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right").font(.caption2)
                            Text(s).font(.subheadline)
                        }
                        .foregroundStyle(ARIATheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(.top, 24)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask your Nexus anything…", text: $query, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(12)
                .background(ARIATheme.background)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ARIATheme.textSecondary.opacity(0.3)))
                .submitLabel(.send)
            Button {
                Task { await ask() }
            } label: {
                if loading {
                    ProgressView().tint(ARIATheme.accent)
                } else {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
            }
            .foregroundStyle(ARIATheme.accent)
            .disabled(loading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private func ask() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !loading else { return }
        loading = true
        errorText = nil
        inputFocused = false
        lastQuestion = q
        do {
            let resp = try await APIClient.shared.commandAsk(query: q)
            answer = (try? AttributedString(markdown: resp.answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(resp.answer)
            consulted = resp.toolCalls.filter { $0.ok }.map(\.tool)
            query = ""
        } catch {
            errorText = "Couldn't reach ARIA — \(error.localizedDescription)"
        }
        loading = false
    }
}
