// MacMonitorApp.swift
//
// Entry point. The app now has TWO surfaces:
//   1. WindowGroup "overview" — the full Overview window, the PRIMARY surface.
//   2. MenuBarExtra — a quick-glance popover that also opens the window.
//
// `LSUIElement` is still set in Info.plist (project.yml), so the process starts
// as `.accessory` (no Dock icon). `AppDelegate.applicationDidFinishLaunching`
// flips it to `.regular` so the primary window foregrounds with a Dock icon on
// launch — the documented fix for "window opens behind everything" in menu-bar
// apps (see CLAUDE.md › Opening windows from an LSUIElement app). The
// MenuBarExtra keeps working in either activation policy.

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
                .onAppear { viewModel.start() }
        }
        // Native unified titlebar+toolbar (NavigationSplitView supplies the
        // sidebar toggle, title/subtitle, and toolbar items). No hidden titlebar
        // — we want the real system chrome now.
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 940)
        .commands {
            // Native "Settings…" app-menu item + ⌘, — opens the AppKit-hosted
            // SettingsWindowController (a SwiftUI `Settings` scene is avoided in
            // this LSUIElement app).
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsWindowController.show(viewModel: viewModel)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // Quick-glance surface: the menu bar popover, with an "Open Main
        // Window" shortcut prepended (MenuBarRootView).
        MenuBarExtra("Mac Monitor", systemImage: "hexagon.fill") {
            MenuBarRootView()
                .environmentObject(viewModel)
                .onAppear { viewModel.start() }
        }
        .menuBarExtraStyle(.window)
        // Settings is shown via AppKit NSWindow (see SettingsWindowController).
    }
}

/// Handles the activation-policy dance an `LSUIElement` app needs to show a
/// real window, plus reopening the window on Dock-icon click.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Become a regular app so the primary window can foreground + get a
        // Dock icon. Without this, the WindowGroup opens behind other apps and
        // can't be brought forward (no Dock icon to click).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock-icon click with no visible window → bring the Overview back.
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }
}
