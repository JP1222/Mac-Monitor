// StatusDot.swift
//
// Port of MMStatusDot from shared.jsx — a colored circle with an outer glow
// ring and an optional "pulse" expanding-border animation when the build is
// live. The pulse uses a `TimelineView(.animation)` so it ticks even inside a
// widget snapshot (where conventional `withAnimation` is a no-op).

import SwiftUI

public struct StatusDot: View {
    public let tone: Color
    public let glow: Color
    public let pulse: Bool
    public let size: CGFloat

    public init(tone: Color, glow: Color, pulse: Bool = false, size: CGFloat = 8) {
        self.tone = tone
        self.glow = glow
        self.pulse = pulse
        self.size = size
    }

    /// Convenience initializer matching the shared.jsx API: pass the token name.
    public init(state: RunnerState, pulse: Bool? = nil, size: CGFloat = 8) {
        self.tone = MMTokens.tone(for: state)
        self.glow = MMTokens.glow(for: state)
        // Default: pulse iff currently building.
        self.pulse = pulse ?? (state == .building)
        self.size = size
    }

    public init(aggregate: DashboardSnapshot.AggregateState, pulse: Bool? = nil, size: CGFloat = 8) {
        self.tone = MMTokens.tone(for: aggregate)
        self.glow = MMTokens.glow(for: aggregate)
        self.pulse = pulse ?? (aggregate == .building)
        self.size = size
    }

    public var body: some View {
        ZStack {
            // Soft outer glow approximated with shadow — `box-shadow: 0 0 0 X glow`.
            Circle()
                .fill(tone)
                .frame(width: size, height: size)
                .shadow(color: glow, radius: size * 0.6, x: 0, y: 0)

            if pulse {
                // TimelineView gives us a deterministic phase 0...1 even when
                // SwiftUI animations are paused (widgets).
                TimelineView(.animation) { ctx in
                    let phase = (ctx.date.timeIntervalSinceReferenceDate)
                        .truncatingRemainder(dividingBy: 1.8) / 1.8
                    let scale = 0.8 + phase * 1.4
                    let opacity = max(0, 0.9 - phase * 1.1)
                    Circle()
                        .stroke(tone, lineWidth: 1.5)
                        .frame(width: size + 4, height: size + 4)
                        .scaleEffect(scale)
                        .opacity(opacity)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview("Status dots") {
    HStack(spacing: 18) {
        StatusDot(state: .idle, size: 10)
        StatusDot(state: .building, size: 10)
        StatusDot(state: .warning, size: 10)
        StatusDot(state: .failure, size: 10)
        StatusDot(state: .offline, size: 10)
    }
    .padding(32)
    .background(MMTokens.glassStrong)
}
