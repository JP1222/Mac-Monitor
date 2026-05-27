// RecentRun.swift
//
// Historical workflow run shown in the "Recent runs" section. We store the
// minimum a row needs to render — no live data, just frozen summary.

import Foundation

public struct RecentRun: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(workflow)-\(commitSHA)" }
    public let result: JobResult
    public let workflow: String         // "build-images · kds-web"
    public let app: String?
    public let branch: String
    public let commitSHA: String
    public let durationSeconds: Int
    public let finishedAt: Date
    public let failureReason: String?   // shown when result == .failure

    public init(
        result: JobResult,
        workflow: String,
        app: String? = nil,
        branch: String,
        commitSHA: String,
        durationSeconds: Int,
        finishedAt: Date,
        failureReason: String? = nil
    ) {
        self.result = result
        self.workflow = workflow
        self.app = app
        self.branch = branch
        self.commitSHA = commitSHA
        self.durationSeconds = durationSeconds
        self.finishedAt = finishedAt
        self.failureReason = failureReason
    }

    /// Pretty duration: `3m 14s`.
    public var durationPretty: String {
        "\(durationSeconds / 60)m \(String(format: "%02d", durationSeconds % 60))s"
    }

    /// Pretty relative time: `2m ago`, `1h ago`.
    public func whenRelative(now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(finishedAt)))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}
