// AgentClient.swift
//
// Talks to the local agent running on each Mac mini. The agent's contract
// (HTTP) is being designed in a separate phase — this stub describes the
// shape so the dashboard wiring can land first.
//
// Expected agent endpoints (running on the mini, reachable at e.g.
// http://studio.local:8080):
//
//   GET /health        → JSON DeviceSnapshot
//   POST /actions/restart-runner  → kicks `launchctl kickstart`
//   POST /actions/prune-cache     → `docker buildx prune -f`

import Foundation

public protocol AgentClienting: Sendable {
    func fetchSnapshot(for device: Device) async throws -> DeviceSnapshot
    func restartRunner(on device: Device) async throws
    func pruneCache(on device: Device) async throws
}

public struct MockAgentClient: AgentClienting {
    public init() {}
    public func fetchSnapshot(for device: Device) async throws -> DeviceSnapshot {
        // Same disk shape as the JSX prototype.
        DashboardSnapshot.mock.deviceSnapshots.first(where: { $0.deviceID == device.id })
            ?? DashboardSnapshot.mock.deviceSnapshots[0]
    }
    public func restartRunner(on device: Device) async throws {}
    public func pruneCache(on device: Device) async throws {}
}

/// Real HTTP client — points at `http://\(device.host):8080`. Plug in real
/// decoding when the agent's contract is fixed.
public struct AgentClient: AgentClienting {
    public let session: URLSession
    public let port: Int

    public init(session: URLSession = .shared, port: Int = 8080) {
        self.session = session
        self.port = port
    }

    private func endpoint(_ path: String, on device: Device) -> URL? {
        URL(string: "http://\(device.host):\(port)\(path)")
    }

    public func fetchSnapshot(for device: Device) async throws -> DeviceSnapshot {
        // TODO: real call. For now return the mock so the UI renders.
        try await MockAgentClient().fetchSnapshot(for: device)
    }

    public func restartRunner(on device: Device) async throws {
        try await MockAgentClient().restartRunner(on: device)
    }

    public func pruneCache(on device: Device) async throws {
        try await MockAgentClient().pruneCache(on: device)
    }
}
