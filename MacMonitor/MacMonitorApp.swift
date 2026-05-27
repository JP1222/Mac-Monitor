// MacMonitorApp.swift
//
// Entry point. The whole app is a single MenuBarExtra: no Dock icon, no
// floating window, no main menu. `LSUIElement` in Info.plist (set by
// project.yml) hides the app from the Dock and force-quit list.
//
// Style choices:
//   - `MenuBarExtra(_:systemImage:)` is the convenience but we want a custom
//      icon (RunnerMenuBarGlyph), so we use the `Label` variant.
//   - `.menuBarExtraStyle(.window)` because the popover is a rich SwiftUI
//      layout, not a list of menu items.

import SwiftUI

@main
struct MacMonitorApp: App {

    // The single source of truth — owned at the App level so the popover and
    // any future settings window share the same state.
    @StateObject private var viewModel = DashboardViewModel(
        github: MockGitHubClient(),
        agent: MockAgentClient(),
        refreshInterval: 15
    )

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(viewModel)
                .onAppear { viewModel.start() }
                .onDisappear { /* keep the timer running in background */ }
        } label: {
            // SwiftUI custom view as the menu bar icon. The aggregate state
            // drives the dot tone so users see "something's building" /
            // "something failed" at a glance without opening the popover.
            RunnerMenuBarGlyph(aggregate: viewModel.snapshot.aggregateState, size: 17)
        }
        .menuBarExtraStyle(.window)
    }
}
