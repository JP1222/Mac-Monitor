// SnapshotStore.swift
//
// The IPC channel between the menu bar app (writer) and the WidgetKit
// extension (reader). Uses `UserDefaults(suiteName:)` against the App Group
// because:
//
//   1. The snapshot is small (a few KB JSON) — well under UserDefaults' soft
//      limit.
//   2. UserDefaults is atomic per-key; we don't need to coordinate file locks.
//   3. The widget process re-reads on every `getTimeline(in:)` call, so we
//      pay for the disk hit at most once per refresh tick.
//
// If snapshots ever grow past ~500KB, switch to writing a JSON file inside
// `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)`.
//
// The App Group ID is the single string we MUST keep in sync between
// SnapshotStore, both .entitlements files, and project.yml. There is no
// runtime check that catches a typo here — instead the widget will silently
// read an empty container.

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public enum SnapshotStore {

    /// Must match `com.apple.security.application-groups` in BOTH
    /// `MacMonitor.entitlements` and `MacMonitorWidgets.entitlements`.
    public static let appGroupID = "group.com.jp1222.macmonitor"

    /// Key inside the App Group's UserDefaults suite.
    public static let snapshotKey = "dashboard.snapshot.v1"

    /// Widget kind name — used by `WidgetCenter.reloadTimelines(ofKind:)` to
    /// target our widgets specifically.
    public static let widgetKind = "MacMonitorWidgets"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // MARK: - Read

    /// Read the latest snapshot, or `nil` if none has been written yet (first
    /// launch) or if the JSON is incompatible with the current schema version.
    public static func read() -> DashboardSnapshot? {
        guard let defaults, let data = defaults.data(forKey: snapshotKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let snapshot = try decoder.decode(DashboardSnapshot.self, from: data)
            // Reject snapshots from a newer app rev — better to show the mock
            // placeholder than crash on a missing field.
            guard snapshot.version <= DashboardSnapshot.currentVersion else {
                return nil
            }
            return snapshot
        } catch {
            #if DEBUG
            print("[SnapshotStore] decode failed: \(error)")
            #endif
            return nil
        }
    }

    /// Read the latest snapshot or fall back to the mock. Widgets call this so
    /// they always have something to render — no empty states.
    public static func readOrMock() -> DashboardSnapshot {
        read() ?? .mock
    }

    // MARK: - Write

    /// Persist a snapshot and ping WidgetCenter so widgets pick it up on the
    /// next system refresh cycle. Safe to call from any thread.
    public static func write(_ snapshot: DashboardSnapshot) {
        guard let defaults else {
            #if DEBUG
            print("[SnapshotStore] no App Group container — check entitlements")
            #endif
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(snapshot)
            defaults.set(data, forKey: snapshotKey)
            reloadWidgets()
        } catch {
            #if DEBUG
            print("[SnapshotStore] encode failed: \(error)")
            #endif
        }
    }

    private static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        #endif
    }

    // MARK: - Diagnostics

    /// Returns the App Group's container directory, or nil if the entitlement
    /// isn't granted. Useful for surfacing setup errors in Settings.
    public static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )
    }

    public static var isAppGroupConfigured: Bool {
        containerURL != nil
    }
}
