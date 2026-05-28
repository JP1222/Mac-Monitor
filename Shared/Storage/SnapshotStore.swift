// SnapshotStore.swift
//
// The IPC channel between the menu bar app (writer) and the WidgetKit
// extension (reader). Uses a JSON FILE inside the App Group container
// (NOT `UserDefaults`) because:
//
//   1. Sandboxed widget extensions can't reliably read App Group
//      `UserDefaults` via `cfprefsd` — macOS rejects with
//      "accessing preferences outside an application's container requires
//      user-preference-read or file-read-data sandbox access".
//      `containerURL(forSecurityApplicationGroupIdentifier:)` on the same
//      group ID is sandbox-permitted for both processes, so file I/O works.
//   2. Atomic write semantics via `Data.write(to:, options: .atomic)` —
//      writer doesn't need locks; reader sees either old-full or new-full,
//      never half-written.
//   3. Survives any future grow in snapshot size (UserDefaults gets unhappy
//      past ~1 MB; files are unbounded).
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

    /// File name for the JSON snapshot inside the App Group container.
    public static let snapshotFilename = "dashboard.snapshot.v1.json"

    /// Widget kind name — used by `WidgetCenter.reloadTimelines(ofKind:)` to
    /// target our widgets specifically.
    public static let widgetKind = "MacMonitorWidgets"

    /// `Library/Application Support/` under the App Group container — the
    /// canonical place for app-private persistent data per Apple's guidance.
    /// Created on first write.
    private static var snapshotURL: URL? {
        guard let container = containerURL else { return nil }
        return container
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(snapshotFilename)
    }

    // MARK: - Read

    /// Read the latest snapshot, or `nil` if none has been written yet (first
    /// launch) or if the JSON is incompatible with the current schema version.
    public static func read() -> DashboardSnapshot? {
        guard let url = snapshotURL else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
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
        guard let url = snapshotURL else {
            #if DEBUG
            print("[SnapshotStore] no App Group container — check entitlements")
            #endif
            return
        }

        // Ensure the directory exists (first write of a fresh install).
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(snapshot)
            // .atomic = write to temp file then rename → readers never see a
            // half-written file. Critical when the widget process polls.
            try data.write(to: url, options: .atomic)
            reloadWidgets()
        } catch {
            #if DEBUG
            print("[SnapshotStore] encode/write failed: \(error)")
            #endif
        }
    }

    /// Debounce window for widget reloads. macOS chronod (the widget host
    /// daemon) treats too-frequent reloadTimelines calls as suspicious and
    /// can throttle / drop them. 5s is a comfortable floor that still feels
    /// responsive to user-driven changes (Settings save, manual refresh).
    private static let widgetReloadDebounceSeconds: TimeInterval = 5
    private static var lastWidgetReload: Date = .distantPast
    private static var pendingWidgetReload: DispatchWorkItem?

    private static func reloadWidgets() {
        #if canImport(WidgetKit)
        // write() is "safe to call from any thread", but lastWidgetReload /
        // pendingWidgetReload are unsynchronized statics. Hop to main so every
        // read/write of them (and the WidgetCenter call + the debounce work
        // item, which also runs on main) is serialized on one queue regardless
        // of the caller's thread — no torn reads, no leaked/uncancelled items.
        DispatchQueue.main.async {
            // Cancel any pending fire, schedule a fresh one. If snapshots get
            // written 10 times in 1 second only the LAST schedule actually
            // hits WidgetCenter.
            pendingWidgetReload?.cancel()
            let elapsed = Date().timeIntervalSince(lastWidgetReload)
            let delay = max(0, widgetReloadDebounceSeconds - elapsed)
            let work = DispatchWorkItem {
                WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
                lastWidgetReload = Date()
            }
            pendingWidgetReload = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
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

    /// Shared secret for authenticating mutating requests to the local
    /// `MacMonitorAgent`. Generated once on first call and persisted (0600)
    /// in the App Group container at `<container>/agent-token`; the
    /// (non-sandboxed) agent reads the same file by absolute path and rejects
    /// POSTs whose `Authorization: Bearer` header doesn't match. Returns nil
    /// only if the App Group container is unavailable.
    @discardableResult
    public static func agentToken() -> String? {
        guard let container = containerURL else { return nil }
        let url = container.appendingPathComponent("agent-token")
        if let data = try? Data(contentsOf: url),
           let existing = String(data: data, encoding: .utf8)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        // First run — 32 random bytes as hex, persisted owner-read/write only.
        let token = (0..<32)
            .map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }
            .joined()
        do {
            try Data(token.utf8).write(to: url, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path
            )
        } catch {
            #if DEBUG
            print("[SnapshotStore] agent-token write failed: \(error)")
            #endif
            return nil
        }
        return token
    }

    public static var isAppGroupConfigured: Bool {
        containerURL != nil
    }

    /// Human-readable path to the snapshot file (or "—" if container missing).
    /// Useful for surfacing in Settings → diagnostics.
    public static var snapshotPath: String {
        snapshotURL?.path ?? "—"
    }
}
