import SwiftUI

struct ContentView: View {
    @State private var response: String = ""
    @State private var isLoading = false
    @State private var questionText = ""
    @State private var showInput = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Quick question button
                    Button {
                        showInput = true
                    } label: {
                        Label("Ask ARIA", systemImage: "mic.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    if isLoading {
                        ProgressView("Thinking...")
                    }

                    if !response.isEmpty {
                        Text(response)
                            .font(.body)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("ARIA")
        }
        .sheet(isPresented: $showInput) {
            DictationInputView { text in
                showInput = false
                Task { await askQuestion(text) }
            }
        }
    }

    private func askQuestion(_ question: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await WatchAPIClient.shared.askQuestion(question)
        } catch {
            response = "Could not reach ARIA."
        }
    }
}

// MARK: - Dictation / Text Input

struct DictationInputView: View {
    let onSubmit: (String) -> Void
    @State private var text = ""

    var body: some View {
        VStack(spacing: 12) {
            TextField("Ask anything...", text: $text)
                .textFieldStyle(.plain)
            Button("Send") {
                onSubmit(text)
            }
            .disabled(text.isEmpty)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
