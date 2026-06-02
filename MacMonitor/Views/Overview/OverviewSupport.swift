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

// MARK: - Content card (native surface)

/// Native macOS content-card surface: a system `controlBackgroundColor` fill, a
/// hairline in the system `separatorColor`, and continuous corners. NO hand-drawn
/// top-lit gradient hairline and NO custom drop shadow — those read as a web port
/// (this UI began as a 1:1 JSX prototype). The system colors instead read as a
/// native grouped surface, the look of Settings panels and source-list detail
/// wells. (Glass stays on the floating chrome; content cards like these are
/// opaque, per Liquid Glass rules — don't "upgrade" this to `glassEffect`.)
struct ContentCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    /// Accent wash laid over the fill for a selected / actively-building card.
    var tint: Color? = nil
    /// Accent stroke for selection; defaults to the system separator hairline.
    var strokeColor: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background {
                ZStack {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                    if let tint { shape.fill(tint) }
                }
            }
            .overlay {
                shape.strokeBorder(
                    strokeColor ?? Color(nsColor: .separatorColor),
                    lineWidth: strokeColor == nil ? 1 : 1.5
                )
            }
            .clipShape(shape)
    }
}

extension View {
    /// Native content-card surface. See `ContentCardModifier`.
    func contentCard(
        cornerRadius: CGFloat = 12,
        tint: Color? = nil,
        strokeColor: Color? = nil
    ) -> some View {
        modifier(ContentCardModifier(cornerRadius: cornerRadius, tint: tint, strokeColor: strokeColor))
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
