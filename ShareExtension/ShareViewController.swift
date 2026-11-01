import UIKit
import Social
import UniformTypeIdentifiers

/// Share Extension that sends shared content to ARIA as a new conversation.
class ShareViewController: UIViewController {

    private var sharedText: String?
    private var sharedURL: String?
    private var sharedImageData: Data?
    private var messageField: UITextView!
    private var sendButton: UIButton!
    private var cancelButton: UIButton!
    private var statusLabel: UILabel!
    private var spinner: UIActivityIndicatorView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 18/255, green: 20/255, blue: 25/255, alpha: 1)
        setupUI()
        extractSharedContent()
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Title bar
        let titleLabel = UILabel()
        titleLabel.text = "Send to Factotum"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Cancel button
        cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.tintColor = UIColor(red: 77/255, green: 232/255, blue: 210/255, alpha: 1)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        // Send button
        sendButton = UIButton(type: .system)
        sendButton.setTitle("Send", for: .normal)
        sendButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        sendButton.tintColor = UIColor(red: 77/255, green: 232/255, blue: 210/255, alpha: 1)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sendButton)

        // Message field
        messageField = UITextView()
        messageField.backgroundColor = UIColor(red: 28/255, green: 31/255, blue: 38/255, alpha: 1)
        messageField.textColor = .white
        messageField.font = .systemFont(ofSize: 15)
        messageField.layer.cornerRadius = 12
        messageField.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        messageField.text = "Send this to Factotum..."
        messageField.textColor = UIColor(white: 0.5, alpha: 1)
        messageField.delegate = self
        messageField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(messageField)

        // Status label
        statusLabel = UILabel()
        statusLabel.textColor = UIColor(white: 0.5, alpha: 1)
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textAlignment = .center
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // Spinner
        spinner = UIActivityIndicatorView(style: .medium)
        spinner.color = UIColor(red: 77/255, green: 232/255, blue: 210/255, alpha: 1)
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            titleLabel.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            sendButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            messageField.topAnchor.constraint(equalTo: cancelButton.bottomAnchor, constant: 16),
            messageField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            messageField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            messageField.heightAnchor.constraint(equalToConstant: 120),

            statusLabel.topAnchor.constraint(equalTo: messageField.bottomAnchor, constant: 12),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            spinner.topAnchor.constraint(equalTo: messageField.bottomAnchor, constant: 12),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    // MARK: - Extract Shared Content

    private func extractSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        for item in items {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    // loadObject (not loadItem, deprecated in iOS 27); its
                    // completion runs off the main actor, so hop before
                    // mutating main-actor-isolated state (Swift 6).
                    _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                        guard let url else { return }
                        Task { @MainActor [weak self] in
                            self?.sharedURL = url.absoluteString
                            self?.updatePreview()
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    _ = provider.loadObject(ofClass: String.self) { [weak self] text, _ in
                        guard let text else { return }
                        Task { @MainActor [weak self] in
                            self?.sharedText = text
                            self?.updatePreview()
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    // Data representation keeps the original bytes (the
                    // pre-4.0 code's preferred path) and avoids the
                    // UIImage bridging overload entirely.
                    _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                        guard let data else { return }
                        Task { @MainActor [weak self] in
                            self?.sharedImageData = data
                            self?.updatePreview()
                        }
                    }
                }
            }
        }
    }

    private func updatePreview() {
        var preview = ""
        if let url = sharedURL { preview += "URL: \(url)\n" }
        if let text = sharedText { preview += text.prefix(200) }
        if sharedImageData != nil { preview += "[Image attached]" }

        if !preview.isEmpty {
            statusLabel.text = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            statusLabel.isHidden = false
        }
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func sendTapped() {
        sendButton.isEnabled = false
        cancelButton.isEnabled = false
        messageField.isEditable = false
        spinner.startAnimating()
        statusLabel.isHidden = true

        Task {
            await sendToARIA()
        }
    }

    private func sendToARIA() async {
        // Build the message content
        var content = ""

        // User's optional note
        let userNote = messageField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !userNote.isEmpty && userNote != "Send this to Factotum..." {
            content += userNote + "\n\n"
        }

        // Shared content
        if let url = sharedURL {
            content += "Shared URL: \(url)\n"
        }
        if let text = sharedText {
            content += text
        }
        if sharedImageData != nil {
            content += "[Image shared — not yet supported in share extension]"
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showError("Nothing to share")
            return
        }

        // Get auth credentials from shared Keychain
        guard let token = KeychainManager.getToken(),
              let serverURL = KeychainManager.getServerURL(),
              !token.isEmpty, !serverURL.isEmpty else {
            showError("Not signed in to Factotum. Open the app first.")
            return
        }

        // POST to /api/chat
        guard let url = URL(string: "\(serverURL)/api/chat") else {
            showError("Invalid server URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = ["content": content]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                showError("Invalid response")
                return
            }

            if http.statusCode == 401 {
                showError("Session expired — open Factotum and sign in again")
                return
            }

            guard (200...299).contains(http.statusCode) else {
                showError("Server error (\(http.statusCode))")
                return
            }

            // Success
            await MainActor.run {
                spinner.stopAnimating()
                statusLabel.text = "Sent to Factotum"
                statusLabel.textColor = UIColor(red: 77/255, green: 232/255, blue: 210/255, alpha: 1)
                statusLabel.isHidden = false
            }

            // Brief delay to show success, then dismiss
            try? await Task.sleep(nanoseconds: 800_000_000)
            extensionContext?.completeRequest(returningItems: nil)

        } catch {
            showError("Failed: \(error.localizedDescription)")
        }
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.spinner.stopAnimating()
            self?.statusLabel.text = message
            self?.statusLabel.textColor = .systemRed
            self?.statusLabel.isHidden = false
            self?.sendButton.isEnabled = true
            self?.cancelButton.isEnabled = true
            self?.messageField.isEditable = true
        }
    }
}

// MARK: - UITextViewDelegate

extension ShareViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.textColor == UIColor(white: 0.5, alpha: 1) {
            textView.text = ""
            textView.textColor = .white
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textView.text = "Send this to Factotum..."
            textView.textColor = UIColor(white: 0.5, alpha: 1)
        }
    }
}
