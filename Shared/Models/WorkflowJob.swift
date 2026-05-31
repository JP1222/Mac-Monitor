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

/// One step inside a job, straight from GitHub's `/jobs` response (each job
/// carries a real `steps[]` array). This is the genuine build progress — real
/// names, real per-step status, real timing — that replaces the old fixture
/// log lines and the fabricated 5-phase rail.
public struct WorkflowStep: Codable, Identifiable, Hashable, Sendable {
    /// GitHub's step lifecycle. `pending` is the catch-all for any not-yet-run
    /// value (GitHub may send "pending" before "queued", or omit it).
    public enum Status: String, Codable, Hashable, Sendable {
        case queued, inProgress, completed, pending
    }

    public var id: Int { number }
    public let number: Int
    public let name: String
    public let status: Status
    /// Only meaningful once `status == .completed`; nil while running/queued.
    public let conclusion: JobResult?
    public let startedAt: Date?
    public let completedAt: Date?

    public init(
        number: Int,
        name: String,
        status: Status,
        conclusion: JobResult? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.number = number
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    /// Folds status + conclusion into the shared `JobResult` palette so a step
    /// renders with the same `ResultGlyph` used in queue/recent rows. An
    /// in-progress step is `.building` (animated spinner); a completed step with
    /// no decodable conclusion is treated as `.failure`, never a perpetual spin.
    public var displayResult: JobResult {
        switch status {
        case .completed:        return conclusion ?? .failure
        case .inProgress:       return .building
        case .queued, .pending: return .queued
        }
    }

    /// Wall-clock seconds for a finished step (both timestamps present).
    /// In-progress steps return nil — the view ticks `now − startedAt` live.
    public var durationSeconds: Int? {
        guard let started = startedAt, let completed = completedAt else { return nil }
        return max(0, Int(completed.timeIntervalSince(started)))
    }
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
    /// Historical average duration (seconds) for this workflow, used to
    /// drive the live-tick progress bar and ETA countdown in the runner
    /// card. Set by `DashboardViewModel` from the avg of recent successful
    /// runs. Nil when no history exists yet — view falls back to a 50%
    /// flatline + hidden ETA rather than fabricating a number.
    ///
    /// Stored here (rather than recomputed in the view from etaSeconds +
    /// elapsed) because etaSeconds is a snapshot value; the back-derivation
    /// `avg = etaSeconds + currentElapsed` is wrong by `(currentElapsed -
    /// snapshotElapsed)`, freezing the displayed ETA at its snapshot value.
    public var historicalAvgSeconds: Int?
    public var runID: Int
    public var runURL: URL
    /// Self-hosted runner the job is executing on. Optional because
    /// cloud-runner jobs leave it nil and so does the queued-state.
    /// Used by DashboardViewModel to stitch the job to its Runner card
    /// by name match.
    public var runnerName: String?
    /// The job's real step sequence from GitHub. Optional + defaulted nil so
    /// older persisted snapshots (no `steps` key) still decode, and so the
    /// queued/cloud paths that don't carry steps stay valid.
    public var steps: [WorkflowStep]?
    /// Fan-out context for matrix builds — a run whose `Detect changed apps`
    /// job dispatches one build job per changed app, so the job count varies
    /// run to run (2 when one app changed, 7+ when everything did). These hold
    /// the parent run's total job count and how many have finished, captured
    /// from the run's full `/jobs` payload at fetch time. Optional + nil so
    /// older snapshots, single-job workflows, and cloud jobs still decode.
    /// They feed `matrixProgress`, the only progress signal that stays correct
    /// when the fan-out width changes between runs (time- and step-based
    /// estimates can't — see `matrixProgress`).
    public var runJobsTotal: Int?
    public var runJobsCompleted: Int?

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
        historicalAvgSeconds: Int? = nil,
        runID: Int,
        runURL: URL,
        runnerName: String? = nil,
        steps: [WorkflowStep]? = nil,
        runJobsTotal: Int? = nil,
        runJobsCompleted: Int? = nil
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
        self.historicalAvgSeconds = historicalAvgSeconds
        self.runID = runID
        self.runURL = runURL
        self.runnerName = runnerName
        self.steps = steps
        self.runJobsTotal = runJobsTotal
        self.runJobsCompleted = runJobsCompleted
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
        // Fallback ladder, best signal first:
        //  1. fan-out matrix → exact job-completion (survives a varying job count)
        //  2. stable single job with history → time estimate elapsed/avg
        //  3. real step-completion of the running job
        //  4. 50% flatline (no steps, no history)
        if let m = matrixProgress { return m }
        guard let avg = historicalAvgSeconds, avg > 0 else { return stepProgress ?? 0.5 }
        let elapsed = elapsedSeconds(now: now)
        return min(0.95, max(0.02, Double(elapsed) / Double(avg)))
    }

