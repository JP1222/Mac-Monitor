// ProgressBarView.swift
//
// Port of MMProgressBar — flat track + colored fill, with an optional shimmer
// sweep when the build is in progress. The shimmer is a `LinearGradient`
// scrolling its `startPoint`/`endPoint` via a `TimelineView` so it keeps
// animating in widget snapshots (timeline-driven, not state-driven).

import SwiftUI

public struct ProgressBarView: View {
    public let value: Double          // 0...1
    public let tone: Color
    public let height: CGFloat
    public let shimmer: Bool

    public init(
        value: Double,
        tone: Color = MMTokens.blue,
        height: CGFloat = 6,
        shimmer: Bool = true
    ) {
        self.value = max(0, min(1, value))
        self.tone = tone
        self.height = height
        self.shimmer = shimmer
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(MMTokens.rgba(255, 255, 255, 0.08))

                // Fill
                ZStack {
                    Capsule().fill(tone)
                    if shimmer {
                        TimelineView(.animation) { ctx in
                            let t = ctx.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: 2.4) / 2.4
                            // Slide a soft white highlight across the fill.
                            let highlightX = (t * 2 - 0.5)  // -0.5 ... 1.5
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear,                                offset: highlightX - 0.18),
                                            .init(color: MMTokens.rgba(255, 255, 255, 0.45),     offset: highlightX),
                                            .init(color: .clear,                                offset: highlightX + 0.18),
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .blendMode(.plusLighter)
                        }
                    }
                }
                .frame(width: max(0, geo.size.width * value))
                .shadow(color: tone.opacity(0.4), radius: height, x: 0, y: 0)
            }
        }
        .frame(height: height)
    }
}

// Workaround: LinearGradient.Stop wants `location` in 0...1. Allow values
// outside that range so the highlight can slide in/out cleanly.
private extension Gradient.Stop {
    init(color: Color, offset: Double) {
        self.init(color: color, location: max(0, min(1, offset)))
    }
}

#Preview("Progress bars") {
    VStack(alignment: .leading, spacing: 14) {
        ProgressBarView(value: 0.73, tone: MMTokens.blue, shimmer: true)
        ProgressBarView(value: 0.42, tone: MMTokens.amber, height: 4, shimmer: false)
        ProgressBarView(value: 0.92, tone: MMTokens.tomato, height: 4, shimmer: false)
    }
    .padding(32)
    .frame(width: 320)
    .background(MMTokens.glassStrong)
}
