// ResultGlyph.swift
//
// Port of MMResultGlyph from shared.jsx: a tiny round chip showing check /
// cross / spinner / placeholder per JobResult. Used in the queue rows, recent
// runs list, and inside cards.

import SwiftUI

public struct ResultGlyph: View {
    public let result: JobResult
    public let size: CGFloat

    public init(result: JobResult, size: CGFloat = 18) {
        self.result = result
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(background)
            .frame(width: size, height: size)
            .overlay { symbol }
    }

    private var background: Color {
        switch result {
        case .success: return MMTokens.mintGlow
        case .failure: return MMTokens.tomatoGlow
        case .cancelled: return MMTokens.rgba(255, 255, 255, 0.08)
        case .building: return MMTokens.blueGlow
        case .queued, .skipped: return MMTokens.rgba(255, 255, 255, 0.06)
        }
    }

    @ViewBuilder
    private var symbol: some View {
        switch result {
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.55, weight: .heavy))
                .foregroundStyle(MMTokens.mint)
        case .failure:
            Image(systemName: "xmark")
                .font(.system(size: size * 0.45, weight: .heavy))
                .foregroundStyle(MMTokens.tomato)
        case .cancelled:
            // ⊘ minus-circle to distinguish from a real failure — the build
            // didn't run to completion (user/system cancelled), not the same
            // as "your code is broken".
            Image(systemName: "minus")
                .font(.system(size: size * 0.55, weight: .heavy))
                .foregroundStyle(MMTokens.inkMuted)
        case .building:
            // Spinner: a partial ring rotating.
            TimelineView(.animation) { ctx in
                let angle = Angle.degrees(
                    ctx.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.1) / 1.1 * 360
                )
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(MMTokens.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: size * 0.62, height: size * 0.62)
                    .rotationEffect(angle)
            }
        case .queued, .skipped:
            EmptyView()
        }
    }
}

#Preview("Result glyphs") {
    HStack(spacing: 12) {
        ResultGlyph(result: .success)
        ResultGlyph(result: .failure)
        ResultGlyph(result: .building)
        ResultGlyph(result: .queued)
        ResultGlyph(result: .cancelled)
    }
    .padding(24)
    .background(MMTokens.glassStrong)
}
