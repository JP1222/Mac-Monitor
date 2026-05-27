// GitHubClient.swift
//
// Thin abstraction over the GitHub REST API surface we need:
//   - Workflow runs in progress (to populate WorkflowJob)
//   - Self-hosted runners on each watched repository
//   - Recent runs for the history panel
//
// The real implementation will use URLSession + a PAT stored in Keychain. For
// now we ship a Mock that returns the same sample data the JSX prototype
// used — this lets the menu bar app render end-to-end before any credentials
// are configured.

import Foundation

public protocol GitHubClienting: Sendable {
    func fetchRunners(for repository: Repository) async throws -> [Runner]
    func fetchInProgressJobs(for repository: Repository) async throws -> [WorkflowJob]
    func fetchQueuedJobs(for repository: Repository) async throws -> [QueueItem]
    func fetchRecentRuns(for repository: Repository, limit: Int) async throws -> [RecentRun]
}

// MARK: - Mock implementation

/// Returns the same shape of data MM_RUNNERS / MM_QUEUE / MM_RECENT held in
/// the JSX prototype. Use this until a real PAT-backed client is wired in.
public struct MockGitHubClient: GitHubClienting {
    public init() {}

    public func fetchRunners(for repository: Repository) async throws -> [Runner] {
        DashboardSnapshot.mock.runners
    }
    public func fetchInProgressJobs(for repository: Repository) async throws -> [WorkflowJob] {
        DashboardSnapshot.mock.runners.compactMap { $0.currentJob }
    }
    public func fetchQueuedJobs(for repository: Repository) async throws -> [QueueItem] {
        DashboardSnapshot.mock.queue
    }
    public func fetchRecentRuns(for repository: Repository, limit: Int) async throws -> [RecentRun] {
        Array(DashboardSnapshot.mock.recent.prefix(limit))
    }
}

// MARK: - Real implementation (skeleton)

/// Real GitHub client — fill in the REST calls when ready. Endpoints documented:
///   GET /repos/{owner}/{repo}/actions/runners
///   GET /repos/{owner}/{repo}/actions/runs?status=in_progress
///   GET /repos/{owner}/{repo}/actions/runs?status=queued
///   GET /repos/{owner}/{repo}/actions/runs?per_page=N
///
/// Authentication: Bearer token (PAT) read from Keychain. Store via
/// `SecItemAdd` keyed by service "MacMonitor.GitHubToken".
public struct GitHubClient: GitHubClienting {
    public let session: URLSession
    /// `@Sendable` so this whole struct can conform to `Sendable` — required
    /// for it to be safely captured into the detached child tasks the
    /// DashboardViewModel spawns.
    public let token: @Sendable () -> String?

    public init(
        session: URLSession = .shared,
        token: @escaping @Sendable () -> String? = { ProcessInfo.processInfo.environment["GITHUB_TOKEN"] }
    ) {
        self.session = session
        self.token = token
    }

    public func fetchRunners(for repository: Repository) async throws -> [Runner] {
        // TODO: implement REST call. Decode GitHub's runner shape:
        //   { id: Int, name: String, status: "online"|"offline",
        //     busy: Bool, labels: [{ name: String }] }
        // and bridge to our Runner model.
        try await MockGitHubClient().fetchRunners(for: repository)
    }

    public func fetchInProgressJobs(for repository: Repository) async throws -> [WorkflowJob] {
        try await MockGitHubClient().fetchInProgressJobs(for: repository)
    }

    public func fetchQueuedJobs(for repository: Repository) async throws -> [QueueItem] {
        try await MockGitHubClient().fetchQueuedJobs(for: repository)
    }

    public func fetchRecentRuns(for repository: Repository, limit: Int) async throws -> [RecentRun] {
        try await MockGitHubClient().fetchRecentRuns(for: repository, limit: limit)
    }
}
