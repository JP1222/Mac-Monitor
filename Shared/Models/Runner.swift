// Runner.swift
//
// A GitHub self-hosted runner. The HTML mock conflates Runner + Device + Job;
// production needs all three. A Runner BELONGS_TO a Device and OPTIONALLY HAS
// a currentJob. RunnerState is a UI roll-up (idle/building/...) derived from
// GitHub's status + the job's result, computed on the writer side so widgets
// don't need any logic.

import Foundation

public enum RunnerStatus: String, Codable, Sendable {
    /// What GitHub reports for the runner registration.
    case online
    case offline
}

public enum RunnerState: String, Codable, Sendable {
    /// Roll-up state used to drive UI accents. `building` wins over everything,
    /// then `failure`, then `warning`, then `idle`, finally `offline`.
    case idle
    case building
    case warning
    case failure
    case offline
}

public struct LastJobSummary: Codable, Hashable, Sendable {
    public let result: JobResult
    public let finishedAt: Date
    public let durationSeconds: Int

    public init(result: JobResult, finishedAt: Date, durationSeconds: Int) {
        self.result = result
        self.finishedAt = finishedAt
        self.durationSeconds = durationSeconds
    }
}

public struct Runner: Codable, Identifiable, Hashable, Sendable {
    /// GitHub's numeric runner ID, stringified.
    public let id: String
    public var name: String                 // GitHub-registered name
    public var label: String                // display label ("mac-mini-1")
    public var deviceID: String             // FK → Device.id
    public var labels: [String]             // ["self-hosted", "macOS", "arm64"]
    public var status: RunnerStatus         // GitHub: online | offline
    public var state: RunnerState           // UI roll-up
    public var currentJob: WorkflowJob?     // populated when state == .building
    public var lastJob: LastJobSummary?     // populated when state == .idle/failure
    public var lastHeartbeat: Date?

    public init(
        id: String,
        name: String,
        label: String,
        deviceID: String,
        labels: [String] = ["self-hosted", "macOS"],
        status: RunnerStatus,
        state: RunnerState,
        currentJob: WorkflowJob? = nil,
        lastJob: LastJobSummary? = nil,
        lastHeartbeat: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.label = label
        self.deviceID = deviceID
        self.labels = labels
        self.status = status
        self.state = state
        self.currentJob = currentJob
        self.lastJob = lastJob
        self.lastHeartbeat = lastHeartbeat
    }

    /// Pretty heartbeat string: `4s ago`, `2m ago`, `—` if never.
    public func heartbeatRelative(now: Date = Date()) -> String {
        guard let lastHeartbeat else { return "—" }
        let seconds = Int(now.timeIntervalSince(lastHeartbeat))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
