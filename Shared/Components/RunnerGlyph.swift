// RunnerGlyph.swift
//
// The "runner mark" — a hexagon-ish shape used both as the brand icon (warm
// gold gradient in the popover header) and as the menu bar app's status icon
// (white-on-dark with a colored state dot overlay).
//
// The path is a direct port of the SVG from menu-bar-app.jsx:
//   M8 1.4 L13.5 4.4 V11.6 L8 14.6 L2.5 11.6 V4.4 Z

import SwiftUI

public struct RunnerHexagonShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        // Designed on a 16×16 viewBox; we scale to the rect.
        let sx = rect.width / 16
        let sy = rect.height / 16
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }
        var path = Path()
        path.move(to: p(8, 1.4))
        path.addLine(to: p(13.5, 4.4))
        path.addLine(to: p(13.5, 11.6))
        path.addLine(to: p(8, 14.6))
        path.addLine(to: p(2.5, 11.6))
        path.addLine(to: p(2.5, 4.4))
        path.closeSubpath()
        return path
    }
}

/// Brand-colored runner mark (warm gold gradient) — used in popover header
/// and widget headers.
public struct RunnerBrandGlyph: View {
    public let size: CGFloat

    public init(size: CGFloat = 28) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [MMTokens.brand, MMTokens.brandDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(MMTokens.rgba(255, 255, 255, 0.4), lineWidth: 0.5)
                )

            ZStack {
                RunnerHexagonShape()
                    .fill(Color(red: 26/255, green: 18/255, blue: 8/255).opacity(0.9))
                Circle()
                    .fill(MMTokens.rgba(255, 255, 255, 0.92))
                    .frame(width: size * 0.30, height: size * 0.30)
            }
            .frame(width: size * 0.6, height: size * 0.6)
        }
        .frame(width: size, height: size)
    }
}

/// Menu bar variant: monochrome hex with a tiny status dot riding the corner.
public struct RunnerMenuBarGlyph: View {
    public let aggregate: DashboardSnapshot.AggregateState
    public let size: CGFloat

    public init(aggregate: DashboardSnapshot.AggregateState, size: CGFloat = 16) {
        self.aggregate = aggregate
        self.size = size
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RunnerHexagonShape()
                    .fill(MMTokens.rgba(255, 255, 255, 0.92))
                Circle()
                    .fill(MMTokens.rgba(0, 0, 0, 0.55))
                    .frame(width: size * 0.28, height: size * 0.28)
            }
            .frame(width: size, height: size)

            // Status dot riding the bottom-right corner.
            Circle()
                .fill(MMTokens.tone(for: aggregate))
                .frame(width: size * 0.44, height: size * 0.44)
                .overlay(
                    Circle()
                        .stroke(MMTokens.rgba(0, 0, 0, 0.55), lineWidth: size * 0.09)
                )
                .shadow(color: MMTokens.glow(for: aggregate), radius: size * 0.22)
                .offset(x: size * 0.18, y: size * 0.18)
        }
        .frame(width: size, height: size)
    }
}

#Preview("Brand glyph") {
    HStack(spacing: 20) {
        RunnerBrandGlyph(size: 16)
        RunnerBrandGlyph(size: 28)
        RunnerBrandGlyph(size: 48)
    }
    .padding(32)
    .background(MMTokens.glassStrong)
}

#Preview("Menu bar glyphs") {
    HStack(spacing: 20) {
        RunnerMenuBarGlyph(aggregate: .idle, size: 20)
        RunnerMenuBarGlyph(aggregate: .building, size: 20)
        RunnerMenuBarGlyph(aggregate: .warning, size: 20)
        RunnerMenuBarGlyph(aggregate: .failure, size: 20)
    }
    .padding(32)
    .background(LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom))
}
