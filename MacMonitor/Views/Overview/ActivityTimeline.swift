// ActivityTimeline.swift
//
// The 24-hour activity sparkbar, now drawn with Swift Charts `BarMark` — the
// native Apple charting component the handoff spec (§04) pointed to. Each bar
// is one hour, colored mint/tomato/blue by result. Idle hours are floored to a
// faint baseline because a zero-height BarMark renders nothing.

import SwiftUI
import Charts

struct ActivityTimeline: View {
    let buckets: [ActivityBucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SectionCap(text: "24h activity")
                Spacer(minLength: 0)
                legend
            }
            .padding(.bottom, 10)

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Hour", bucket.id),
                    y: .value("Activity", displayHeight(bucket)),
                    width: .ratio(0.72)
                )
                .foregroundStyle(color(for: bucket.kind))
                .cornerRadius(2)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...1)
            .chartXScale(domain: -0.5...(Double(max(buckets.count, 1)) - 0.5))
            .frame(height: 70)

            HStack {
                Text("24h ago"); Spacer(); Text("16h"); Spacer(); Text("8h"); Spacer(); Text("now")
            }
            .font(MMFont.mono(size: 10))
            .foregroundStyle(MMTokens.inkFaint)
            .padding(.top, 6)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
        .glassCard()
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem("success", MMTokens.mint)
            legendItem("fail", MMTokens.tomato)
            legendItem("active", MMTokens.blue)
        }
    }
    private func legendItem(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(MMFont.rounded(size: 11)).foregroundStyle(MMTokens.inkMuted)
        }
    }

    /// Floor idle bars to a thin baseline so the row reads as a continuous
    /// 24-slot strip rather than gaps; real activity scales above it.
    private func displayHeight(_ b: ActivityBucket) -> Double {
        b.kind == .idle ? 0.03 : max(0.10, b.height)
    }

    private func color(for kind: ActivityBucket.Kind) -> Color {
        switch kind {
        case .success: return MMTokens.mint
        case .failure: return MMTokens.tomato
        case .building: return MMTokens.blue
        case .idle: return MMTokens.rgba(255, 255, 255, 0.08)
        }
    }
}
