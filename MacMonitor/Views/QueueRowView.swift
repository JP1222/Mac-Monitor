// QueueRowView.swift
//
// Single row in the "Queue · N waiting" panel. Port of MBAQueueRow.

import SwiftUI

public struct QueueRowView: View {
    public let item: QueueItem
    public let isLongest: Bool

    public init(item: QueueItem, isLongest: Bool = false) {
        self.item = item
        self.isLongest = isLongest
    }

    public var body: some View {
        HStack(spacing: 8) {
            ResultGlyph(result: .queued, size: 18)
            if let pr = item.pullRequest {
                Text("#\(pr)").mmMono(size: 11.5, weight: .semibold, color: MMTokens.ink)
                    .fixedSize()
            }
            // Single line — long branch names truncate instead of wrapping to
            // 2–3 lines (which blew up the popover height).
            Text(item.branch).mmMono(size: 11.5)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text(item.workflow)
                .font(MMFont.rounded(size: 11))
                .foregroundStyle(MMTokens.inkMuted)
                .lineLimit(1)
                .fixedSize()
            Text(item.waitingPretty())
                .font(MMFont.rounded(size: 10.5, weight: isLongest ? .bold : .medium))
                .foregroundStyle(isLongest ? MMTokens.amber : MMTokens.inkSoft)
                .fixedSize()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
    }
}
