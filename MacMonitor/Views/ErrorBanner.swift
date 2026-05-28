// ErrorBanner.swift
//
// Slim red strip that surfaces `DashboardViewModel.lastError` between the
// header and the scrollable section list. Dismissible — clears
// `viewModel.lastError`. Re-appears on next refresh if the underlying
// problem isn't fixed.
//
// The banner only shows when lastError is non-nil, so when everything is
// healthy there's zero visual cost.

import SwiftUI

public struct ErrorBanner: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    public init() {}

    public var body: some View {
        if let message = viewModel.lastError {
            banner(
                message: message,
                tint: MMTokens.tomato,
                background: MMTokens.tomatoGlow,
                icon: "exclamationmark.triangle.fill",
                dismiss: { viewModel.dismissError() }
            )
        } else if let toast = viewModel.lastActionToast {
            banner(
                message: toast,
                tint: MMTokens.mint,
                background: MMTokens.mintGlow,
                icon: "checkmark.circle.fill",
                dismiss: { viewModel.dismissToast() }
            )
        }
    }

    @ViewBuilder
    private func banner(
        message: String,
        tint: Color,
        background: Color,
        icon: String,
        dismiss: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tint)
            Text(message)
                .font(MMFont.rounded(size: 11))
                .foregroundStyle(MMTokens.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MMTokens.inkMuted)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MMTokens.glassDivider).frame(height: 1)
        }
    }
}
