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
    private func iconButton(
        systemName: String,
        help: String,
        spinning: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        HeaderIconButton(systemName: systemName, help: help, spinning: spinning, action: action)
    }
}

/// A 24×24 icon button for the popover header. `.plain` drops every native
/// feedback layer on the floor, so this view rebuilds the three that matter:
///   • hover  — background brightens when the pointer is over it
///   • press  — scales down + brightens further (only a `ButtonStyle` can see
///              `configuration.isPressed`, so the press layer lives there)
///   • work   — when `spinning` is true the glyph rotates continuously, so the
///              refresh icon reflects the in-flight fetch, not just the tap
private struct HeaderIconButton: View {
    let systemName: String
    let help: String
    var spinning: Bool = false
    let action: () -> Void

    @State private var isHovering = false
    @State private var angle: Double = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MMTokens.inkMuted)
                .rotationEffect(.degrees(angle))
        }
        .buttonStyle(HeaderIconButtonStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
        .help(help)
        .onChange(of: spinning) { _, now in
            if now {
                // Canonical bug-free continuous spin: animate a monotonically
                // increasing angle with `.repeatForever`. Each cycle adds 360°
                // so it never visibly resets while turning.
                withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) {
                    angle += 360
                }
            } else {
                // Stopping a `repeatForever` is the tricky half: the infinite
                // animation keeps "owning" `angle`, so a plain assignment won't
                // settle it. Mutating inside an animations-disabled transaction
                // detaches the repeat and snaps the glyph back to rest.
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { angle = 0 }
            }
        }
    }
}

/// Press feedback for the header icon buttons. A `ButtonStyle` is the only
/// place SwiftUI exposes the pressed phase (`configuration.isPressed`); hover
/// is passed in from the owning view since a style can't observe it.
private struct HeaderIconButtonStyle: ButtonStyle {
    let isHovering: Bool
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 24, height: 24)
            .background(
                fill(pressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    /// Three rest/hover/press tiers, each adaptive: a white scrim reads on the
    /// dark popover, a black scrim on the light one. The old hardcoded
    /// `rgba(255,255,255,0.06)` was nearly invisible in light mode.
    private func fill(pressed: Bool) -> Color {
        let dark = scheme == .dark
        if pressed {
            return dark ? MMTokens.rgba(255, 255, 255, 0.16) : MMTokens.rgba(0, 0, 0, 0.14)
        }
        if isHovering {
            return dark ? MMTokens.rgba(255, 255, 255, 0.10) : MMTokens.rgba(0, 0, 0, 0.08)
        }
        return dark ? MMTokens.rgba(255, 255, 255, 0.05) : MMTokens.rgba(0, 0, 0, 0.04)
    }
}
