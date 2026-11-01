import SwiftUI

/// Full-screen voice conversation mode with animated orb button.
struct VoiceSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveLayout) private var layout
    @State private var voiceService = VoiceService()
    @Bindable var vm: ChatViewModel

    @State private var lastSpokenMessageId: String?
    @State private var showTranscript = true
    @State private var isHoldingOrb = false

    var body: some View {
        ZStack {
            ARIATheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if layout.isRegular && layout.isLandscape {
                    // iPad landscape: transcript left, orb right
                    HStack(spacing: 0) {
                        if showTranscript {
                            transcript
                                .frame(maxHeight: .infinity)
                        }

                        VStack {
                            Spacer()
                            liveTranscriptOverlay
                            errorOverlay
                            statusText
                            orbButton
                                .padding(.bottom, 16)
                            HStack(spacing: 20) {
                                muteButton
                                modeToggle
                            }
                            .padding(.bottom, 24)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    // Portrait / iPhone: stacked layout
                    if showTranscript {
                        transcript
                    }

                    Spacer()
                    liveTranscriptOverlay
                    errorOverlay
                    statusText
                    orbButton
                        .padding(.bottom, 16)

                    HStack(spacing: 20) {
                        muteButton
                        modeToggle
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: voiceService.state)
        .onAppear {
            voiceService.checkAndRequestAuthorization()
        }
        // Auto-stop listening after silence (only in normal mode)
        .onChange(of: voiceService.liveTranscript) {
            guard !voiceService.walkieTalkieMode else { return }
            let service = voiceService
            service.resetSilenceTimer {
                guard service.state == .listening else { return }
                let transcript = voiceService.stopListening()
                guard !transcript.isEmpty else {
                    voiceService.state = .idle
                    return
                }
                Task {
                    await sendVoiceMessage(transcript)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Close") {
                voiceService.interrupt()
                dismiss()
            }
            .font(.system(size: layout.fontBody))
            .foregroundStyle(ARIATheme.textSecondary)

            Spacer()

            Text("Voice Mode")
                .font(layout.adaptiveTitleFont)
                .foregroundStyle(ARIATheme.textPrimary)

            Spacer()

            Button {
                showTranscript.toggle()
            } label: {
                Image(systemName: showTranscript ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: layout.sized(phone: 18, pad: 22)))
                    .foregroundStyle(ARIATheme.textSecondary)
            }
        }
        .padding(.horizontal, layout.screenPadding)
        .padding(.vertical, 12)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(vm.messages, id: \.id) { message in
                        MessageBubbleView(message: message, photos: vm.messagePhotos[message.id] ?? [])
                            .id(message.id)
                    }
                }
                .padding(.horizontal, layout.screenPadding)
                .padding(.vertical, 8)
            }
            .onChange(of: vm.messages.count) {
                withAnimation {
                    proxy.scrollTo(vm.messages.last?.id, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: layout.isRegular ? 500 : 300)
    }

    // MARK: - Overlays

    @ViewBuilder
    private var liveTranscriptOverlay: some View {
        if voiceService.state == .listening && !voiceService.liveTranscript.isEmpty {
            Text(voiceService.liveTranscript)
                .font(layout.adaptiveBodyFont)
                .foregroundStyle(ARIATheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var errorOverlay: some View {
        if let error = voiceService.error {
            Text(error)
                .font(layout.adaptiveCaptionFont)
                .foregroundStyle(ARIATheme.error)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Status Text

    private var statusText: some View {
        Group {
            switch voiceService.state {
            case .idle:
                Text(voiceService.walkieTalkieMode ? "Hold to talk" : "Tap to talk")
                    .foregroundStyle(ARIATheme.textMuted)
            case .listening:
                Text("Listening...")
                    .foregroundStyle(Color.green)
            case .processing:
                Text("Thinking...")
                    .foregroundStyle(ARIATheme.accentCyan)
            case .speaking:
                Text("ARIA is speaking")
                    .foregroundStyle(ARIATheme.accent)
            case .muted:
                Text("Muted")
                    .foregroundStyle(Color.red)
            }
        }
        .font(.system(size: layout.fontCaption, weight: .medium))
        .padding(.bottom, 16)
    }

    // MARK: - Orb Button

    private var orbButton: some View {
        let shouldPulse = voiceService.state == .listening
            || voiceService.state == .speaking
            || voiceService.state == .processing
            || voiceService.state == .muted

        let glowColor: Color = switch voiceService.state {
        case .idle: Color.clear
        case .listening: Color.green
        case .processing: ARIATheme.accentCyan
        case .speaking: ARIATheme.accent
        case .muted: Color.red
        }

        let orbSize: CGFloat = voiceService.walkieTalkieMode ? layout.orbSizeWalkie : layout.orbSize
        let glowSize: CGFloat = orbSize * 1.4

        return ZStack {
            // Glow — only visible when active
            if shouldPulse {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glowColor.opacity(0.4), glowColor.opacity(0)],
                            center: .center,
                            startRadius: orbSize * 0.4,
                            endRadius: glowSize * 0.55
                        )
                    )
                    .frame(width: glowSize, height: glowSize)
                    .scaleEffect(shouldPulse ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: shouldPulse)
            }

            Circle()
                .stroke(shouldPulse ? glowColor.opacity(0.6) : ARIATheme.textMuted.opacity(0.2), lineWidth: shouldPulse ? 3 : 1)
                .frame(width: orbSize, height: orbSize)

            Image("ARIAProfile")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: orbSize - 10, height: orbSize - 10)
                .clipShape(Circle())
                .opacity(voiceService.state == .speaking ? 0.9 : 0.4)

            if voiceService.state != .speaking {
                Image(systemName: voiceService.state == .listening ? "waveform" : "mic.fill")
                    .font(.system(size: orbSize * 0.27, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
        }
        .contentShape(Circle())
        .gesture(
            voiceService.walkieTalkieMode
                ? AnyGesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isHoldingOrb {
                            isHoldingOrb = true
                            voiceService.startListening()
                        }
                    }
                    .onEnded { _ in
                        isHoldingOrb = false
                        let transcript = voiceService.stopListening()
                        guard !transcript.isEmpty else {
                            voiceService.state = .idle
                            return
                        }
                        Task { await sendVoiceMessage(transcript) }
                    }
                    .map { _ in () })
                : AnyGesture(TapGesture()
                    .map { _ in () }
                    .onEnded { handleOrbTap() })
        )
    }

    // MARK: - Mute Button

    private var muteButton: some View {
        Button {
            voiceService.toggleMute()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: voiceService.state == .muted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: layout.sized(phone: 14, pad: 16)))
                Text(voiceService.state == .muted ? "Unmute" : "Mute")
                    .font(.system(size: layout.sized(phone: 12, pad: 14), weight: .medium))
            }
            .foregroundStyle(voiceService.state == .muted ? Color.red : ARIATheme.textSecondary)
            .padding(.horizontal, layout.sized(phone: 14, pad: 18))
            .padding(.vertical, layout.sized(phone: 8, pad: 10))
            .background(voiceService.state == .muted ? Color.red.opacity(0.15) : ARIATheme.surface)
            .clipShape(Capsule())
        }
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        Button {
            voiceService.walkieTalkieMode.toggle()
            if voiceService.state == .listening {
                voiceService.cancelSilenceTimer()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: voiceService.walkieTalkieMode ? "waveform.circle.fill" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: layout.sized(phone: 12, pad: 14)))
                Text(voiceService.walkieTalkieMode ? "Switch to Auto" : "Switch to Walkie-Talkie")
                    .font(.system(size: layout.sized(phone: 12, pad: 14), weight: .medium))
            }
            .foregroundStyle(ARIATheme.textSecondary)
            .padding(.horizontal, layout.sized(phone: 14, pad: 18))
            .padding(.vertical, layout.sized(phone: 8, pad: 10))
            .background(ARIATheme.surface)
            .clipShape(Capsule())
        }
    }

    // MARK: - Actions

    private func handleOrbTap() {
        switch voiceService.state {
        case .idle:
            voiceService.startListening()

        case .listening:
            voiceService.cancelSilenceTimer()
            let transcript = voiceService.stopListening()
            guard !transcript.isEmpty else {
                voiceService.state = .idle
                return
            }
            Task { await sendVoiceMessage(transcript) }

        case .processing:
            break

        case .speaking:
            voiceService.stopSpeaking()

        case .muted:
            voiceService.toggleMute()
        }
    }

    private func sendVoiceMessage(_ text: String) async {
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            conversationId: vm.currentConversation?.id ?? "",
            role: "user",
            content: text
        )
        vm.messages.append(userMessage)

        await vm.sendVoiceMessage(text)

        // Speak the response
        if let lastAssistant = vm.messages.last(where: { $0.role == "assistant" }),
           lastAssistant.id != lastSpokenMessageId {
            lastSpokenMessageId = lastAssistant.id
            await voiceService.speak(text: lastAssistant.content)
        }

        // Ensure we're back to idle
        if voiceService.state != .idle {
            voiceService.state = .idle
        }

        // Auto-resume listening in normal mode (not walkie-talkie), unless goodbye detected
        if !voiceService.walkieTalkieMode && !voiceService.didDetectGoodbye {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if voiceService.state == .idle {
                voiceService.startListening()
            }
        }
    }
}
