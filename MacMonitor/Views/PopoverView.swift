// PopoverView.swift
//
// Top-level popover layout — header, runner cards, queue, recent runs, storage,
// quick action buttons. Direct translation of `MBAPopover` from
// menu-bar-app.jsx, preserving the section order, spacing, and divider model.
//
// Width is fixed at 380pt (MBA_WIDTH in the JSX). Height is content-driven
// with a max-height cap so the popover never extends past the screen.

import SwiftUI

public struct PopoverView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    public init() {}

    public var body: some View {
        // Layout strategy:
        //   - Plain VStack. MenuBarExtra(.window) sizes the popover to the
        //     view tree's intrinsic height — every section has a known size
        //     so this Just Works.
        //   - Sections cap row counts (.prefix(N)) so the popover can't grow
        //     unbounded if a repo has e.g. 50 queued jobs.
        //   - Tried ScrollView + .fixedSize and ViewThatFits — both collapse
        //     to 0 height inside MenuBarExtra. The cap-rows approach is the
        //     reliable workaround.
        VStack(spacing: 0) {
            PopoverHeader()
            if viewModel.hasGitHubToken {
                ErrorBanner()
                    .environmentObject(viewModel)
                sectionsContent
                QuickActionsBar()
                    .environmentObject(viewModel)
            } else {
                OnboardingView()
                    .environmentObject(viewModel)
            }
        }
        .frame(width: 380)
        .background(popoverBackground)
        .foregroundStyle(MMTokens.ink)
        .clipShape(RoundedRectangle(cornerRadius: MMTokens.radiusPopover, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MMTokens.radiusPopover, style: .continuous)
                .stroke(MMTokens.glassBorder, lineWidth: 1)
        )
    }

    /// The four data sections. Extracted so ViewThatFits can use the same
    /// content tree in both the no-scroll and scroll variants without
    /// duplicating ~60 lines of MMSection definitions.
    /// Visible-row caps per section. Anything beyond these limits is summed
    /// into a "+N more" footer link so the popover height stays predictable
    /// (~520pt max with all sections full).
    private let maxRunners = 6
    private let maxQueueRows = 5
    private let maxRecentRows = 5

    @ViewBuilder
    private var sectionsContent: some View {
        let onlineRunners = viewModel.snapshot.runners.filter { $0.status == .online }
        let offlineRunners = viewModel.snapshot.runners.filter { $0.status == .offline }

        VStack(spacing: 0) {
            MMSection(title: "Runners · \(viewModel.snapshot.runners.count)") {
                VStack(spacing: 8) {
                    ForEach(onlineRunners.prefix(maxRunners)) { runner in
                        RunnerCardView(runner: runner)
                    }
                    if onlineRunners.count > maxRunners {
                        moreRow(count: onlineRunners.count - maxRunners)
                    }
                    // Offline runners collapsed into a single chip so they
                    // don't eat 80pt of vertical space per runner just to
                    // say "still off". Names still visible.
                    if !offlineRunners.isEmpty {
                        offlineSummaryChip(offlineRunners)
                    }
                }
            }
            MMSection(
                title: "Queue · \(viewModel.snapshot.queue.count) waiting",
                action: {
                    if viewModel.snapshot.longestWaitingSeconds > 0 {
                        Text("longest \(viewModel.snapshot.longestWaitingSeconds)s")
                            .font(MMFont.rounded(size: 11, weight: .semibold))
                            .foregroundStyle(MMTokens.amber)
                    } else {
                        EmptyView()
                    }
                }
            ) {
                VStack(spacing: 0) {
                    ForEach(
                        Array(viewModel.snapshot.queue.prefix(maxQueueRows).enumerated()),
                        id: \.element.id
                    ) { i, q in
                        QueueRowView(item: q, isLongest: i == 0 && viewModel.snapshot.queue.count > 0)
                    }
                    if viewModel.snapshot.queue.count > maxQueueRows {
                        moreRow(count: viewModel.snapshot.queue.count - maxQueueRows)
                    }
                }
            }

            MMSection(
                title: "Recent runs",
                action: {
                    Text("View all on GitHub ›")
                        .font(MMFont.rounded(size: 11))
                        .foregroundStyle(MMTokens.inkMuted)
                }
            ) {
                VStack(spacing: 0) {
                    ForEach(viewModel.snapshot.recent.prefix(maxRecentRows)) { run in
                        RecentRunRowView(run: run)
                    }
                }
            }

            MMSection(title: "Storage · three-layer", divider: false) {
                VStack(spacing: 9) {
                    ForEach(viewModel.snapshot.primaryDisks) { disk in
                        DiskMeterView(disk: disk)
                    }
                }
            }
        }
    }

    /// "+N more" row at the bottom of a capped section. Visual cue that
    /// data was truncated without dropping it silently.
    private func moreRow(count: Int) -> some View {
        Text("+\(count) more")
            .font(MMFont.rounded(size: 10.5, weight: .semibold))
            .foregroundStyle(MMTokens.inkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 5)
    }

    /// Compact one-line chip listing offline runners. Replaces per-runner
    /// full cards for offline status — keeps the names visible but reclaims
    /// ~60pt per runner of vertical space.
    private func offlineSummaryChip(_ runners: [Runner]) -> some View {
        HStack(spacing: 8) {
            StatusDot(state: .offline, pulse: false, size: 7)
            Text("\(runners.count) offline")
                .font(MMFont.rounded(size: 11.5, weight: .semibold))
                .foregroundStyle(MMTokens.inkSoft)
            Text("·").foregroundStyle(MMTokens.inkFaint)
            Text(runners.map(\.label).joined(separator: ", "))
                .font(MMFont.mono(size: 10.5))
                .foregroundStyle(MMTokens.inkFaint)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MMTokens.rgba(255, 255, 255, 0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MMTokens.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Dark glass = system thin material + our token color overlay. The
    /// material brings the SwiftUI vibrancy effect; the overlay matches the
    /// 78% alpha tint from shared.jsx (`rgba(28,28,32,0.78)`).
    private var popoverBackground: some View {
        ZStack {
            Rectangle().fill(.thinMaterial)
            Rectangle().fill(MMTokens.glass)
        }
    }
}

#Preview("Popover") {
    PopoverView()
        .environmentObject(DashboardViewModel(refreshInterval: 999))
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(red: 91/255, green: 109/255, blue: 143/255),
                         Color(red: 26/255, green: 31/255, blue: 46/255)],
                startPoint: .top, endPoint: .bottom
            )
        )
}
