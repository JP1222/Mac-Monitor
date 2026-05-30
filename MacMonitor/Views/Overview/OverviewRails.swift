// OverviewRails.swift
//
// The right-rail cards: Queue (jobs waiting on a runner) and Recent runs
// (history). Both are glass cards wrapping a column of rows, the spec's direct
// `List`/`LazyVStack`-of-rows mapping. Queue wait times tick live via a 1s
// TimelineView; recent rows open the run on GitHub when tapped.

import SwiftUI

/// Generic rail container: eyebrow title + optional trailing accessory + body.
struct RailCard<Accessory: View, Content: View>: View {
    let title: String
    var fixedHeight: CGFloat? = nil
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionCap(text: title)
                Spacer(minLength: 0)
                accessory()
            }
            VStack(alignment: .leading, spacing: 2) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(height: fixedHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard()
    }
}

// MARK: - Queue

struct QueueRail: View {
    let items: [QueueItem]
    var fixedHeight: CGFloat? = nil

    var body: some View {
        RailCard(title: "Queue · \(items.count)", fixedHeight: fixedHeight) {
            if let longest = items.map({ $0.waitingSeconds() }).max(), longest > 0 {
                Text("longest \(OverviewData.prettyDuration(longest))")
                    .font(MMFont.rounded(size: 10.5, weight: .bold))
                    .foregroundStyle(MMTokens.amber)
            }
        } content: {
            if items.isEmpty {
                Text("Queue is empty")
                    .font(MMFont.rounded(size: 12)).foregroundStyle(MMTokens.inkSoft)
                    .padding(.vertical, 6)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        QueueRow(item: item, longest: idx == 0, now: ctx.date)
                    }
                }
            }
        }
    }
}

private struct QueueRow: View {
    let item: QueueItem
    let longest: Bool
    let now: Date

    var body: some View {
        HStack(spacing: 9) {
            ResultGlyph(result: .queued, size: 18)
            if let pr = item.pullRequest {
                Text("#\(pr)").mmMono(size: 11.5, weight: .semibold, color: MMTokens.ink)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.branch).mmMono(size: 11.5, color: MMTokens.ink).lineLimit(1)
                Text(item.workflow).font(MMFont.rounded(size: 10.5)).foregroundStyle(MMTokens.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(item.waitingPretty(now: now))
                .font(MMFont.mono(size: 11, weight: .bold))
                .foregroundStyle(longest ? MMTokens.amber : MMTokens.inkSoft)
        }
        .padding(.horizontal, 6).padding(.vertical, 8)
        .background(longest ? MMTokens.amber.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - Recent runs

struct RecentRunsRail: View {
    let runs: [RecentRun]
    var onOpen: (URL) -> Void = { _ in }

    var body: some View {
        RailCard(title: "Recent runs") {
            HStack(spacing: 3) {
                Text("See all").font(MMFont.rounded(size: 10.5)).foregroundStyle(MMTokens.inkMuted)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(MMTokens.inkMuted)
            }
        } content: {
            if runs.isEmpty {
                Text("No recent runs")
                    .font(MMFont.rounded(size: 12)).foregroundStyle(MMTokens.inkSoft)
                    .padding(.vertical, 6)
            } else {
                ForEach(runs) { run in
                    HistoryRow(run: run)
                        .contentShape(Rectangle())
                        .onTapGesture { if let url = run.htmlURL { onOpen(url) } }
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let run: RecentRun

    var body: some View {
        HStack(spacing: 9) {
            ResultGlyph(result: run.result, size: 18)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(run.branch).mmMono(size: 11.5, weight: .semibold, color: MMTokens.ink).lineLimit(1)
                    Text(run.commitSHA.prefix(7)).font(MMFont.mono(size: 10)).foregroundStyle(MMTokens.inkFaint)
                }
                HStack(spacing: 0) {
                    Text(run.workflow).font(MMFont.rounded(size: 10.5)).foregroundStyle(MMTokens.inkSoft).lineLimit(1)
                    if let reason = run.failureReason {
                        Text(" · \(reason)").font(MMFont.rounded(size: 10.5)).foregroundStyle(MMTokens.tomato).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(run.durationPretty).mmMono(size: 11, color: MMTokens.inkMuted)
                Text(run.whenRelative()).font(MMFont.rounded(size: 10)).foregroundStyle(MMTokens.inkFaint)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 8)
    }
}
