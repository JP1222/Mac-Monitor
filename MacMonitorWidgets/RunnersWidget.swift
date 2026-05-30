// RunnersWidget.swift
//
// The widget declaration. Supports systemSmall / systemMedium / systemLarge
// (macOS desktop widget families on Sonoma+). The single `RunnersWidgetView`
// switches layout by `widgetFamily` — keeps configuration in one place.

import SwiftUI
import WidgetKit

public struct RunnersWidget: Widget {
    public let kind = SnapshotStore.widgetKind

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RunnersTimelineProvider()) { entry in
            RunnersWidgetView(entry: entry)
                // macOS 14 / iOS 17+ — let the system manage the widget bg.
                .containerBackground(for: .widget) { widgetBackground }
        }
        .configurationDisplayName("Yolo Runners")
        .description("Self-hosted runners status, queue, and disk pressure.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }

    /// Direct port of the `DWShell` gradient in desktop-widget.jsx —
    /// rgba(34,34,40,0.94) → rgba(20,20,24,0.94).
    @ViewBuilder
    private var widgetBackground: some View {
        LinearGradient(
            colors: [
                MMTokens.rgba(34, 34, 40, 0.94),
                MMTokens.rgba(20, 20, 24, 0.94),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

public struct RunnersWidgetView: View {
    @Environment(\.widgetFamily) private var family
    public let entry: DashboardEntry

    public init(entry: DashboardEntry) {
        self.entry = entry
    }

    public var body: some View {
        familyView
            // Desktop widgets stay dark-glass regardless of system appearance —
            // they're ambient surfaces over the wallpaper, where the dark look
            // reads consistently. Pinning here also keeps the now-adaptive
            // MMTokens resolving to their dark variants inside the widget.
            .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var familyView: some View {
        switch family {
        case .systemSmall:  SmallWidgetView(snapshot: entry.snapshot)
        case .systemMedium: MediumWidgetView(snapshot: entry.snapshot)
        case .systemLarge:  LargeWidgetView(snapshot: entry.snapshot)
        default:            SmallWidgetView(snapshot: entry.snapshot)
        }
    }
}

#Preview("Small", as: .systemSmall) {
    RunnersWidget()
} timeline: {
    DashboardEntry(date: .now, snapshot: .mock)
}

#Preview("Medium", as: .systemMedium) {
    RunnersWidget()
} timeline: {
    DashboardEntry(date: .now, snapshot: .mock)
}

#Preview("Large", as: .systemLarge) {
    RunnersWidget()
} timeline: {
    DashboardEntry(date: .now, snapshot: .mock)
}
