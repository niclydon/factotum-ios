import SwiftUI

struct ChatView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(PushNotificationService.self) private var pushService
    @Environment(DeepLinkManager.self) private var deepLink
    @Environment(\.adaptiveLayout) private var layout
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var vm = ChatViewModel()
    @State private var showSettings = false
    @State private var showSyncFreshness = false
    @State private var showVoiceMode = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    /// The persona slug for the current conversation, defaulting to nil (shows standard ARIA profile).
    private var currentPersonaSlug: String? {
        vm.currentConversation?.personaSlug
    }

    /// Maps a persona slug to an asset catalog image name, falling back to "ARIAProfile".
    private func personaAvatarName(for slug: String?) -> String {
        guard let slug = slug else { return "ARIAProfile" }
        let parts = slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return "PersonaAvatar" + parts.joined()
    }

    var body: some View {
        Group {
            if hSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showSyncFreshness) {
            NavigationStack { DataSourcesView() }
        }
        .fullScreenCover(isPresented: $showVoiceMode) {
            VoiceSessionView(vm: vm)
        }
        .task {
            await vm.loadConversations()
        }
        .onChange(of: pushService.pendingConversationId) { _, id in
            guard let id else { return }
            pushService.pendingConversationId = nil
            Task { await navigateToConversation(id: id) }
        }
        .onChange(of: deepLink.pendingConversationId) { _, id in
            guard let id else { return }
            deepLink.pendingConversationId = nil
            Task { await navigateToConversation(id: id) }
        }
        .onChange(of: deepLink.pendingPrompt) { _, prompt in
            guard let prompt else { return }
            deepLink.pendingPrompt = nil
            vm.newConversation()
            vm.inputText = prompt
        }
        .onChange(of: deepLink.pendingRoute) { _, route in
            guard let route else { return }
            deepLink.pendingRoute = nil
            switch route {
            case .pushSettings:
                showSettings = true
            case .dataSources:
                showSyncFreshness = true
            }
        }
        .onChange(of: pushService.pendingPIEInsight?.conversationId) { _, id in
            guard let insight = pushService.pendingPIEInsight else { return }
            pushService.pendingPIEInsight = nil
            Task { await handlePIEInsightTap(insight) }
        }
    }

    // MARK: - iPad Layout (NavigationSplitView)

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } detail: {
            chatContent
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - iPhone Layout (overlay sidebar)

    private var iPhoneLayout: some View {
        ZStack {
            ARIATheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                chatHeader
                Divider().overlay(ARIATheme.border)
                chatContent
            }

            if vm.showSidebar {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { vm.showSidebar = false }

                HStack {
                    sidebarContent
                        .frame(width: layout.sidebarWidth)
                        .background(ARIATheme.surface)
                    Spacer()
                }
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.showSidebar)
    }

    // MARK: - Sidebar Content (shared)

    private var sidebarContent: some View {
        // Phase-5 single-thread model means there's nothing meaningful to
        // pick between in a "conversations list" — instead, the sidebar
        // surfaces the model picker (mirrors Desk's UX) and the inbox
        // shortcut. (The old ConversationListView was removed in OB-52318.)
        ModelPickerView(
            models: vm.availableModels,
            selectedModel: vm.selectedModel,
            isLoading: vm.availableModels.isEmpty,
            onSelectModel: { id in
                vm.selectedModel = id
                vm.showSidebar = false
            },
            onClearChat: { vm.newConversation() }
        )
        .task { await vm.loadAvailableModels() }
    }

    // MARK: - Chat Content (shared)

    private var chatContent: some View {
        VStack(spacing: 0) {
            if hSizeClass == .regular {
                iPadChatHeader
                Divider().overlay(ARIATheme.border)
            }

            messageList

            if vm.isStreaming {
                streamingIndicator
            }

            if let error = vm.error {
                errorBanner(error)
            }

            Divider().overlay(ARIATheme.border)

            MessageInputView(
                text: $vm.inputText,
                isStreaming: vm.isStreaming,
                onSend: { Task { await vm.send() } },
                onVoiceTap: { showVoiceMode = true }
            )
            .frame(maxWidth: layout.isRegular ? 800 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .background(ARIATheme.background)
    }

    // MARK: - iPhone Header

    private var chatHeader: some View {
        HStack {
            Button { vm.showSidebar.toggle() } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 20))
                    .foregroundStyle(ARIATheme.textSecondary)
            }
            Spacer()
            headerTitle
            Spacer()
            headerMenu
        }
        .padding(.horizontal, layout.screenPadding)
        .padding(.vertical, 12)
    }

    // MARK: - iPad Header

    private var iPadChatHeader: some View {
        HStack {
            headerTitle
            Spacer()
            headerMenu
        }
        .padding(.horizontal, layout.screenPadding)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var headerTitle: some View {
        if vm.currentConversation == nil {
            HStack(spacing: 6) {
                Image(personaAvatarName(for: currentPersonaSlug))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: layout.profileImageChat, height: layout.profileImageChat)
                    .clipShape(Circle())
                Text("ARIA")
                    .font(layout.adaptiveTitleFont)
                    .foregroundStyle(ARIATheme.textPrimary)
            }
        } else {
            Text(TextSanitizer.sanitize(vm.currentConversation?.title ?? "ARIA"))
                .font(layout.adaptiveTitleFont)
                .foregroundStyle(ARIATheme.textPrimary)
                .lineLimit(1)
        }
    }

    private var headerMenu: some View {
        Menu {
            Button("Settings", systemImage: "gearshape") { showSettings = true }
            Button("Sign Out", systemImage: "arrow.right.square", role: .destructive) { auth.logout() }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20))
                .foregroundStyle(ARIATheme.textSecondary)
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if vm.messages.isEmpty && !vm.isStreaming {
                        emptyState
                    }

                    ForEach(vm.messages, id: \.id) { message in
                        MessageBubbleView(
                            message: message,
                            photos: vm.messagePhotos[message.id] ?? [],
                            personaSlug: currentPersonaSlug,
                            model: vm.messageModels[message.id],
                        )
                        .id(message.id)
                    }

                    if !vm.streamingText.isEmpty {
                        MessageBubbleView(
                            message: ChatMessage(
                                id: "streaming",
                                conversationId: "",
                                role: "assistant",
                                content: vm.streamingText
                            ),
                            isStreaming: true,
                            personaSlug: currentPersonaSlug
                        )
                        .id("streaming")
                    }
                }
                .padding(.horizontal, layout.screenPadding)
                .padding(.vertical, 8)
                .frame(maxWidth: layout.isRegular ? 900 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.messages.count) {
                withAnimation {
                    proxy.scrollTo(vm.messages.last?.id ?? "streaming", anchor: .bottom)
                }
            }
            .onChange(of: vm.streamingText) {
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: layout.sized(phone: 60, pad: 100))

            Image(personaAvatarName(for: currentPersonaSlug))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: layout.profileImageMedium, height: layout.profileImageMedium)
                .clipShape(Circle())
                .overlay(Circle().stroke(ARIATheme.accentCyan.opacity(0.3), lineWidth: 1))

            Text("ARIA")
                .font(.system(size: layout.titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [ARIATheme.accent, ARIATheme.accentCyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("What can I help you with?")
                .font(layout.adaptiveBodyFont)
                .foregroundStyle(ARIATheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Streaming indicator

    private var streamingIndicator: some View {
        HStack(spacing: 6) {
            Image(personaAvatarName(for: currentPersonaSlug))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 18, height: 18)
                .clipShape(Circle())
            ProgressView().scaleEffect(0.7).tint(ARIATheme.accentCyan)
            Text(vm.statusText.isEmpty ? "Thinking..." : TextSanitizer.sanitize(vm.statusText))
                .font(layout.adaptiveCaptionFont)
                .foregroundStyle(ARIATheme.textMuted)
        }
        .padding(.horizontal, layout.screenPadding)
        .padding(.vertical, 6)
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ARIATheme.error)
            Text(message).font(layout.adaptiveCaptionFont).foregroundStyle(ARIATheme.error)
            Spacer()
            Button { vm.error = nil } label: {
                Image(systemName: "xmark").font(.caption).foregroundStyle(ARIATheme.textMuted)
            }
        }
        .padding(10)
        .background(ARIATheme.error.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, layout.screenPadding)
        .padding(.bottom, 4)
    }

    // MARK: - Deep Link

    private func navigateToConversation(id: String) async {
        if let conv = vm.conversations.first(where: { $0.id == id }) {
            await vm.selectConversation(conv)
        } else {
            await vm.loadConversations()
            if let conv = vm.conversations.first(where: { $0.id == id }) {
                await vm.selectConversation(conv)
            }
        }
    }

    // MARK: - Notification Handling

    private func handlePIEInsightTap(_ insight: PendingPIEInsight) async {
        // Navigate to the insight conversation (already created server-side)
        await navigateToConversation(id: insight.conversationId)
        // Pre-fill input with a suggested follow-up
        vm.inputText = "Tell me more about this and what I should do."
    }
}
