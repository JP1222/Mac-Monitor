// RecentRunRowView.swift
//
// Single row in the "Recent runs" panel. Port of MBARecentRow.

import SwiftUI

public struct RecentRunRowView: View {
    public let run: RecentRun

    public init(run: RecentRun) { self.run = run }

    public var body: some View {
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
        .padding(.horizontal, 4)
    }
}
