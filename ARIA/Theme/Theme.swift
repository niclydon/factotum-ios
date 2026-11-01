import SwiftUI

/// Factotum design tokens — nova-modern-glass (the author's design system; source
/// implementations: Pane admin_ui.h). Darker graphite glass: near-black
/// backdrop, #1C1C1E glass panels, cerulean #4A7FA5 borders, light cyan
/// #8ABAD3 labels, gold-amber #C9933A accents and section heads, 45-degree
/// cut corners (14 panels / 10 buttons), flat color, error #D96A5A.
/// Retokenized in 3.3.0; previously matched the ARIA web app's dark theme.
enum ARIATheme {
    // MARK: - Colors

    /// Backdrop behind the glass (#0c0e10) — darker graphite.
    static let background = Color(red: 12/255, green: 14/255, blue: 16/255)

    /// Glass panel base (#1c1c1e)
    static let surface = Color(red: 28/255, green: 28/255, blue: 30/255)

    /// Glass panel as Pane specifies it: #1c1c1e at 78% over the backdrop,
    /// with the texture plate ghosting through.
    static let glassSurface = Color(red: 28/255, green: 28/255, blue: 30/255, opacity: 0.78)

    /// Borders, dividers — cerulean at working strength.
    static let border = Color(red: 74/255, green: 127/255, blue: 165/255, opacity: 0.45)

    /// Card outline — full cerulean #4a7fa5.
    static let borderStrong = Color(red: 74/255, green: 127/255, blue: 165/255)

    /// Accent / cerulean #4a7fa5.
    static let accent = Color(red: 74/255, green: 127/255, blue: 165/255)

    /// Light cyan #8abad3 — labels.
    static let accentCyan = Color(red: 138/255, green: 186/255, blue: 211/255)
    static let labelCyan = accentCyan

    /// Gold-amber #c9933a — accents and section heads.
    static let accentGold = Color(red: 201/255, green: 147/255, blue: 58/255)

    /// Metallic silver (#b8bcc4)
    static let metallic = Color(red: 184/255, green: 188/255, blue: 196/255)

    /// Primary text
    static let textPrimary = Color.white

    /// Secondary text
    static let textSecondary = Color(white: 0.6)

    /// Muted text
    static let textMuted = Color(white: 0.4)

    /// User message bubble
    static let userBubble = accent.opacity(0.15)

    /// Assistant message bubble
    static let assistantBubble = surface

    /// Error / destructive — nova-glass muted red #d96a5a.
    static let error = Color(red: 217/255, green: 106/255, blue: 90/255)

    /// Success
    static let success = Color(red: 34/255, green: 197/255, blue: 94/255)

    // MARK: - Typography

    static let titleFont: Font = .system(size: 17, weight: .semibold)
    static let bodyFont: Font = .system(size: 15)
    static let captionFont: Font = .system(size: 13)
    static let monoFont: Font = .system(size: 14, design: .monospaced)

    // MARK: - Layout

    static let cornerRadius: CGFloat = 12
    /// 45-degree cut for glass panels (Pane: 14px).
    static let cutCorner: CGFloat = 14
    /// 45-degree cut for buttons (Pane: 10px).
    static let buttonCut: CGFloat = 10
    static let messagePadding: CGFloat = 12
    static let screenPadding: CGFloat = 16
}

/// Rectangle with all four corners cut at 45 degrees — the nova-glass
/// panel signature (Pane's clip-path, as a Shape).
struct CutCorners: Shape {
    var cut: CGFloat = ARIATheme.cutCorner

    func path(in rect: CGRect) -> Path {
        let c = min(cut, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        p.closeSubpath()
        return p
    }
}

/// The nova-glass backdrop: darker graphite with the generated smoked-glass
/// texture plate ghosting through behind the (translucent) glass panels.
struct NovaGlassBackdrop: View {
    var body: some View {
        ZStack {
            ARIATheme.background
            Image("NovaGlassTexture")
                .resizable()
                .scaledToFill()
                .opacity(0.5)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Glass card chrome: translucent graphite fill, cerulean outline,
    /// 45-degree cut corners.
    func novaGlassCard(cut: CGFloat = ARIATheme.cutCorner) -> some View {
        self
            .background(ARIATheme.glassSurface)
            .overlay(CutCorners(cut: cut).stroke(ARIATheme.borderStrong.opacity(0.65), lineWidth: 1))
            .clipShape(CutCorners(cut: cut))
    }

    /// Swap a flat .background(ARIATheme.background) for the textured
    /// nova-glass backdrop.
    func novaGlassBackdrop() -> some View {
        background(NovaGlassBackdrop())
    }
}