    /// Same calculation, but returns remaining seconds. Negative when the
    /// build is running longer than its historical average (returns 0).
    public func estimatedEtaSeconds(historicalAvgSeconds: Int?, now: Date = Date()) -> Int? {
        guard let avg = historicalAvgSeconds, avg > 0 else { return nil }
        return max(0, avg - elapsedSeconds(now: now))
    }

    /// Fallback progress for an in-progress job that has **no historical
    /// average** to estimate against — a brand-new or rarely-succeeding
    /// workflow (e.g. a Docker image build that runs far less often than CI,
    /// so its one success never survives the 10-run `recent` window the
    /// average is drawn from). Instead of flatlining at 50%, derive a *real*
    /// fraction from the job's live `steps[]`: GitHub reports each step's
    /// status, so completed-vs-total is genuine, monotonic, and always
    /// available for a running job — no extra API call.
    ///
    /// Returns nil when there are no steps to measure (queued/cloud jobs that
    /// carry no `steps`), so callers can chain a clean fallback ladder:
    ///   `historicalEstimate ?? stepProgress ?? 0.5`
    public var stepProgress: Double? {
        guard let steps, !steps.isEmpty else { return nil }
        // Completed steps count fully; the single in-progress step gets half
        // credit so the bar advances mid-step rather than freezing — the
        // "Build & push" step alone can run for minutes. Capped below 1.0 so
        // a job never reads 100% while its final "Complete job" / "Post …"
        // steps are still wrapping up.
        let total = Double(steps.count)
        let completed = Double(steps.filter { $0.status == .completed }.count)
        let inFlight = steps.contains { $0.status == .inProgress } ? 0.5 : 0
        return min(0.95, (completed + inFlight) / total)
    }

    /// Build progress for a fan-out matrix run, measured over the WHOLE matrix
    /// instead of one job. A matrix run's `Detect changed apps` job dispatches
    /// one build per changed app, so both obvious proxies fail:
    ///   • time-based `elapsed / historicalAvg` — the job count, and therefore
    ///     duration, changes per run; any average conflates 2-app and 7-app runs.
    ///   • single-job `stepProgress` — sawtooths, resetting toward 0 each time
    ///     the runner finishes one app and picks up the next.
    /// Job-completion is exact regardless of fan-out width:
    ///   (finished jobs + the running job's step fraction) / total jobs.
    /// Returns nil for non-matrix work (no run counts, or a lone job) so linear
    /// workflows fall through to the time/step estimates above.
    public var matrixProgress: Double? {
        guard let total = runJobsTotal, total > 1 else { return nil }
        let done = Double(runJobsCompleted ?? 0)
        // The matched in-progress job is NOT in `done` (it's still running), so
        // its step fraction is added as the partial next job — no double-count.
        // nil steps → 0, degrading cleanly to pure done/total.
        let inFlight = stepProgress ?? 0
        return min(0.99, (done + inFlight) / Double(total))
    }
}
