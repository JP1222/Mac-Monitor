// AgentToken.swift
//
// Shared-secret gate for the mutating POST endpoints. The menu-bar app
// (sandboxed) generates a random token on launch and writes it into the App
// Group container; this daemon (NOT sandboxed) reads the same file by its
// absolute path and requires a matching `Authorization: Bearer` header on
// POST. GET routes stay open.
//
// Rendezvous file:
//   ~/Library/Group Containers/group.com.jp1222.macmonitor/agent-token
//
// The group ID is hardcoded here to match `SnapshotStore.appGroupID` in the
// app's Shared module (the daemon doesn't link that module). Keep in sync.

import Foundation

enum AgentToken {

    /// Must match `SnapshotStore.appGroupID` in the app.
    private static let appGroupID = "group.com.jp1222.macmonitor"

    private static let tokenURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Group Containers/\(appGroupID)/agent-token")

    /// The token the app provisioned, or nil if the file is missing/empty
    /// (app never launched, or App Group not configured).
    static func current() -> String? {
        guard
            let data = try? Data(contentsOf: tokenURL),
            let raw = String(data: data, encoding: .utf8)
        else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// True only if a token is provisioned AND the presented value matches it.
    /// Fails closed: no provisioned token → no POST allowed.
    static func validate(_ presented: String?) -> Bool {
        guard let expected = current(), let presented, !presented.isEmpty else {
            return false
        }
        // Length check first, then a constant-time-ish full comparison to
        // avoid leaking the secret via early-exit timing.
        let a = Array(expected.utf8)
        let b = Array(presented.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}
