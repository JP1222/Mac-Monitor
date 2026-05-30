// OverviewSupport.swift
//
// Shared primitives for the Overview window. The card surface is now backed by
// a real SwiftUI `Material` (an NSVisualEffectView under the hood) rather than a
// flat ~2.5%-white fill — that's what gives native macOS cards their frosted
// depth, inner top-highlight, and separation from the background. We keep a
// thin gradient stroke + soft shadow on top for the "elevated surface" look.

import SwiftUI
import AppKit

// MARK: - Vibrancy

/// `NSVisualEffectView` bridge for cases where we want a specific material the
/// SwiftUI `Material` enum doesn't expose (e.g. `.underWindowBackground`,
/// `.sidebar`). SwiftUI's `.background(.regularMaterial)` covers most cards.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = emphasized
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

// MARK: - Glass card

/// Native elevated card surface: a `Material` base + a top-lit hairline + a soft
/// drop shadow. This is the single biggest "feels native" change — Materials
/// render as frosted vibrancy in dark mode, the way macOS sheets/popovers do,
/// instead of the previous near-invisible translucent fill.
struct GlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var material: Material = .regularMaterial
    var cornerRadius: CGFloat = 12
    var elevated: Bool = true
    /// Optional accent tint laid over the surface (used by the live-build hero
    /// and the selected fleet card).
    var tint: Color? = nil
    var strokeColor: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = scheme == .dark
        return content
            .background {
                ZStack {
                    // Dark mode: frosted vibrancy reads as elevated glass.
                    // Light mode: a CRISP SOLID card — the vibrancy material
                    // fogs over content and washes out accent tints in light,
                    // which is exactly the "covered / colors paled" symptom.
                    if dark {
                        shape.fill(material)
                    } else {
                        shape.fill(Color(nsColor: .controlBackgroundColor))
                    }
                    if let tint { shape.fill(tint) }
                }
            }
            .overlay {
                if let strokeColor {
                    shape.strokeBorder(strokeColor, lineWidth: 1)
                } else {
                    // Top-lit hairline, polarity flipped per appearance.
                    shape.strokeBorder(
                        LinearGradient(
                            colors: dark
                                ? [MMTokens.rgba(255, 255, 255, 0.14), MMTokens.rgba(255, 255, 255, 0.04)]
                                : [MMTokens.rgba(0, 0, 0, 0.10), MMTokens.rgba(0, 0, 0, 0.05)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(elevated ? (dark ? 0.22 : 0.10) : 0),
                    radius: dark ? 7 : 4, x: 0, y: dark ? 3 : 2)
    }
}

extension View {
    /// Native elevated card surface. See `GlassCardModifier`.
    func glassCard(
        material: Material = .regularMaterial,
        cornerRadius: CGFloat = 12,
        elevated: Bool = true,
        tint: Color? = nil,
        strokeColor: Color? = nil
    ) -> some View {
        modifier(GlassCardModifier(material: material, cornerRadius: cornerRadius,
                                   elevated: elevated, tint: tint, strokeColor: strokeColor))
    }
}

// MARK: - Eyebrow (section caps)

/// Uppercase, tracked, heavy section label used on rail/card headers.
struct SectionCap: View {
    let text: String
    var color: Color = MMTokens.ink
    var body: some View {
        Text(text)
            .font(MMFont.rounded(size: 11.5, weight: .heavy))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
