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

    // GroupBox is the native primitive for a titled content panel (DESIGN.md §3):
    // the rail title (+ optional accessory) is the box label, the rows are its
    // content. No hand-rolled card.
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 2) { content() }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: fixedHeight, alignment: .top)
        } label: {
            HStack {
                Text(title).font(.headline)
                Spacer(minLength: 0)
                accessory()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MMTokens.amber)
            }
        } content: {
            if items.isEmpty {
                Text("Queue is empty")
                    .font(.callout).foregroundStyle(.secondary)
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
                Text("#\(pr)").font(.system(.caption, design: .monospaced).weight(.semibold)).monospacedDigit().foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.branch).font(.system(.caption, design: .monospaced)).foregroundStyle(.primary).lineLimit(1)
                Text(item.workflow).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(item.waitingPretty(now: now))
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(longest ? AnyShapeStyle(MMTokens.amber) : AnyShapeStyle(.secondary))
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
                Text("See all").font(.caption2).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        } content: {
            if runs.isEmpty {
                Text("No recent runs")
                    .font(.callout).foregroundStyle(.secondary)
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
                    Text(run.branch).font(.system(.caption, design: .monospaced).weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(run.commitSHA.prefix(7)).font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                }
                HStack(spacing: 0) {
                    Text(run.workflow).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    if let reason = run.failureReason {
                        Text(" · \(reason)").font(.caption2).foregroundStyle(MMTokens.tomato).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(run.durationPretty).font(.system(.caption, design: .monospaced)).monospacedDigit().foregroundStyle(.secondary)
                Text(run.whenRelative()).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 8)
    }
}
