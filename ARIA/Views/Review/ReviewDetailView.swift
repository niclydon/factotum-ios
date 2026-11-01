import SwiftUI

struct ReviewDetailView: View {
    @Environment(ReviewStore.self) private var store
    @State var card: ReviewCard
    @State private var note = ""
    @State private var selectedValue: String?
    @State private var busy = false
    @State private var inlineMessage: String?
    @State private var receipt: Receipt?
    @FocusState private var noteFocused: Bool

    struct Receipt: Equatable { let label: String; let detail: String; let ok: Bool }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ReviewCard.humanise(card.kind)).font(.caption).foregroundStyle(ARIATheme.textMuted)
                    Text(card.title).font(.title3).fontWeight(.semibold).foregroundStyle(ARIATheme.textPrimary)
                    if let age = RelativeAge.string(fromISO: card.postedAt) {
                        Text("Posted \(age)").font(.caption2).foregroundStyle(ARIATheme.textMuted)
                    }
                }
                Text(Self.markdown(card.body)).foregroundStyle(ARIATheme.textPrimary).textSelection(.enabled)

                if let receipt {
                    receiptStrip(receipt)
                } else if card.isOpen {
                    if let select = card.selects.first {
                        Picker(select.placeholder, selection: $selectedValue) {
                            Text(select.placeholder).tag(String?.none)
                            ForEach(select.options) { Text($0.label).tag(String?.some($0.value)) }
                        }
                        .pickerStyle(.menu).tint(ARIATheme.accent)
                    }
                    ReviewActionButtons(actions: card.actions, disabled: busy) { decide($0.decision) }
                    if let select = card.selects.first, card.actions.isEmpty || select.action != card.actions.first?.decision {
                        Button { decide(select.action) } label: {
                            Text("Confirm selection").frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent).tint(ARIATheme.accent).disabled(busy || selectedValue == nil)
                    }
                    noteField
                    if busy { ProgressView().frame(maxWidth: .infinity) }
                    if let inlineMessage {
                        Text(inlineMessage).font(.caption).foregroundStyle(ARIATheme.error)
                    }
                } else {
                    receiptStrip(Receipt(label: ReviewCard.humanise(card.selectedDecision ?? card.status),
                                         detail: card.decidedOnThisPhone ? "from this phone" : "from Discord", ok: true))
                }
            }
            .padding(20)
        }
        .background(ARIATheme.background)
        .navigationTitle(ReviewCard.domainTitle(card.domain))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Add a note (optional)", text: $note, axis: .vertical)
                .lineLimit(2...6)
                .focused($noteFocused)
                .padding(12)
                .background(ARIATheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ARIATheme.border))
            Text("Required for actions that ask for a name or correction.").font(.caption2).foregroundStyle(ARIATheme.textMuted)
        }
    }

    private func receiptStrip(_ r: Receipt) -> some View {
        HStack(spacing: 8) {
            Image(systemName: r.ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(r.ok ? ARIATheme.success : ARIATheme.error)
            Text("\(r.label) · \(r.detail)").font(.subheadline).foregroundStyle(ARIATheme.textPrimary)
            Spacer()
        }
        .padding(12).background(ARIATheme.surface).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func decide(_ decision: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if card.requiresNote(for: decision), trimmed.isEmpty {
            inlineMessage = card.prompt(for: decision)
            noteFocused = true
            return
        }
        busy = true; inlineMessage = nil
        let values = selectedValue.map { [$0] } ?? []
        Task {
            let outcome = await store.decide(id: card.id, decision: decision, note: trimmed.isEmpty ? nil : trimmed, selectedValues: values)
            busy = false
            switch outcome {
            case .decided(let c):
                card = c
                receipt = Receipt(label: labelFor(decision), detail: "just now · from this phone", ok: true)
            case .conflict(let c):
                card = c
                receipt = Receipt(label: ReviewCard.humanise(c.selectedDecision ?? "Decided"), detail: "Decided in Discord", ok: true)
            case .noteRequired(let prompt):
                inlineMessage = prompt; noteFocused = true
            case .failed(let message):
                inlineMessage = message
            }
        }
    }

    private func labelFor(_ decision: String) -> String {
        card.actions.first(where: { $0.decision == decision })?.label ?? ReviewCard.humanise(decision)
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
