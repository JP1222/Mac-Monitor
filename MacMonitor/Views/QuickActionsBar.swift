// QuickActionsBar.swift
//
// Three buttons across the bottom of the popover:
//   - Actions  → opens the watched repo's Actions tab in the browser
//   - Restart  → asks the agent to restart the runner LaunchAgent
//   - Prune cache → asks the agent to drop the BuildKit cache (tinted amber)

import SwiftUI
import AppKit

public struct QuickActionsBar: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    public init() {}

    public var body: some View {
        // Both buttons in one container so the prominent action and the Quit
        // glass pill share a sampling region and blend at their shared edge.
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                // Primary action: prominent (opaque) glass, brand-tinted.
                Button {
                    if let url = viewModel.snapshot.repositories.first?.actionsURL {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open Actions on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(MMFont.rounded(size: 11.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                // Quit — a menu-bar (`.accessory`) app has no app menu, so this is
                // the user's way out. ⌘Q works while the popover is focused.
                // Secondary action → translucent `.glass`.
                Button { NSApp.terminate(nil) } label: {
                    Label("Quit", systemImage: "power")
                        .font(MMFont.rounded(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("q", modifiers: .command)
                .help("Quit Mac Monitor")
                // Restart / Prune buttons intentionally removed: they act on the
                // LOCAL agent's runner LaunchAgents, but this setup runs runners on
                // a remote machine and schedules them externally — so the buttons
                // could never succeed here and only produced confusing errors.
                // The agent-side actions + ViewModel methods remain for a future
                // setup that wants in-app control.
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
