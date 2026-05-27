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
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(MMTokens.tomato)
                Text(message)
                    .font(MMFont.rounded(size: 11))
                    .foregroundStyle(MMTokens.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    viewModel.dismissError()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MMTokens.inkMuted)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(MMTokens.tomatoGlow)
            .overlay(alignment: .bottom) {
                Rectangle().fill(MMTokens.glassDivider).frame(height: 1)
            }
        }
    }
}
