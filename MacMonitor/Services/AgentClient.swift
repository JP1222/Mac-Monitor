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

/// Real HTTP client that talks to MacMonitorAgent (see ../MacMonitorAgent/).
/// The agent is a standalone Swift executable installed as a LaunchAgent on
/// each Mac in the build farm. We POST nothing — agent only exposes a GET
/// `/health` endpoint that returns the current DeviceSnapshot.
///
/// Behavior on connection failure: throws `AgentError.unreachable`. Caller
/// (DashboardViewModel) catches and falls back to the mock so the popover
/// keeps rendering with last-known data + an error banner.
public struct AgentClient: AgentClienting {

    public enum AgentError: Swift.Error, LocalizedError {
        case unreachable(String)
        case badStatus(Int)
        /// Carries the agent's own failure message from the JSON body — e.g.
        /// "No actions.runner.* LaunchAgents found…" — so the user sees WHY,
        /// not a bare status code.
        case actionFailed(String)
        case decode

        public var errorDescription: String? {
            switch self {
            case .unreachable(let host): return "Agent at \(host) unreachable. Is `macmonitor-agent` running?"
            case .badStatus(let code):   return "Agent returned HTTP \(code)"
            case .actionFailed(let msg): return msg
            case .decode:                return "Agent returned an unexpected payload"
            }
        }
    }

    /// The agent's action response body (`{ ok, message, affected }`). We only
    /// need the message for surfacing failures.
    private struct ActionResult: Decodable {
        let ok: Bool
        let message: String?
    }

    public let session: URLSession
    public let port: Int

    public init(session: URLSession = nil ?? .shared, port: Int = 8765) {
        self.session = session
        self.port = port
    }

    private func endpoint(_ path: String, on device: Device) throws -> URL {
        guard let url = URL(string: "http://\(device.host):\(port)\(path)") else {
            throw AgentError.unreachable(device.host)
        }
        return url
    }

    public func fetchSnapshot(for device: Device) async throws -> DeviceSnapshot {
        let url = try endpoint("/health", on: device)
        var req = URLRequest(url: url)
        // 12s timeout — agent shells out to `docker system df`, which under
        // launchd's minimal env / a busy Docker can take several seconds (and
        // the agent gives it a 6s budget before falling back). Too tight a
        // timeout makes the Storage section silently empty or forces the
        // agent's BuildKit value into the host-side metadata fallback.
        req.timeoutInterval = 12
        req.setValue("MacMonitor/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AgentError.unreachable(device.host)
        }
        guard let http = response as? HTTPURLResponse else { throw AgentError.decode }
        guard (200..<300).contains(http.statusCode) else { throw AgentError.badStatus(http.statusCode) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DeviceSnapshot.self, from: data)
    }

    public func restartRunner(on device: Device) async throws {
        try await postAction(path: "/actions/restart-runners", on: device)
    }

    public func pruneCache(on device: Device) async throws {
        try await postAction(path: "/actions/prune-cache", on: device)
    }

    private func postAction(path: String, on device: Device) async throws {
        let url = try endpoint(path, on: device)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60   // prune can take a while
        req.setValue("MacMonitor/0.1", forHTTPHeaderField: "User-Agent")
        // Authenticate the mutating request with the shared secret the agent
        // reads from the App Group container. Without it the agent returns 401.
        if let token = SnapshotStore.agentToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AgentError.unreachable(device.host)
        }
        guard let http = response as? HTTPURLResponse else { throw AgentError.decode }
        guard (200..<300).contains(http.statusCode) else {
            // Prefer the agent's own explanation (e.g. "No actions.runner.*
            // LaunchAgents found. Install with actions-runner/svc.sh install.")
            // over a bare "HTTP 500".
            if let result = try? JSONDecoder().decode(ActionResult.self, from: data),
               let message = result.message, !message.isEmpty {
                throw AgentError.actionFailed(message)
            }
            throw AgentError.badStatus(http.statusCode)
        }
    }
}
