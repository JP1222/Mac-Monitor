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

                // Local runner online/offline. Only shown when the local agent
                // reports an installed runner LaunchAgent, so it never appears
                // for a setup whose runners live on a remote, externally-managed
                // machine (the reason the Restart/Prune buttons were pulled).
                if let control = viewModel.localRunnerControl {
                    Button {
                        Task { await viewModel.setRunner(online: !control.online, on: control.device) }
                    } label: {
                        Label(control.online ? "On" : "Off",
                              systemImage: control.online ? "bolt.fill" : "bolt.slash")
                            .font(MMFont.rounded(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(control.online ? .green : nil)
                    .disabled(viewModel.isPerformingAction)
                    .help(control.online
                          ? "Runner online — click to take this Mac out of the CI pool"
                          : "Runner offline — click to bring this Mac into the CI pool")
                }

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
                // The full Restart + Prune-cache buttons stay removed (they act
                // on the LOCAL agent but only make sense where runners actually
                // run — see git history). The online/offline toggle above is the
                // one in-app control, and it self-hides unless the local agent
                // reports an installed runner, so it never shows the confusing
                // "no runners here" error those buttons did.
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
