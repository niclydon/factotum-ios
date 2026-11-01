import SwiftUI

/// Adaptive sizing helpers for iPhone/iPad and orientation changes.
/// Use these throughout views instead of hardcoded values.
struct AdaptiveLayout {
    let horizontalSizeClass: UserInterfaceSizeClass?
    let verticalSizeClass: UserInterfaceSizeClass?

    /// True for iPad full-screen (not split-view narrow)
    var isRegular: Bool {
        horizontalSizeClass == .regular
    }

    /// True for iPhone portrait or iPad narrow split-view
    var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    /// True when in landscape (vertical is compact)
    var isLandscape: Bool {
        verticalSizeClass == .compact
    }

    /// Pick a value based on device class
    func sized<T>(phone: T, pad: T) -> T {
        isRegular ? pad : phone
    }

    /// Pick a value based on orientation
    func oriented<T>(portrait: T, landscape: T) -> T {
        isLandscape ? landscape : portrait
    }

    // MARK: - Common Adaptive Sizes

    /// Profile image size (login, splash, settings)
    var profileImageLarge: CGFloat { sized(phone: 100, pad: 140) }
    var profileImageMedium: CGFloat { sized(phone: 80, pad: 100) }
    var profileImageSmall: CGFloat { sized(phone: 40, pad: 56) }
    var profileImageChat: CGFloat { sized(phone: 22, pad: 28) }

    /// Chat message max-width as fraction of container
    var messageMaxWidthFraction: CGFloat { sized(phone: 0.85, pad: 0.70) }
    var messageMinSpacing: CGFloat { sized(phone: 40, pad: 60) }

    /// Button sizes
    var buttonWidth: CGFloat { sized(phone: 220, pad: 280) }
    var buttonHeight: CGFloat { sized(phone: 44, pad: 50) }

    /// Voice orb
    var orbSize: CGFloat { sized(phone: 120, pad: 160) }
    var orbSizeWalkie: CGFloat { sized(phone: 200, pad: 260) }

    /// Sidebar
    var sidebarWidth: CGFloat { sized(phone: 300, pad: 320) }

    /// Title font size
    var titleSize: CGFloat { sized(phone: 32, pad: 44) }
    var subtitleSize: CGFloat { sized(phone: 15, pad: 17) }

    /// Screen padding
    var screenPadding: CGFloat { sized(phone: 16, pad: 24) }

    // MARK: - Adaptive Font Sizes

    /// Title font size: iPhone 17pt, iPad 20pt
    var fontTitle: CGFloat { sized(phone: 17, pad: 20) }
    /// Body font size: iPhone 15pt, iPad 17pt
    var fontBody: CGFloat { sized(phone: 15, pad: 17) }
    /// Caption font size: iPhone 13pt, iPad 15pt
    var fontCaption: CGFloat { sized(phone: 13, pad: 15) }
    /// Subheadline font size: iPhone 14pt, iPad 16pt
    var fontSubheadline: CGFloat { sized(phone: 14, pad: 16) }

    // MARK: - Adaptive Fonts (convenience)

    var adaptiveTitleFont: Font { .system(size: fontTitle, weight: .semibold) }
    var adaptiveBodyFont: Font { .system(size: fontBody) }
    var adaptiveCaptionFont: Font { .system(size: fontCaption) }
    var adaptiveSubheadlineFont: Font { .system(size: fontSubheadline) }

    // MARK: - Content Constraints

    /// Max content width for centered layouts on large iPad screens
    var maxContentWidth: CGFloat { sized(phone: .infinity, pad: 720) }
    /// Input field minimum height
    var inputHeight: CGFloat { sized(phone: 40, pad: 48) }
    /// Message bubble horizontal padding
    var messageBubblePadding: CGFloat { sized(phone: 12, pad: 16) }
    /// Vertical section spacing
    var sectionSpacing: CGFloat { sized(phone: 12, pad: 20) }
}

// MARK: - Environment Key

private struct AdaptiveLayoutKey: EnvironmentKey {
    static let defaultValue = AdaptiveLayout(horizontalSizeClass: .compact, verticalSizeClass: .regular)
}

extension EnvironmentValues {
    var adaptiveLayout: AdaptiveLayout {
        get { self[AdaptiveLayoutKey.self] }
        set { self[AdaptiveLayoutKey.self] = newValue }
    }
}

// MARK: - View Modifier

/// Injects AdaptiveLayout into the environment based on current size classes.
struct AdaptiveLayoutModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.verticalSizeClass) private var vSizeClass

    func body(content: Content) -> some View {
        content
            .environment(\.adaptiveLayout, AdaptiveLayout(
                horizontalSizeClass: hSizeClass,
                verticalSizeClass: vSizeClass
            ))
    }
}

extension View {
    func adaptiveLayout() -> some View {
        modifier(AdaptiveLayoutModifier())
    }
}
