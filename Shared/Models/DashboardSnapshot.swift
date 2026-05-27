// DashboardSnapshot.swift
//
// The single Codable blob written to the App Group by the menu bar app and
// read by the widget extension. Versioned so we can evolve the schema safely:
// older widgets that fail to decode v2 just fall back to a placeholder.

import Foundation

public struct DashboardSnapshot: Codable, Hashable, Sendable {
    /// Bump when the schema changes incompatibly. Widget falls back to mock
    /// if the on-disk version is newer than what it knows.
    public static let currentVersion = 1

    public let version: Int
    public let generatedAt: Date

    // Topology
    public let repositories: [Repository]
    public let devices: [Device]
    public let runners: [Runner]

    // Live state
    public let queue: [QueueItem]
    public let recent: [RecentRun]
    public let deviceSnapshots: [DeviceSnapshot]

    /// UI roll-up — drives the menu bar icon tint and the widget accent dot.
    /// Computed on the writer side so widgets stay trivial.
    public let aggregateState: AggregateState

    public enum AggregateState: String, Codable, Sendable {
        case idle, building, warning, failure, offline
    }

    public init(
        version: Int = DashboardSnapshot.currentVersion,
        generatedAt: Date = Date(),
        repositories: [Repository],
        devices: [Device],
        runners: [Runner],
        queue: [QueueItem],
        recent: [RecentRun],
        deviceSnapshots: [DeviceSnapshot],
        aggregateState: AggregateState
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.repositories = repositories
        self.devices = devices
        self.runners = runners
        self.queue = queue
        self.recent = recent
        self.deviceSnapshots = deviceSnapshots
        self.aggregateState = aggregateState
    }

    // MARK: - Derivations

    /// Disk meters to render in the "Storage · three-layer" section. We pull
    /// from the snapshot of whichever device has the freshest reading — for
    /// MVP that's effectively the only device the user has the agent on.
    public var primaryDisks: [DiskUsage] {
        deviceSnapshots
            .sorted { $0.capturedAt > $1.capturedAt }
            .first?.disks ?? []
    }

    public func runners(on device: Device) -> [Runner] {
        runners.filter { $0.deviceID == device.id }
    }

    public var onlineRunnerCount: Int {
        runners.filter { $0.status == .online }.count
    }

    public var buildingRunnerCount: Int {
        runners.filter { $0.state == .building }.count
    }

    public func passedInLastHour(now: Date = Date()) -> Int {
        recent.filter {
            $0.result == .success && now.timeIntervalSince($0.finishedAt) <= 3600
        }.count
    }

    public func failedInLastHour(now: Date = Date()) -> Int {
        recent.filter {
            $0.result == .failure && now.timeIntervalSince($0.finishedAt) <= 3600
        }.count
    }

    public var longestWaitingSeconds: Int {
        queue.map { $0.waitingSeconds() }.max() ?? 0
    }
}

// MARK: - Aggregate state computation

extension DashboardSnapshot {
    /// Pure function so the writer can recompute on every refresh without
    /// duplicating logic across call sites.
    public static func computeAggregateState(
        runners: [Runner],
        queue: [QueueItem],
        recent: [RecentRun],
        deviceSnapshots: [DeviceSnapshot],
        now: Date = Date()
    ) -> AggregateState {
        // Anything actively building → "building" (the most attention-grabbing
        // accent because users are usually watching for completion).
        if runners.contains(where: { $0.state == .building }) {
            return .building
        }

        // Recent failure in the last 5 minutes → "failure".
        if recent.contains(where: {
            $0.result == .failure && now.timeIntervalSince($0.finishedAt) <= 300
        }) {
            return .failure
        }

        // Any runner offline OR disk pressure critical → "warning".
        let hasOfflineRunner = runners.contains { $0.status == .offline }
        let hasCriticalDisk = deviceSnapshots.flatMap { $0.disks }.contains { $0.displayTone == .critical }
        let longQueue = queue.contains { $0.waitingSeconds(now: now) > 120 }
        if hasOfflineRunner || hasCriticalDisk || longQueue {
            return .warning
        }

        // No live runners at all → "offline" (used by the menu bar icon to
        // show a dimmed glyph instead of the green idle dot).
        if runners.isEmpty || runners.allSatisfy({ $0.status == .offline }) {
            return .offline
        }

        return .idle
    }
}
