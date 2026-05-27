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
    //
    // GitHub client: real GitHubClient — reads PAT from Keychain on every
    // call. If no PAT is configured yet (first run, fresh install), the
    // client surfaces `Error.missingToken` and the ViewModel keeps showing
    // the last cached snapshot (or the mock if there's no cache). The
    // Settings sheet in the popover header lets the user paste a PAT.
    //
    // Agent client: still mocked until the Mac-mini agent daemon ships.
    @StateObject private var viewModel = DashboardViewModel(
        github: GitHubClient(),
        agent: MockAgentClient(),
        refreshInterval: 15
    )

    var body: some Scene {
        MenuBarExtra("Mac Monitor", systemImage: "hexagon.fill") {
            PopoverView()
                .environmentObject(viewModel)
                .onAppear { viewModel.start() }
        }
        .menuBarExtraStyle(.window)
        // Settings is shown via AppKit NSWindow (see SettingsWindowController)
        // rather than a SwiftUI `Window` scene because LSUIElement apps can't
        // open Window scenes — the .accessory activation policy blocks it.
    }
}
