// Device.swift
//
// A physical Mac that hosts one or more self-hosted GitHub runners. The HTML
// mock had `host: "studio.local"` baked into Runner; we split it out because:
//
//   1. One Mac mini can host multiple runners (multi-arch, different labels).
//   2. Device health (disk, memory, thermals) is collected by the local agent
//      and applies to the host machine, not any one runner.
//   3. The menu bar UI lists runners but the desktop widget summarizes by
//      device — keeping them as separate types makes that pivot natural.

import Foundation

public struct Device: Codable, Identifiable, Hashable, Sendable {
    /// Stable ID assigned at agent enrollment, e.g. `mac-mini-1`.
    public let id: String
    /// Display name shown in the UI.
    public var label: String
    /// Network host the agent is reachable at, e.g. `studio.local`.
    public var host: String
    /// Marketing-name model, e.g. `Mac mini (M2 Pro, 2023)`.
    public var model: String?
    /// macOS version reported by the agent, e.g. `14.5`.
    public var osVersion: String?
    /// Last time the agent posted a heartbeat to the menu bar app.
    public var lastSeen: Date?

    public init(
        id: String,
        label: String,
        host: String,
        model: String? = nil,
        osVersion: String? = nil,
        lastSeen: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.host = host
        self.model = model
        self.osVersion = osVersion
        self.lastSeen = lastSeen
    }

    /// Heartbeat freshness in seconds, or `.infinity` if never seen. Useful for
    /// painting the status dot tone (mint < 30s, amber 30-120s, tomato > 120s).
    public func secondsSinceHeartbeat(now: Date = Date()) -> TimeInterval {
        guard let lastSeen else { return .infinity }
        return now.timeIntervalSince(lastSeen)
    }
}
