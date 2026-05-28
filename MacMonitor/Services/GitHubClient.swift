// GitHubClient.swift
//
// Real GitHub Actions REST client. Decodes the API's snake_case JSON into
// dedicated DTOs (`APIRunner`, `APIWorkflowRun`, `APIWorkflowJob`) and bridges
// them to our domain models. Keeping the DTOs internal means the domain
// models stay clean and the JSON-shape decisions never leak past this file.
//
// Endpoints we call:
//
//   GET /repos/{owner}/{repo}/actions/runners
//   GET /repos/{owner}/{repo}/actions/runs?status=in_progress&per_page=20
//   GET /repos/{owner}/{repo}/actions/runs?status=queued&per_page=20
//   GET /repos/{owner}/{repo}/actions/runs?per_page=20
//   GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs   (per in-progress run)
//
// All authenticated as `Authorization: Bearer <PAT>`. We read the PAT from
// KeychainStore on every call so token rotation takes effect without restart.

import Foundation

public protocol GitHubClienting: Sendable {
    func fetchRunners(for repository: Repository) async throws -> [Runner]
    func fetchInProgressJobs(for repository: Repository) async throws -> [WorkflowJob]
    func fetchQueuedJobs(for repository: Repository) async throws -> [QueueItem]
    func fetchRecentRuns(for repository: Repository, limit: Int) async throws -> [RecentRun]
    /// Per-runner most-recent completed job. Keyed by `runner_name` (matches
    /// `Runner.name`). Returned map only contains runners that actually ran a
    /// job in the scanned window — missing keys = no recent activity.
    func fetchLastJobsByRunner(for repository: Repository, scanRuns: Int) async throws -> [String: LastJobSummary]
}

// MARK: - Mock implementation

/// Returns the same shape of data MM_RUNNERS / MM_QUEUE / MM_RECENT held in
/// the JSX prototype. Use this for tests, previews, and as a fallback when
/// no PAT is configured.
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
    public func fetchLastJobsByRunner(for repository: Repository, scanRuns: Int) async throws -> [String: LastJobSummary] {
        Dictionary(uniqueKeysWithValues: DashboardSnapshot.mock.runners.compactMap { r -> (String, LastJobSummary)? in
            guard let lj = r.lastJob else { return nil }
            return (r.name, lj)
        })
    }
}

// MARK: - Real implementation

public struct GitHubClient: GitHubClienting {

    public enum Error: Swift.Error, LocalizedError {
        case missingToken
        case http(Int, String?)
        case invalidURL

        public var errorDescription: String? {
            switch self {
            case .missingToken: return "No GitHub PAT in Keychain. Open Settings to add one."
            case .http(let code, let body):
                return "GitHub API returned \(code)" + (body.map { ": \($0)" } ?? "")
            case .invalidURL: return "Failed to construct GitHub URL"
            }
        }
    }

    public let session: URLSession
    /// Token provider. Defaults to KeychainStore but can be overridden in tests.
    /// `@Sendable` so this struct can stay Sendable for use inside task groups.
    public let tokenProvider: @Sendable () -> String?

    public init(
        session: URLSession = .shared,
        tokenProvider: @escaping @Sendable () -> String? = { KeychainStore.readGitHubToken() }
    ) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // MARK: - Endpoint construction

    private func endpoint(_ path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        var components = URLComponents(string: "https://api.github.com" + path)
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw Error.invalidURL }

