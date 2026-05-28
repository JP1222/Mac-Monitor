// DeviceSnapshot.swift
//
// Copy of Shared/Models/DeviceSnapshot.swift duplicated here so the agent
// binary stays self-contained (no SPM dependency on the SwiftUI app's
// project). Keep the JSON shape IDENTICAL to the shared version — the
// MacMonitor AgentClient decodes against the shared model.

import Foundation

enum ThermalState: String, Codable {
    case nominal, fair, serious, critical
}

struct DiskUsage: Codable {
    enum Layer: String, Codable {
        case apfsHost, orbStackVM, buildKitCache, other
    }
    enum State: String, Codable { case ok, warn, critical }

    let layer: Layer
    let label: String
    let sub: String
    let usedBytes: Int64
    let totalBytes: Int64
    let state: State
}

struct DeviceSnapshot: Codable {
    let deviceID: String
    let capturedAt: Date
    let cpuLoad: Double
    let memoryPressurePercent: Double
    let thermalState: ThermalState
    let uptimeSeconds: TimeInterval
    let orbStackRunning: Bool
    let dockerContainersRunning: Int
    let disks: [DiskUsage]
    let agentVersion: String
}
