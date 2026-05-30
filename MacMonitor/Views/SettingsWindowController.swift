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
        hosting.preferredContentSize = NSSize(width: 520, height: 600)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .resizable],
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

/// On Settings close, demote back to `.accessory` ONLY when no main window is
/// open — so the menu-bar-only case returns to no-Dock-icon, but closing
/// Settings while the primary Overview window is up does NOT yank the Dock icon
/// (and focus) out from under it.
@MainActor
private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowDelegate()
    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        let hasMainWindow = NSApp.windows.contains {
            $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && $0.canBecomeMain
        }
        if !hasMainWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
