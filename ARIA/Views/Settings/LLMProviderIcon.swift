import SwiftUI

/// Renders provider logo icons for the LLM selector.
struct LLMProviderIcon: View {
    let provider: String
    let isActive: Bool

    private var iconColor: Color {
        isActive ? ARIATheme.success : ARIATheme.textSecondary
    }

    var body: some View {
        switch provider {
        case "claude":
            ClaudeLogo(color: iconColor)
        case "openai":
            OpenAILogo(color: iconColor)
        case "gemini":
            GeminiLogo(color: iconColor)
        default:
            AutoLogo(color: iconColor)
        }
    }
}

// MARK: - Claude Logo

private struct ClaudeLogo: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let scale = min(w, h) / 32

            // Main triangle shape (Claude's mark)
            var path = Path()
            path.move(to: CGPoint(x: 16 * scale, y: 4 * scale))
            path.addLine(to: CGPoint(x: 24 * scale, y: 26 * scale))
            path.addQuadCurve(
                to: CGPoint(x: 22 * scale, y: 28 * scale),
                control: CGPoint(x: 23.5 * scale, y: 27.5 * scale)
            )
            path.addLine(to: CGPoint(x: 16 * scale, y: 10 * scale))
            path.addLine(to: CGPoint(x: 10 * scale, y: 28 * scale))
            path.addQuadCurve(
                to: CGPoint(x: 8 * scale, y: 26 * scale),
                control: CGPoint(x: 8.5 * scale, y: 27.5 * scale)
            )
            path.closeSubpath()

            context.fill(path, with: .color(color))
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - OpenAI Logo

private struct OpenAILogo: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 24

            // Simplified OpenAI hexagonal aperture
            let path = Path { p in
                // Outer hexagon shape with aperture blades
                let cx: CGFloat = 12 * s
                let cy: CGFloat = 12 * s
                let r: CGFloat = 9 * s

                for i in 0..<6 {
                    let angle1 = CGFloat(i) * .pi / 3 - .pi / 6
                    let angle2 = CGFloat(i + 1) * .pi / 3 - .pi / 6

                    let x1 = cx + r * cos(angle1)
                    let y1 = cy + r * sin(angle1)
                    let x2 = cx + r * cos(angle2)
                    let y2 = cy + r * sin(angle2)

                    // Draw blade from edge to center offset
                    let innerR: CGFloat = 3.5 * s
                    let midAngle = (angle1 + angle2) / 2
                    let ix = cx + innerR * cos(midAngle + .pi / 6)
                    let iy = cy + innerR * sin(midAngle + .pi / 6)

                    p.move(to: CGPoint(x: x1, y: y1))
                    p.addLine(to: CGPoint(x: x2, y: y2))
                    p.addLine(to: CGPoint(x: ix, y: iy))
                    p.closeSubpath()
                }
            }

            context.stroke(path, with: .color(color), lineWidth: 1.5 * s)

            // Simple hexagon outline
            var hex = Path()
            for i in 0..<6 {
                let angle = CGFloat(i) * .pi / 3 - .pi / 6
                let x = 12 * s + 9 * s * cos(angle)
                let y = 12 * s + 9 * s * sin(angle)
                if i == 0 {
                    hex.move(to: CGPoint(x: x, y: y))
                } else {
                    hex.addLine(to: CGPoint(x: x, y: y))
                }
            }
            hex.closeSubpath()
            context.stroke(hex, with: .color(color), lineWidth: 1.2 * s)
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - Gemini Logo

private struct GeminiLogo: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 24

            // Four-pointed star (Gemini sparkle)
            var star = Path()
            let cx: CGFloat = 12 * s
            let cy: CGFloat = 12 * s

            star.move(to: CGPoint(x: cx, y: 2 * s))
            star.addQuadCurve(
                to: CGPoint(x: cx + 10 * s, y: cy),
                control: CGPoint(x: cx + 2.5 * s, y: cy - 2.5 * s)
            )
            star.addQuadCurve(
                to: CGPoint(x: cx, y: cy + 10 * s),
                control: CGPoint(x: cx + 2.5 * s, y: cy + 2.5 * s)
            )
            star.addQuadCurve(
                to: CGPoint(x: cx - 10 * s, y: cy),
                control: CGPoint(x: cx - 2.5 * s, y: cy + 2.5 * s)
            )
            star.addQuadCurve(
                to: CGPoint(x: cx, y: 2 * s),
                control: CGPoint(x: cx - 2.5 * s, y: cy - 2.5 * s)
            )

            context.fill(star, with: .color(color))
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - Auto Logo

private struct AutoLogo: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 24

            // Large sparkle
            var spark1 = Path()
            spark1.move(to: CGPoint(x: 10 * s, y: 2 * s))
            spark1.addQuadCurve(
                to: CGPoint(x: 17 * s, y: 10 * s),
                control: CGPoint(x: 12 * s, y: 8 * s)
            )
            spark1.addQuadCurve(
                to: CGPoint(x: 10 * s, y: 18 * s),
                control: CGPoint(x: 12 * s, y: 12 * s)
            )
            spark1.addQuadCurve(
                to: CGPoint(x: 3 * s, y: 10 * s),
                control: CGPoint(x: 8 * s, y: 12 * s)
            )
            spark1.addQuadCurve(
                to: CGPoint(x: 10 * s, y: 2 * s),
                control: CGPoint(x: 8 * s, y: 8 * s)
            )
            context.fill(spark1, with: .color(color))

            // Small sparkle
            var spark2 = Path()
            spark2.move(to: CGPoint(x: 18 * s, y: 13 * s))
            spark2.addQuadCurve(
                to: CGPoint(x: 22 * s, y: 17.5 * s),
                control: CGPoint(x: 19 * s, y: 16 * s)
            )
            spark2.addQuadCurve(
                to: CGPoint(x: 18 * s, y: 22 * s),
                control: CGPoint(x: 19 * s, y: 19 * s)
            )
            spark2.addQuadCurve(
                to: CGPoint(x: 14 * s, y: 17.5 * s),
                control: CGPoint(x: 17 * s, y: 19 * s)
            )
            spark2.addQuadCurve(
                to: CGPoint(x: 18 * s, y: 13 * s),
                control: CGPoint(x: 17 * s, y: 16 * s)
            )
            context.fill(spark2, with: .color(color.opacity(0.7)))
        }
        .frame(width: 28, height: 28)
    }
}
