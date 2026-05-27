// WidgetHeader.swift
//
// Shared header row at the top of every widget size — gold brand mark + small
// uppercase title + accent dot in the top-right. Direct port of DWHeader.

import SwiftUI

public struct WidgetHeader: View {
    public let title: String
    public let accent: DashboardSnapshot.AggregateState

    public init(title: String, accent: DashboardSnapshot.AggregateState) {
        self.title = title
        self.accent = accent
    }

    public var body: some View {
        HStack(spacing: 6) {
            RunnerBrandGlyph(size: 16)
            Text(title).mmEyebrow()
            Spacer()
            StatusDot(aggregate: accent, pulse: accent == .building, size: 6)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 0, trailing: 14))
    }
}
