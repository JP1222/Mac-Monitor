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
            }
            Text(item.branch).mmMono(size: 11.5)
            Spacer()
            Text(item.workflow)
                .font(MMFont.rounded(size: 11))
                .foregroundStyle(MMTokens.inkMuted)
            Text(item.waitingPretty())
                .font(MMFont.rounded(size: 10.5, weight: isLongest ? .bold : .medium))
                .foregroundStyle(isLongest ? MMTokens.amber : MMTokens.inkSoft)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
    }
}