        guard let token = tokenProvider(), !token.isEmpty else { throw Error.missingToken }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("MacMonitor/0.1", forHTTPHeaderField: "User-Agent")
        return req
    }

    private func decode<T: Decodable>(_ type: T.Type, from req: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw Error.http(-1, nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(200), encoding: .utf8)
            throw Error.http(http.statusCode, snippet)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - GitHub endpoints

    public func fetchRunners(for repository: Repository) async throws -> [Runner] {
        let req = try endpoint("/repos/\(repository.slug)/actions/runners")
        let payload = try await decode(APIRunnersResponse.self, from: req)
        return payload.runners.map { $0.toDomain(deviceID: "local") }
    }

    public func fetchInProgressJobs(for repository: Repository) async throws -> [WorkflowJob] {
        // List in-progress runs, then per run pull its jobs (because a run
        // can contain multiple parallel jobs). For the MVP we only surface
        // jobs that are themselves "in_progress" — queued/completed ones are
        // covered by the other endpoints.
        let runsReq = try endpoint(
            "/repos/\(repository.slug)/actions/runs",
            queryItems: [
                URLQueryItem(name: "status",   value: "in_progress"),
                URLQueryItem(name: "per_page", value: "20"),
            ]
        )
        let runs = try await decode(APIRunsResponse.self, from: runsReq).workflow_runs

        var jobs: [WorkflowJob] = []
        try await withThrowingTaskGroup(of: [WorkflowJob].self) { group in
            for run in runs {
                group.addTask {
                    let req = try endpoint("/repos/\(repository.slug)/actions/runs/\(run.id)/jobs")
                    let payload = try await decode(APIJobsResponse.self, from: req)
                    return payload.jobs
                        .filter { $0.status == "in_progress" }
                        .map { $0.toDomain(run: run, repository: repository) }
                }
            }
            for try await batch in group { jobs.append(contentsOf: batch) }
        }
        return jobs
    }

    public func fetchQueuedJobs(for repository: Repository) async throws -> [QueueItem] {
        let req = try endpoint(
            "/repos/\(repository.slug)/actions/runs",
            queryItems: [
                URLQueryItem(name: "status",   value: "queued"),
                URLQueryItem(name: "per_page", value: "20"),
            ]
        )
        let runs = try await decode(APIRunsResponse.self, from: req).workflow_runs
        return runs.map { $0.toQueueItem(repository: repository) }
    }

    public func fetchRecentRuns(for repository: Repository, limit: Int) async throws -> [RecentRun] {
        // Fetch MORE than `limit` because we filter out skipped runs (which
        // are usually conditional notify-on-failure workflows that do
        // nothing on a healthy main — high frequency, zero signal). Without
        // overfetching we could end up with fewer than `limit` rows in the
        // popover.
        let fetchCount = min(100, max(limit * 3, 20))
        let req = try endpoint(
            "/repos/\(repository.slug)/actions/runs",
            queryItems: [
                URLQueryItem(name: "per_page", value: String(fetchCount)),
            ]
        )
        let runs = try await decode(APIRunsResponse.self, from: req).workflow_runs
        // We include in-progress runs too — they map to `.building` and show
        // a spinner glyph in the popover. This makes the dogfood loop feel
        // immediate: push commit → CI starts → popover lights up within the
        // next refresh tick, instead of waiting for completion.
        return runs
            // Drop skipped runs (path filters, scheduled no-ops, conditional
            // workflows that didn't meet their `if:` clause). They contain
            // no actionable signal but inflate the row count.
            .filter { $0.conclusion != "skipped" }
            .prefix(limit)
            .map { $0.toRecentRun() }
    }

    public func fetchLastJobsByRunner(for repository: Repository, scanRuns: Int) async throws -> [String: LastJobSummary] {
        // 1. Pull the most recent COMPLETED runs (skip in-progress — those
        //    have no completion time so they can't represent "last job").
        //    Scan more than we strictly need because not every run uses a
        //    self-hosted runner (Discord notify, lint-only, etc.).
        let req = try endpoint(
            "/repos/\(repository.slug)/actions/runs",
            queryItems: [
                URLQueryItem(name: "status",   value: "completed"),
                URLQueryItem(name: "per_page", value: String(min(100, max(1, scanRuns)))),
            ]
        )
        let runs = try await decode(APIRunsResponse.self, from: req).workflow_runs

        // 2. Concurrently fetch jobs for every run.
        var allJobs: [APIWorkflowJob] = []
        await withTaskGroup(of: [APIWorkflowJob].self) { group in
            for run in runs {
                group.addTask {
                    do {
                        let r = try endpoint("/repos/\(repository.slug)/actions/runs/\(run.id)/jobs")
                        return try await decode(APIJobsResponse.self, from: r).jobs
                    } catch {
                        return []
                    }
                }
            }
            for await batch in group { allJobs.append(contentsOf: batch) }
        }

        // 3. Group by runner_name, keep the most recently completed job per runner.
        var result: [String: LastJobSummary] = [:]
        for job in allJobs {
            guard let runnerName = job.runner_name, !runnerName.isEmpty,
                  let completedAt = job.completed_at,
                  let startedAt = job.started_at else { continue }
            let summary = LastJobSummary(
                result: job.toJobResult(),
                finishedAt: completedAt,
                durationSeconds: max(1, Int(completedAt.timeIntervalSince(startedAt)))
            )
            if let existing = result[runnerName], existing.finishedAt >= summary.finishedAt {
                continue
            }
            result[runnerName] = summary
        }
        return result
    }
}

