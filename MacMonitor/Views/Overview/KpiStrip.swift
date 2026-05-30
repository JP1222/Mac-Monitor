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

    var body: some View {
        HStack(spacing: 11) {
            // Accent stripe (the prototype's absolutely-positioned 3px bar).
            RoundedRectangle(cornerRadius: 3)
                .fill(metric.tone)
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(metric.label)
                    .font(MMFont.rounded(size: 10.5, weight: .heavy))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(MMTokens.inkSoft)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(metric.value)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .kerning(-0.8)
                        .foregroundStyle(MMTokens.ink)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    if let trend = metric.trend {
                        Text(trend)
                            .font(MMFont.rounded(size: 11, weight: .bold))
                            .foregroundStyle(metric.trendTone ?? MMTokens.mint)
                    }
                }

                Text(metric.sub)
                    .font(MMFont.rounded(size: 11.5))
                    .foregroundStyle(MMTokens.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 14, leading: 13, bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .glassCard(cornerRadius: 12)
    }
}
