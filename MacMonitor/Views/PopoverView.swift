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
        VStack(spacing: 0) {
            PopoverHeader()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    MMSection(title: "Runners") {
                        VStack(spacing: 8) {
                            ForEach(viewModel.snapshot.runners) { runner in
                                RunnerCardView(runner: runner)
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
                            ForEach(Array(viewModel.snapshot.queue.enumerated()), id: \.element.id) { i, q in
                                QueueRowView(item: q, isLongest: i == 0 && viewModel.snapshot.queue.count > 0)
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
                            ForEach(viewModel.snapshot.recent.prefix(5)) { run in
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
            .frame(maxHeight: 560)

            QuickActionsBar()
                .environmentObject(viewModel)
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
