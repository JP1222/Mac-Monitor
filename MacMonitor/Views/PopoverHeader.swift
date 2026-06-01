// PopoverHeader.swift
//
// The 28pt-tall header row at the top of the popover: brand glyph, title,
// "N online · synced 4s ago" status line, and two icon buttons (refresh +
// settings). Direct port of MBAPopover's header block.

import SwiftUI
import AppKit

public struct PopoverHeader: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @EnvironmentObject private var nav: NavModel
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        HStack(spacing: 9) {
            RunnerBrandGlyph(size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Yolo Runners")
                    .font(MMFont.rounded(size: 14, weight: .bold))
                    .kerning(-0.1)
                    .foregroundStyle(MMTokens.ink)

                HStack(spacing: 5) {
                    StatusDot(aggregate: viewModel.snapshot.aggregateState, size: 6)
                    Text(syncSummary)
                        .font(MMFont.rounded(size: 11))
                        .foregroundStyle(MMTokens.inkSoft)
                }
            }

            Spacer()

            // Three glass icon buttons in one container so they share a sampling
            // region and read as a single control cluster (Liquid Glass blends
            // neighboring glass within `spacing`).
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 4) {
                    iconButton(systemName: "macwindow", help: "Open main window") {
                        // Jump to the main window (Overview). No `.regular` flip — the
                        // app stays `.accessory` (no Dock icon); activate is enough to
                        // bring the window to the front.
                        nav.section = .overview
                        openWindow(id: OverviewWindowID.overview)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    iconButton(systemName: "arrow.clockwise", help: "Refresh", spinning: viewModel.isRefreshing) {
                        Task { await viewModel.refresh() }
                    }
                    iconButton(systemName: "gearshape", help: "Settings") {
                        // Open the main window and select the inline Settings section.
                        nav.section = .settings
                        openWindow(id: OverviewWindowID.overview)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MMTokens.glassDivider).frame(height: 1)
        }
    }

    private var syncSummary: String {
        let online = viewModel.snapshot.onlineRunnerCount
        let seconds = Int(Date().timeIntervalSince(viewModel.snapshot.generatedAt))
        let when: String
        if seconds < 60 { when = "\(seconds)s ago" }
        else if seconds < 3600 { when = "\(seconds / 60)m ago" }
        else { when = "—" }
        return "\(online) online · synced \(when)"
    }

    /// Native circular glass icon button (macOS 26). `.buttonStyle(.glass)`
    /// supplies hover, press (scale + illumination), and the vibrant glyph
    /// treatment that the old hand-rolled `HeaderIconButton` +
    /// `HeaderIconButtonStyle` (~65 lines, now deleted) approximated. The
    /// refresh button still swaps in the system spinner while a fetch is in
    /// flight — the one affordance the style doesn't cover.
    @ViewBuilder
    private func iconButton(
        systemName: String,
        help: String,
        spinning: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if spinning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .help(help)
    }
}
