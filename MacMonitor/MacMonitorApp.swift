// MacMonitorApp.swift
//
// Entry point. The app has TWO surfaces:
//   1. WindowGroup "overview" — the full Overview window.
//   2. MenuBarExtra — the quick-glance popover (also opens the window).
//
// The app is a menu-bar utility: `LSUIElement` (project.yml) keeps it
// `.accessory` — NO Dock icon. We do NOT flip to `.regular`; the window is
// brought to the front with `NSApp.activate(ignoringOtherApps:)` instead. The
// menu-bar icon is managed by the user (e.g. via Bartender).

import SwiftUI
import AppKit

@main
struct MacMonitorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The single source of truth — owned at the App level so the Overview
    // window AND the menu bar popover share one DashboardViewModel.
    @StateObject private var viewModel = DashboardViewModel(
        github: GitHubClient(),
        agent: AgentClient(),    // real HTTP to local MacMonitorAgent on :8765
        refreshInterval: 15
    )

    // Shared navigation state — lets the menu-bar gear and ⌘, drive the
    // window's selected section (Settings shows inline, not as a popup window).
    @StateObject private var nav = NavModel()

    init() {
        // Observe iCloud settings sync. Safe to call unconditionally — falls
        // back to local UserDefaults if iCloud is unavailable.
        UserSettings.startObservingICloud()

        // Register the bundled local agent as a LaunchAgent (SMAppService) so
        // the Storage panel gets live local-device health with no manual
        // install. Idempotent + non-fatal on failure. Local Mac only — remote
        // build-farm Macs install their own agent. See AgentInstaller.
        AgentInstaller.ensureRegistered()
    }

    var body: some Scene {
        // Primary surface: the full Overview window. `.hiddenTitleBar` lets the
        // custom dark-glass title bar show while the real traffic lights float
        // over it; `.contentMinSize` honors the 1100×760 min from OverviewWindow.
        WindowGroup(id: OverviewWindowID.overview) {
            OverviewWindow()
                .environmentObject(viewModel)
                .environmentObject(nav)
                .onAppear { viewModel.start() }
        }
        // Native unified titlebar+toolbar (NavigationSplitView supplies the
        // sidebar toggle, title/subtitle, and toolbar items). No hidden titlebar
        // — we want the real system chrome now.
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 940)
        .commands {
            // Native "Settings…" app-menu item + ⌘, — selects the inline
            // Settings section in the window (no separate Settings window).
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { nav.section = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        // Quick-glance surface: the menu bar popover. Its header carries a
        // small "open main window" icon (PopoverHeader) — no big button.
        MenuBarExtra("Mac Monitor", systemImage: "hexagon.fill") {
            PopoverView()
                .environmentObject(viewModel)
                .environmentObject(nav)
                .onAppear { viewModel.start() }
        }
        .menuBarExtraStyle(.window)
        // Settings is an inline section of the Overview window (NavModel /
        // NavSection.settings), not a separate window.
    }
}

/// Shared window identifier so the scene and every opener agree on one string.
enum OverviewWindowID {
    static let overview = "overview"
}

/// Foregrounds the initial window on launch. Stays `.accessory` (no Dock icon).
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No `setActivationPolicy(.regular)` — we want NO Dock icon. Activating
        // brings the auto-opened window to the front without a Dock presence.
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }
}
