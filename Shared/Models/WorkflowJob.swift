// WorkflowJob.swift
//
// A GitHub Actions workflow job — the unit that runs ON a runner. One workflow
// run can contain many jobs; we surface the job because that's the level the
// runner is busy at.

import Foundation

public enum JobResult: String, Codable, Hashable, Sendable {
    case success
    case failure
    case cancelled
    case skipped
    case building
    case queued
}

public struct WorkflowJob: Codable, Identifiable, Hashable, Sendable {
    /// GitHub's numeric job ID, stringified for stability across encodings.
    public let id: String
    public var workflow: String         // "build-images"
    public var app: String?             // logical sub-app, e.g. "kds-api"
    public var repository: String       // "owner/name" — slug form
    public var branch: String
    public var pullRequest: Int?
    public var commitSHA: String
    public var step: String?            // current step's display name
    public var progress: Double         // 0...1 (estimated by the agent)
    public var startedAt: Date
    public var etaSeconds: Int?
    public var runID: Int
    public var runURL: URL
    /// Self-hosted runner the job is executing on. Optional because
    /// cloud-runner jobs leave it nil and so does the queued-state.
    /// Used by DashboardViewModel to stitch the job to its Runner card
    /// by name match.
    public var runnerName: String?

    public init(
        id: String,
        workflow: String,
        app: String? = nil,
        repository: String,
        branch: String,
        pullRequest: Int? = nil,
        commitSHA: String,
        step: String? = nil,
        progress: Double,
        startedAt: Date,
        etaSeconds: Int? = nil,
        runID: Int,
        runURL: URL,
        runnerName: String? = nil
    ) {
        self.id = id
        self.workflow = workflow
        self.app = app
        self.repository = repository
        self.branch = branch
        self.pullRequest = pullRequest
        self.commitSHA = commitSHA
        self.step = step
        self.progress = max(0, min(1, progress))
        self.startedAt = startedAt
        self.etaSeconds = etaSeconds
        self.runID = runID
        self.runURL = runURL
        self.runnerName = runnerName
    }

    public func elapsedSeconds(now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(startedAt)))
    }

    /// Estimate progress 0...1 from historical average duration of the same
    /// workflow. GitHub Actions doesn't expose a real "percent complete" —
    /// the closest approximation is `elapsed / average_of_last_N_successful_runs`.
    /// Capped at 0.95 so the bar never reads 100% before the build actually
    /// finishes (which would feel like a lie when ETA blows past).
    public func estimatedProgress(historicalAvgSeconds: Int?, now: Date = Date()) -> Double {
        guard let avg = historicalAvgSeconds, avg > 0 else { return 0.5 }
        let elapsed = elapsedSeconds(now: now)
        return min(0.95, max(0.02, Double(elapsed) / Double(avg)))
    }

    /// Same calculation, but returns remaining seconds. Negative when the
    /// build is running longer than its historical average (returns 0).
    public func estimatedEtaSeconds(historicalAvgSeconds: Int?, now: Date = Date()) -> Int? {
        guard let avg = historicalAvgSeconds, avg > 0 else { return nil }
        return max(0, avg - elapsedSeconds(now: now))
    }
}
