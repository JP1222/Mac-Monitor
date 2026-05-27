// LargeWidgetView.swift
//
// 338×338 — everything: two runner mini-cards, queue/passed/failed counts,
// 3 recent runs, three-layer disk strip. Port of `DWLarge`.

import SwiftUI

public struct LargeWidgetView: View {
    public let snapshot: DashboardSnapshot

    public init(snapshot: DashboardSnapshot) { self.snapshot = snapshot }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(
                title: "Runners · last 60 min",
                accent: snapshot.aggregateState
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(snapshot.runners.prefix(2)) { r in
                        RunnerMiniCard(runner: r)
                    }
                }
                .frame(minHeight: 78)

                HStack(spacing: 8) {
                    CountTile(label: "Queue",
                              value: snapshot.queue.count,
                              sub: "\(snapshot.longestWaitingSeconds)s longest",
                              tone: MMTokens.amber)
                    CountTile(label: "Passed",
                              value: snapshot.passedInLastHour(),
                              sub: "last hour",
                              tone: MMTokens.mint)
                    CountTile(label: "Failed",
                              value: snapshot.failedInLastHour(),
                              sub: "last hour",
                              tone: MMTokens.tomato)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent").mmEyebrow(color: MMTokens.inkFaint)
                    ForEach(snapshot.recent.prefix(3)) { run in
                        recentRow(run: run)
                    }
                }

                Spacer(minLength: 0)
                diskStrip
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 14, trailing: 14))
        }
    }

    // MARK: - Recent rows

    @ViewBuilder
    private func recentRow(run: RecentRun) -> some View {
        HStack(spacing: 7) {
            ResultGlyph(result: run.result, size: 14)
            Text(truncate(run.branch, max: 18))
                .mmMono(size: 11, weight: .semibold, color: MMTokens.ink)
            Spacer()
            Text(run.durationPretty).mmMono(size: 11)
            Text(run.whenRelative())
                .font(MMFont.rounded(size: 10))
                .foregroundStyle(MMTokens.inkSoft)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func truncate(_ s: String, max: Int) -> String {
        s.count > max ? String(s.prefix(max - 1)) + "…" : s
    }

    // MARK: - Disk strip (three-layer mini)

    @ViewBuilder
    private var diskStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Disk · three-layer").mmEyebrow(color: MMTokens.inkFaint)
                Spacer()
                Text("APFS · VM · cache")
                    .font(MMFont.mono(size: 9.5))
                    .foregroundStyle(MMTokens.inkMuted)
            }
            HStack(spacing: 8) {
                ForEach(snapshot.primaryDisks) { d in
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressBarView(value: d.usedFraction,
                                        tone: MMTokens.tone(for: d.displayTone),
                                        height: 4, shimmer: false)
                        HStack {
                            Text(d.label.split(separator: " ").first.map(String.init) ?? d.label)
                                .font(MMFont.mono(size: 9.5))
                                .foregroundStyle(MMTokens.inkMuted)
                            Spacer()
                            Text("\(Int(d.usedFraction * 100))%")
                                .font(MMFont.mono(size: 9.5, weight: .bold))
                                .foregroundStyle(MMTokens.tone(for: d.displayTone))
                        }
                    }
                }
            }
        }
    }
}

/// Square tile showing a count + tone + sub. Used in the large widget header.
public struct CountTile: View {
    public let label: String
    public let value: Int
    public let sub: String
    public let tone: Color

    public init(label: String, value: Int, sub: String, tone: Color) {
        self.label = label
        self.value = value
        self.sub = sub
        self.tone = tone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(value)")
                    .font(MMFont.mono(size: 20, weight: .heavy))
                    .kerning(-0.6)
                    .foregroundStyle(tone)
                Text(label)
                    .font(MMFont.rounded(size: 10, weight: .semibold))
                    .foregroundStyle(MMTokens.inkMuted)
            }
            Text(sub)
                .font(MMFont.mono(size: 9.5))
                .foregroundStyle(MMTokens.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
        .background(MMTokens.rgba(255, 255, 255, 0.04),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MMTokens.glassDivider, lineWidth: 1)
        )
    }
}
