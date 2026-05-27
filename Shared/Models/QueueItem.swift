// QueueItem.swift
//
// A workflow job waiting for an available runner. Distinct from WorkflowJob
// because queued jobs have no runner assignment, no progress, no step.

import Foundation

public struct QueueItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(repository)#\(jobID)" }
    public let jobID: String
    public let repository: String      // slug
    public let workflow: String
    public let pullRequest: Int?
    public let branch: String
    public let enqueuedAt: Date

    public init(
        jobID: String,
        repository: String,
        workflow: String,
        pullRequest: Int? = nil,
        branch: String,
        enqueuedAt: Date
    ) {
        self.jobID = jobID
        self.repository = repository
        self.workflow = workflow
        self.pullRequest = pullRequest
        self.branch = branch
        self.enqueuedAt = enqueuedAt
    }

    public func waitingSeconds(now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(enqueuedAt)))
    }

    /// Pretty "0m 38s" form used in the queue row.
    public func waitingPretty(now: Date = Date()) -> String {
        let s = waitingSeconds(now: now)
        return "\(s / 60)m \(String(format: "%02d", s % 60))s"
    }
}
