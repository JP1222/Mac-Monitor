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

            iconButton(systemName: "arrow.clockwise", help: "Refresh") {
                Task { await viewModel.refresh() }
            }
            iconButton(systemName: "gearshape", help: "Settings") {
                // Open the main window and select the inline Settings section —
                // no separate Settings window. Set the section first so the
                // window shows Settings whether it's already open or just opened.
                nav.section = .settings
                NSApp.setActivationPolicy(.regular)
                openWindow(id: OverviewWindowID.overview)
                NSApp.activate(ignoringOtherApps: true)
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

    @ViewBuilder
    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MMTokens.inkMuted)
                .frame(width: 24, height: 24)
                .background(MMTokens.rgba(255, 255, 255, 0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