// MARK: - GitHub REST DTOs

/// Wrapper struct because GitHub returns `{ "total_count": N, "runners": [...] }`.
private struct APIRunnersResponse: Decodable { let runners: [APIRunner] }
private struct APIRunsResponse:    Decodable { let workflow_runs: [APIWorkflowRun] }
private struct APIJobsResponse:    Decodable { let jobs: [APIWorkflowJob] }

private struct APIRunner: Decodable {
    let id: Int
    let name: String
    let status: String       // "online" | "offline"
    let busy: Bool
    let labels: [APIRunnerLabel]

    struct APIRunnerLabel: Decodable { let name: String }

    func toDomain(deviceID: String) -> Runner {
        Runner(
            id: String(id),
            name: name,
            label: name,
            deviceID: deviceID,
            labels: labels.map { $0.name },
            status: status == "online" ? .online : .offline,
            state: status == "online" ? (busy ? .building : .idle) : .offline,
            currentJob: nil,           // populated separately by fetchInProgressJobs
            lastJob: nil,
            lastHeartbeat: Date()
        )
    }
}

private struct APIWorkflowRun: Decodable {
    let id: Int
    let name: String?
    let head_branch: String
    let head_sha: String
    let status: String         // "queued" | "in_progress" | "completed"
    let conclusion: String?    // "success" | "failure" | "cancelled" | nil
    let created_at: Date
    let updated_at: Date
    let run_started_at: Date?
    let html_url: URL
    let display_title: String?
    let event: String
    let pull_requests: [APIPullRequestRef]?

    struct APIPullRequestRef: Decodable { let number: Int }

    func toQueueItem(repository: Repository) -> QueueItem {
        QueueItem(
            jobID: String(id),
            repository: repository.slug,
            workflow: name ?? display_title ?? "workflow",
            pullRequest: pull_requests?.first?.number,
            branch: head_branch,
            enqueuedAt: created_at
        )
    }

    func toRecentRun() -> RecentRun {
        let result: JobResult
        switch conclusion {
        case "success":  result = .success
        case "failure":  result = .failure
        case "cancelled":result = .cancelled
        case "skipped":  result = .skipped
        default:         result = .building
        }
        let started = run_started_at ?? created_at
        return RecentRun(
            result: result,
            workflow: name ?? display_title ?? "workflow",
            app: nil,
            branch: head_branch,
            commitSHA: String(head_sha.prefix(7)),
            durationSeconds: max(1, Int(updated_at.timeIntervalSince(started))),
            finishedAt: updated_at,
            failureReason: nil,
            htmlURL: html_url
        )
    }
}

private struct APIWorkflowJob: Decodable {
    let id: Int
    let run_id: Int
    let name: String
    let status: String         // "queued" | "in_progress" | "completed"
    let conclusion: String?
    let started_at: Date?
    let completed_at: Date?
    let html_url: URL
    /// GitHub fills this on jobs that ran on a self-hosted runner. Null for
    /// jobs that ran on cloud runners (or never ran).
    let runner_name: String?

    func toJobResult() -> JobResult {
        switch conclusion {
        case "success":  return .success
        case "failure":  return .failure
        case "cancelled":return .cancelled
        case "skipped":  return .skipped
        default:         return .building
        }
    }

    func toDomain(run: APIWorkflowRun, repository: Repository) -> WorkflowJob {
        // GitHub doesn't report a real "% complete" — we report 0.5 as a
        // conservative placeholder. ViewModel re-derives a real % from
        // historical avg duration if available.
        WorkflowJob(
            id: String(id),
            workflow: run.name ?? run.display_title ?? "workflow",
            app: nil,
            repository: repository.slug,
            branch: run.head_branch,
            pullRequest: run.pull_requests?.first?.number,
            commitSHA: String(run.head_sha.prefix(7)),
            step: name,
            progress: 0.5,
            startedAt: started_at ?? Date(),
            etaSeconds: nil,
            runID: run.id,
            runURL: html_url,
            runnerName: runner_name
        )
    }
}
