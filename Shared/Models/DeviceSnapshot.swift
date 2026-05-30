// DeviceSnapshot.swift
//
// A point-in-time health reading from the local agent running on a Device.
// Snapshots are cached in the App Group so widgets render even when the menu
// bar app hasn't refreshed in a while. We keep this struct intentionally
// flat — Codable JSON in UserDefaults works best when the schema is shallow.

import Foundation

public enum ThermalState: String, Codable, Hashable, Sendable {
    case nominal, fair, serious, critical
}

public struct DiskUsage: Codable, Hashable, Identifiable, Sendable {
    /// Three-layer disk model: APFS host, OrbStack VM, BuildKit cache.
    public enum Layer: String, Codable, Sendable {
        case apfsHost
        case orbStackVM
        case buildKitCache
        case other
    }

    public enum State: String, Codable, Sendable { case ok, warn, critical }

    public var id: String { label }
    public let layer: Layer
    public let label: String         // "APFS host"
    public let sub: String           // "/ on macOS"
    public let usedBytes: Int64
    public let totalBytes: Int64
    public let state: State

    public init(
        layer: Layer,
        label: String,
        sub: String,
        usedBytes: Int64,
        totalBytes: Int64,
        state: State
    ) {
        self.layer = layer
        self.label = label
        self.sub = sub
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.state = state
    }

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }

    /// Recomputed tone for the disk meter. The agent's `state` is the
    /// authoritative source but UI thresholds may want to override.
    public var displayTone: State {
        let pct = usedFraction
        if pct > 0.85 { return .critical }
        if pct > 0.7  { return .warn }
        return .ok
    }
}

public struct DeviceSnapshot: Codable, Identifiable, Hashable, Sendable {
    public var id: String { deviceID }
    public let deviceID: String
    public let capturedAt: Date

    // System health
    public let cpuLoad: Double                // 0...1 (normalized 1-minute load)
    public let memoryPressurePercent: Double  // 0...100
    /// Physical memory in use, in bytes. Optional so snapshots written by an
    /// older agent build (which only sent `memoryPressurePercent`) still decode
    /// — the fleet card falls back to the percent when these are nil. New agent
    /// builds always populate both.
    public let memoryUsedBytes: Int64?
    public let memoryTotalBytes: Int64?
    public let thermalState: ThermalState
    public let uptimeSeconds: TimeInterval

    // Build infrastructure
    public let orbStackRunning: Bool
    public let dockerContainersRunning: Int
    public let disks: [DiskUsage]

    public let agentVersion: String

    public init(
        deviceID: String,
        capturedAt: Date,
        cpuLoad: Double,
        memoryPressurePercent: Double,
        memoryUsedBytes: Int64? = nil,
        memoryTotalBytes: Int64? = nil,
        thermalState: ThermalState,
        uptimeSeconds: TimeInterval,
        orbStackRunning: Bool,
        dockerContainersRunning: Int,
        disks: [DiskUsage],
        agentVersion: String
    ) {
        self.deviceID = deviceID
        self.capturedAt = capturedAt
        self.cpuLoad = cpuLoad
        self.memoryPressurePercent = memoryPressurePercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.thermalState = thermalState
        self.uptimeSeconds = uptimeSeconds
        self.orbStackRunning = orbStackRunning
        self.dockerContainersRunning = dockerContainersRunning
        self.disks = disks
        self.agentVersion = agentVersion
    }

    /// Age of this snapshot. Anything over a few minutes is "stale" and the UI
    /// should fade or warn.
    public func ageSeconds(now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(capturedAt)
    }

    // MARK: - Fleet-card derivations

    /// "4.8/16" style memory string in GB, or nil when the agent didn't report
    /// byte-level memory (older build). Uses decimal GB (÷1e9) to match the way
    /// macOS reports RAM ("16 GB"), not GiB.
    public func memoryUsedTotalGB() -> (used: Double, total: Double)? {
        guard let used = memoryUsedBytes, let total = memoryTotalBytes, total > 0 else { return nil }
        return (Double(used) / 1_000_000_000, Double(total) / 1_000_000_000)
    }

    /// BuildKit cache fullness 0...1 against its design threshold (the layer's
    /// own totalBytes is pinned to 30 GB by the collector). Drives the fleet
    /// card "Cache" stat. Nil when no cache layer is present.
    public var buildKitCacheFraction: Double? {
        disks.first { $0.layer == .buildKitCache }?.usedFraction
    }
}
