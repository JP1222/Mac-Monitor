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

let port: UInt16 = UInt16(ProcessInfo.processInfo.environment["MM_AGENT_PORT"] ?? "8765") ?? 8765

print("[macmonitor-agent] starting on port \(port)")

let server = HTTPServer(port: port)
do {
    try server.start()
} catch {
    print("[macmonitor-agent] failed to start: \(error)")
    exit(1)
}

// Keep the process alive — NWListener's queue is not the main runloop.
RunLoop.main.run()
