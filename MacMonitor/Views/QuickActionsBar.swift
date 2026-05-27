// QuickActionsBar.swift
//
// Three buttons across the bottom of the popover:
//   - Actions  → opens the watched repo's Actions tab in the browser
//   - Restart  → asks the agent to restart the runner LaunchAgent
//   - Prune cache → asks the agent to drop the BuildKit cache (tinted amber)

import SwiftUI

public struct QuickActionsBar: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    public init() {}

    public var body: some View {
        HStack(spacing: 6) {
            QuickActionButton(
                systemImage: "chevron.left.forwardslash.chevron.right",
                label: "Actions",
                primary: true
            ) {
                if let url = viewModel.snapshot.repositories.first?.actionsURL {
                    #if canImport(AppKit)
                    NSWorkspace.shared.open(url)
                    #endif
                }
            }
            QuickActionButton(
                systemImage: "arrow.counterclockwise",
                label: "Restart"
            ) {
                guard let device = viewModel.snapshot.devices.first else { return }
                Task { await viewModel.restartRunner(on: device) }
            }
            QuickActionButton(
                systemImage: "trash",
                label: "Prune cache",
                tone: MMTokens.amber
            ) {
                guard let device = viewModel.snapshot.devices.first else { return }
                Task { await viewModel.pruneCache(on: device) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct QuickActionButton: View {
    let systemImage: String
    let label: String
    var tone: Color? = nil
    var primary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(MMFont.rounded(size: 11.5, weight: .semibold))
                    .kerning(-0.1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .padding(.horizontal, 10)
            .foregroundStyle(tone ?? MMTokens.ink)
            .background(buttonBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MMTokens.glassBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if primary {
            LinearGradient(
                colors: [
                    MMTokens.rgba(255, 255, 255, 0.10),
                    MMTokens.rgba(255, 255, 255, 0.03),
                ],
                startPoint: .top, endPoint: .bottom
            )
        } else {
            MMTokens.rgba(255, 255, 255, 0.04)
        }
    }
}
