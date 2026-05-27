// RunnersTimelineProvider.swift
//
// TimelineProvider for the Runners widget. Reads cached DashboardSnapshot
// from the App Group on every refresh — by design we NEVER call GitHub here.
// The host app is the source of truth; widgets are pure readers.
//
// Refresh policy: every 30 seconds. The host app also pings
// `WidgetCenter.reloadTimelines(ofKind:)` whenever it writes a new snapshot,
// so the timer is a backstop in case the host isn't running (system reboot,
// user quit the app).

import WidgetKit

public struct DashboardEntry: TimelineEntry {
    public let date: Date
    public let snapshot: DashboardSnapshot
}

public struct RunnersTimelineProvider: TimelineProvider {

    public init() {}

    /// Synchronous, no IO — shown briefly in the widget gallery.
    public func placeholder(in context: Context) -> DashboardEntry {
        DashboardEntry(date: Date(), snapshot: .mock)
    }

    /// Called when the system needs a one-off preview (e.g. widget editor).
    public func getSnapshot(in context: Context, completion: @escaping (DashboardEntry) -> Void) {
        let snap = SnapshotStore.readOrMock()
        completion(DashboardEntry(date: Date(), snapshot: snap))
    }

    /// The real refresh. Read from App Group, then schedule the next refresh.
    public func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardEntry>) -> Void) {
        let snap = SnapshotStore.readOrMock()
        let now = Date()
        let entry = DashboardEntry(date: now, snapshot: snap)
        // Refresh in 30s, OR sooner if the host app writes (via WidgetCenter).
        let nextRefresh = now.addingTimeInterval(30)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}
