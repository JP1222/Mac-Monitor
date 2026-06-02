// KpiStrip.swift
//
// The five headline metrics. Each card is a glass surface with a colored accent
// stripe down the left edge and a big SF Pro Rounded numeral — the spec maps
// the KPI value to `.font(.system(size: 28, weight: .heavy, design: .rounded))`
// with `.contentTransition(.numericText())` so live updates roll rather than
// snap. The strip itself is an adaptive grid (the spec's `LazyVGrid`), the
// idiomatic translation of the prototype's `flex-wrap` row.

import SwiftUI

struct KpiStrip: View {
    let metrics: [KpiMetric]

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(metrics) { metric in
                KpiCard(metric: metric)
            }
        }
    }
}

private struct KpiCard: View {
    let metric: KpiMetric

    // GroupBox is Apple's prescribed native primitive for a titled stat group
    // (DESIGN.md §3) — the metric name is the box label, the value + sub are its
    // content. No hand-rolled card surface.
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(metric.value)
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(metric.tone)
                        .lineLimit(1)
                    if let trend = metric.trend {
                        Text(trend)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(metric.trendTone ?? Color.secondary)
                    }
                }
                Text(metric.sub)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
        } label: {
            Text(metric.label)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
    }
}
