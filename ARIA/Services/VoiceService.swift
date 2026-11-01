import Foundation
import Speech
import AVFoundation

/// Manages speech recognition and on-device TTS for voice conversations.
@Observable
@MainActor
final class VoiceService: NSObject {

    // MARK: - State

    enum VoiceState: Equatable {
        case idle
        case listening
        case processing
        case speaking
        case muted
    }

    var state: VoiceState = .idle
    var liveTranscript: String = ""
    var error: String?
    var isAuthorizationChecked = false
    var walkieTalkieMode = false

    // MARK: - Private

    private var listeningSession: ListeningSession?
    private var silenceTimer: Timer?
    private var silenceCallback: (() -> Void)?
    private var noSpeechTimer: Timer?
    private let synthesizer = AVSpeechSynthesizer()
    private var speechContinuation: CheckedContinuation<Void, Never>?
    private var stateBeforeMute: VoiceState = .idle

    // MARK: - Authorization

    var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func checkAndRequestAuthorization() {
        isAuthorizationChecked = true
        synthesizer.delegate = self

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor [weak self] in
                    if status != .authorized {
                        self?.error = "Speech recognition permission required"
                    }
                }
            }
        }

        if AVAudioApplication.shared.recordPermission == .undetermined {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor [weak self] in
                    if !granted {
                        self?.error = "Microphone permission required"
                    }
                }
            }
        }
    }

    // MARK: - Mute

    func toggleMute() {
        if state == .muted {
            if stateBeforeMute == .listening {
                state = .idle
                startListening()
            } else {
                state = .idle
            }
        } else if state == .listening {
            stateBeforeMute = .listening
            cancelSilenceTimer()
            cancelNoSpeechTimer()
            listeningSession?.stop()
            listeningSession = nil
            liveTranscript = ""
            state = .muted
        } else if state == .speaking {
            stateBeforeMute = .speaking
            stopSpeaking()
            state = .muted
        } else if state == .idle {
            stateBeforeMute = .idle
            state = .muted
        }
    }

    // MARK: - Listening

    func startListening() {
        guard state == .idle || state == .speaking else { return }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            error = "Speech recognition not authorized. Check Settings > Privacy."
            return
        }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            error = "Microphone not authorized. Check Settings > Privacy."
            return
        }

        stopSpeaking()
        error = nil
        liveTranscript = ""
        state = .listening

        // Start a "no speech detected" timer — if nothing is transcribed in 5 seconds, stop
        startNoSpeechTimer()

        listeningSession = ListeningSession { [weak self] transcript in
            Task { @MainActor [weak self] in
                self?.liveTranscript = transcript
                self?.cancelNoSpeechTimer()
                // Check for conversation-ending phrases
                self?.checkForGoodbye(transcript)
            }
        } onError: { [weak self] message in
            Task { @MainActor [weak self] in
                self?.error = message
                self?.state = .idle
            }
        }

        listeningSession?.start()
    }

    func stopListening() -> String {
        let transcript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

        cancelSilenceTimer()
        cancelNoSpeechTimer()
        listeningSession?.stop()
        listeningSession = nil

        state = transcript.isEmpty ? .idle : .processing
        return transcript
    }

    // MARK: - TTS (On-Device)

    func speak(text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[VoiceService] speak: empty text, skipping")
            state = .idle
            return
        }

        print("[VoiceService] speak: starting TTS for \(text.prefix(50))...")
        state = .speaking

        // Switch audio session to playback mode
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Use playAndRecord with defaultToSpeaker so it works after recording
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("[VoiceService] speak: audio session error: \(error)")
            state = .idle
            return
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.0
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Voice preference: Zoe (premium) first, then NZ/SA/British fallbacks
        let preferredVoiceIDs = [
            // Zoe — best quality US voice
            "com.apple.voice.premium.en-US.Zoe",
            "com.apple.voice.enhanced.en-US.Zoe",
            // New Zealand
            "com.apple.voice.premium.en-NZ.Nicky",
            "com.apple.voice.enhanced.en-NZ.Nicky",
            // South African
            "com.apple.voice.premium.en-ZA.Tessa",
            "com.apple.voice.enhanced.en-ZA.Tessa",
            // British
            "com.apple.voice.premium.en-GB.Stephanie",
            "com.apple.voice.enhanced.en-GB.Stephanie",
            "com.apple.voice.premium.en-GB.Kate",
            "com.apple.voice.enhanced.en-GB.Kate",
        ]
        let selectedVoice = preferredVoiceIDs.lazy.compactMap { AVSpeechSynthesisVoice(identifier: $0) }.first
        utterance.voice = selectedVoice ?? AVSpeechSynthesisVoice(language: "en-US")
        print("[VoiceService] speak: using voice \(utterance.voice?.name ?? "default")")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            speechContinuation = continuation
            synthesizer.speak(utterance)
        }
        print("[VoiceService] speak: finished")
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if let cont = speechContinuation {
            speechContinuation = nil
            cont.resume()
        }
        if state == .speaking { state = .idle }
    }

    // MARK: - Silence Detection (user stopped talking)

    func resetSilenceTimer(onSilence: @escaping () -> Void) {
        silenceTimer?.invalidate()
        silenceCallback = onSilence
        guard !liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.silenceCallback?()
                self?.silenceCallback = nil
            }
        }
    }

    func cancelSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        silenceCallback = nil
    }

    // MARK: - Goodbye Detection

    /// If the user says a clear conversation-ending phrase, stop immediately.
    var didDetectGoodbye = false

    private static let goodbyePhrases = [
        "goodbye", "good bye", "bye bye", "bye aria", "bye for now",
        "talk to you later", "talk later", "see you later", "see ya",
        "farewell", "take care", "that's all", "that is all",
        "i'm done", "im done", "we're done", "end conversation",
        "stop listening", "close voice", "exit voice",
        "good night", "goodnight", "night night",
    ]

    private func checkForGoodbye(_ transcript: String) {
        let lower = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isGoodbye = Self.goodbyePhrases.contains { lower.hasSuffix($0) || lower == $0 }
        if isGoodbye {
            didDetectGoodbye = true
            cancelSilenceTimer()
            cancelNoSpeechTimer()
            // Stop listening immediately
            listeningSession?.stop()
            listeningSession = nil
            state = .idle
            liveTranscript = ""
        }
    }

    // MARK: - No Speech Detection (user never started talking)

    private func startNoSpeechTimer() {
        noSpeechTimer?.invalidate()
        noSpeechTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state == .listening,
                      self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                // No speech detected — go back to idle
                self.listeningSession?.stop()
                self.listeningSession = nil
                self.state = .idle
            }
        }
    }

    private func cancelNoSpeechTimer() {
        noSpeechTimer?.invalidate()
        noSpeechTimer = nil
    }

    func interrupt() {
        cancelSilenceTimer()
        cancelNoSpeechTimer()
        stopSpeaking()
        listeningSession?.stop()
        listeningSession = nil
        state = .idle
        liveTranscript = ""
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceService: @preconcurrency AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("[VoiceService] TTS didStart speaking")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("[VoiceService] TTS didFinish")
        if let cont = speechContinuation {
            speechContinuation = nil
            cont.resume()
        }
        state = .idle
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("[VoiceService] TTS didCancel")
        if let cont = speechContinuation {
            speechContinuation = nil
            cont.resume()
        }
        state = .idle
    }
}

