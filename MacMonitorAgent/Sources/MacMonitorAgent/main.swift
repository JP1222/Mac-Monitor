// main.swift — MacMonitorAgent entry point.
//
// Single-file Swift HTTP server on `Network` framework's NWListener. No
// external dependencies. Two routes:
//
//   GET /health   → JSON DeviceSnapshot
//   GET /         → human-readable status page
//
// Sandbox: this binary is NOT sandboxed (it's a normal command-line
// tool). It needs to call `statvfs`, `getloadavg`, and shell out to
// `docker`/`du` — sandbox would block these.

import Foundation
import Network

// Parse MM_AGENT_PORT; treat empty/unparseable/0 as "use the default". Port 0
// is a valid UInt16 but means "OS-assigned ephemeral" — which would bind a
// random port and make the agent unreachable at the expected 8765.
let parsedPort = UInt16(ProcessInfo.processInfo.environment["MM_AGENT_PORT"] ?? "") ?? 0
let port: UInt16 = parsedPort == 0 ? 8765 : parsedPort

// Bind host: loopback by default (only this machine can reach it). Set
// MM_AGENT_BIND to a specific interface address — e.g. a Tailscale IP — to
// expose the agent on that private network so another Mac can read /health.
let bindHost: String? = (ProcessInfo.processInfo.environment["MM_AGENT_BIND"]?
    .trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }

print("[macmonitor-agent] starting on \(bindHost ?? "127.0.0.1"):\(port)")

let server = HTTPServer(port: port, bindHost: bindHost)
do {
    try server.start()
} catch {
    print("[macmonitor-agent] failed to start: \(error)")
    exit(1)
}

// Keep the process alive — NWListener's queue is not the main runloop.
RunLoop.main.run()
