// MenuBarRootView.swift
//
// The menu-bar popover's content, now that the full Overview window is the
// app's primary surface. The popover stays the quick-glance view (unchanged
// `PopoverView`); this wrapper just prepends an "Open Main Window" affordance so
// the menu bar becomes a lightweight shortcut *into* the window — the shape the
// user asked for ("window primary, popover a quick-glance shortcut").

import SwiftUI
import AppKit

struct MenuBarRootView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            openWindowButton
            Divider().overlay(MMTokens.glassDivider)
            PopoverView()
                .environmentObject(viewModel)
        }
        .frame(width: 380)
        .background(.regularMaterial)   // native frosted popover surface (adapts light/dark)
        .clipShape(RoundedRectangle(cornerRadius: MMTokens.radiusPopover, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MMTokens.radiusPopover, style: .continuous)
                .stroke(MMTokens.glassBorder, lineWidth: 1)
        )
    }

    private var openWindowButton: some View {
        Button(action: openMainWindow) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [MMTokens.brand, MMTokens.brandDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: "hexagon.fill").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Open Main Window")
                        .font(MMFont.rounded(size: 13, weight: .semibold))
                        .foregroundStyle(MMTokens.ink)
                    Text("Full fleet · live build · logs")
                        .font(MMFont.rounded(size: 10.5))
                        .foregroundStyle(MMTokens.inkSoft)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(MMTokens.inkMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openMainWindow() {
        // An LSUIElement app launches `.accessory`; flip to `.regular` so the
        // window can foreground and gain a Dock icon, then open + activate.
        NSApp.setActivationPolicy(.regular)
        openWindow(id: OverviewWindowID.overview)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Shared window identifier so the scene and every opener agree on one string.
enum OverviewWindowID {
    static let overview = "overview"
}