// MARK: - ListeningSession (nonisolated, owns audio engine)

private final class ListeningSession: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let onTranscript: @Sendable (String) -> Void
    private let onError: @Sendable (String) -> Void
    private var isStarted = false

    init(onTranscript: @escaping @Sendable (String) -> Void, onError: @escaping @Sendable (String) -> Void) {
        self.onTranscript = onTranscript
        self.onError = onError
    }

    func start() {
        DispatchQueue.global(qos: .userInteractive).async { [self] in
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                onError("Audio session error: \(error.localizedDescription)")
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            self.recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            // NOTE (4.0 step-zero, verified against the iOS 27.1 SDK):
            // this installTap form is deprecated in iOS 27 in favor of
            // the error-reporting variant, but that variant is marked
            // NS_REFINED_FOR_SWIFT with no Swift overlay shipped in the
            // 27.1 SDK, so Swift cannot call it yet. The deprecated form
            // is the only callable one; revisit when an SDK ships the
            // overlay. (One of four documented warning exceptions.)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            self.recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                if let result {
                    self?.onTranscript(result.bestTranscription.formattedString)
                }
                if let error, (error as NSError).code != 216 {
                    self?.onError(error.localizedDescription)
                }
            }

            do {
                audioEngine.prepare()
                try audioEngine.start()
                isStarted = true
            } catch {
                onError("Could not start audio: \(error.localizedDescription)")
                inputNode.removeTap(onBus: 0)
            }
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }
}
