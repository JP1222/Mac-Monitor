// RecentRunRowView.swift
//
// Single row in the "Recent runs" panel. Port of MBARecentRow.

import SwiftUI

public struct RecentRunRowView: View {
    public let run: RecentRun
    @State private var isHovering = false

    public init(run: RecentRun) { self.run = run }

    public var body: some View {
        Button(action: openInBrowser) {
            HStack(spacing: 8) {
                ResultGlyph(result: run.result, size: 18)
                Text(run.branch).mmMono(size: 11.5, weight: .semibold, color: MMTokens.ink)
                Text("·")
                    .font(MMFont.rounded(size: 10.5))
                    .foregroundStyle(MMTokens.inkFaint)
                Text(run.workflow)
                    .font(MMFont.rounded(size: 11.5))
                    .foregroundStyle(MMTokens.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(run.durationPretty).mmMono(size: 11.5)
                Text(run.whenRelative())
                    .font(MMFont.rounded(size: 10.5))
                    .foregroundStyle(MMTokens.inkSoft)
                    .frame(width: 46, alignment: .trailing)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? MMTokens.rowHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(run.htmlURL?.absoluteString ?? "")
        .onHover { isHovering = $0 }
        .disabled(run.htmlURL == nil)
    }

    private func openInBrowser() {
        guard let url = run.htmlURL else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }
}

#if canImport(AppKit)
import AppKit
#endif
