// SettingsWindowController.swift
//
// AppKit window host for SettingsView. Bypasses SwiftUI's `Window` scene,
// which doesn't work in LSUIElement apps (the activation policy
// `.accessory` blocks Window scenes from opening). We:
//
//   1. Promote the app to `.regular` policy so the window can take focus.
//   2. Construct an NSWindow with an `NSHostingController` hosting the
//      SwiftUI SettingsView (same view, just hosted via AppKit).
//   3. On close, demote back to `.accessory` so the app returns to its
//      menu-bar-only state.
//
// Singleton-by-static — there's only one Settings window per process. Re-
// opening focuses the existing window.

import AppKit
import SwiftUI

@MainActor
enum SettingsWindowController {

    private static var window: NSWindow?

    /// Open or focus the Settings window. Call this from the gear button.
    static func show(viewModel: DashboardViewModel) {
        // Promote to regular so the window can claim focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsView().environmentObject(viewModel)
        )
        // Force the desired size: our SettingsView declares frame 460x480.
        hosting.preferredContentSize = NSSize(width: 460, height: 480)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Mac Monitor Settings"
        newWindow.contentViewController = hosting
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.delegate = SettingsWindowDelegate.shared

        window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
    }
}

/// Demote app activation policy back to `.accessory` when the user closes
/// the Settings window — otherwise the Dock would keep showing our icon.
@MainActor
private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowDelegate()
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
