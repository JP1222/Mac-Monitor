// DashboardViewModel.swift
//
// Orchestrates the refresh loop:
//
//   ┌──────────────┐    ┌────────────────┐
//   │ GitHubClient │ ─┐  │  AgentClient   │
//   └──────────────┘  │  └────────────────┘
//                     ▼          │
//              ┌──────────────────▼─────┐
//              │  composeSnapshot()     │   computes aggregateState,
//              │                        │   merges runners + devices + recent
//              └──────────┬─────────────┘
//                         ▼
//                ┌─────────────────┐
//                │  SnapshotStore  │ → @Published snapshot (popover)
//                │  (App Group)    │ → WidgetCenter.reloadTimelines()
//                └─────────────────┘
//
// Every `refreshInterval` seconds the timer fires `Task { await refresh() }`.
// The popover observes `snapshot` via `@Published`; widgets pull from
// SnapshotStore on their own schedule.

import Foundation
import Combine

@MainActor
public final class DashboardViewModel: ObservableObject {

    // MARK: - Public state

    @Published public private(set) var snapshot: DashboardSnapshot
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var lastError: String?

    /// Set when a user-initiated action (Prune cache / Restart) finishes.
    /// Auto-cleared after `actionToastDuration` seconds. Drives a green
    /// toast banner in the popover so users get visible confirmation that
    /// the action actually happened.
    @Published public private(set) var lastActionToast: String?
    @Published public private(set) var isPerformingAction = false
    private let actionToastDuration: TimeInterval = 4

    // MARK: - Dependencies

    private let github: GitHubClienting
    private let agent: AgentClienting
    /// Initial refresh interval from constructor. After `start()` this is
    /// superseded by `UserSettings.refreshIntervalSeconds` and changes when
    /// the user picks a different interval in Settings.
    private let initialRefreshInterval: TimeInterval

    private var timerCancellable: AnyCancellable?
    private var settingsObserver: AnyCancellable?

    public init(
        github: GitHubClienting = MockGitHubClient(),
        agent: AgentClienting = MockAgentClient(),
        refreshInterval: TimeInterval = 15
    ) {
        self.github = github
        self.agent = agent
        self.initialRefreshInterval = refreshInterval
        // Seed from disk so the popover and widgets render instantly on launch.
        self.snapshot = SnapshotStore.readOrMock()
    }

    // MARK: - Lifecycle

    /// Start the refresh timer. Call from `MacMonitorApp.init()` or on first
    /// popover open. When the Touch ID gate is enabled, first prompts for
    /// biometric auth — only proceeds to fetching after the user authorizes.
    public func start() {
        Task { [weak self] in
            // If gate enabled and not yet unlocked, prompt before fetching.
            if UserSettings.touchIDGateEnabled {
                let ok = await KeychainStore.unlockSession(
                    reason: "Mac Monitor needs to read your GitHub token to fetch build status"
                )
                if !ok {
                    await MainActor.run {
                        self?.lastError = "Touch ID required. Click the refresh icon to try again."
                    }
                    return
                }
            }
            await self?.refresh()
            await MainActor.run { self?.restartTimer() }
        }

        // Listen for Settings changes — repo list edit / interval picker /
        // iCloud sync from another device. Cheap re-subscribe is fine; debounce
        // could be added later if Settings emits rapidly.
        settingsObserver = NotificationCenter.default
            .publisher(for: UserSettings.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.restartTimer()
                Task { [weak self] in await self?.refresh() }
            }
    }

    public func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
        settingsObserver?.cancel()
        settingsObserver = nil
    }

    private func restartTimer() {
        timerCancellable?.cancel()
        let interval = TimeInterval(UserSettings.refreshIntervalSeconds)
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in await self?.refresh() }
            }
    }

    // MARK: - Refresh pipeline

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        // composeSnapshot is per-endpoint-resilient so it never throws, but
        // it CAN return a degraded snapshot if e.g. the PAT is missing or
        // every API call 401s. Surface a user-facing message in that case.
        let composed = await composeSnapshot()
        self.snapshot = composed
        SnapshotStore.write(composed)

        // Notify on new failures (deduped inside the service).
        await NotificationService.shared.notifyFailures(in: composed)

        // Heuristic: if we ended up with zero runners + zero recent runs and
        // we DO have repos configured, something fetch-side is wrong. The
        // most common culprit is missing/expired PAT or scope mismatch.
        if composed.runners.isEmpty && composed.recent.isEmpty
            && !composed.repositories.isEmpty {
            if KeychainStore.readGitHubToken() == nil {
                self.lastError = "No GitHub token in Keychain. Open Settings to add one."
            } else {
                self.lastError = "GitHub returned no data. Check your PAT scope covers \(composed.repositories.map(\.slug).joined(separator: ", "))."
            }
        } else {
            self.lastError = nil
        }
    }

    /// Public so the PopoverHeader's banner dismiss button can clear it.
    public func dismissError() { lastError = nil }

    private func composeSnapshot() async -> DashboardSnapshot {
        // Repos come from UserSettings (iCloud-synced). Devices currently come
        // from the mock (until the local agent ships).
        let repositories: [Repository] = UserSettings.repositorySlugs.compactMap { slug -> Repository? in
            let parts = slug.split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return Repository(owner: String(parts[0]), name: String(parts[1]))
        }
        let resolvedRepos = repositories.isEmpty
            ? DashboardSnapshot.mock.repositories
            : repositories
        let devices = snapshot.devices.isEmpty
            ? DashboardSnapshot.mock.devices
            : snapshot.devices

        // Capture into local constants so the task-group closures don't have
        // to capture `self`. Both protocols are `Sendable` so the locals can
        // safely cross the actor boundary into the detached child tasks.
        let github = self.github
        let agent = self.agent

        // Fan out to GitHub for each repository.
        //
        // IMPORTANT: each per-repo fetch is wrapped in `try? await` so one
        // failing call doesn't cancel the whole sibling task group. The most
        // common failure is GitHub Actions runners endpoint returning 403
        // ("Resource not accessible by personal access token") when the PAT
        // lacks Administration:Read — but that's an OPTIONAL data source.
        // Queue / recent runs / device snapshots should still show even when
        // runners can't be enumerated. Throwing a single error used to take
        // out the entire dashboard.
        async let runnersTask = withTaskGroup(of: [Runner].self) { group -> [Runner] in
            for repo in resolvedRepos {
                group.addTask { (try? await github.fetchRunners(for: repo)) ?? [] }
            }
            return await group.reduce(into: []) { $0.append(contentsOf: $1) }
        }
        async let queueTask = withTaskGroup(of: [QueueItem].self) { group -> [QueueItem] in
            for repo in resolvedRepos {
                group.addTask { (try? await github.fetchQueuedJobs(for: repo)) ?? [] }
            }
            return await group.reduce(into: []) { $0.append(contentsOf: $1) }
        }
        async let recentTask = withTaskGroup(of: [RecentRun].self) { group -> [RecentRun] in
            for repo in resolvedRepos {
                group.addTask { (try? await github.fetchRecentRuns(for: repo, limit: 10)) ?? [] }
            }
            return await group.reduce(into: []) { $0.append(contentsOf: $1) }
        }

        // Fan out to agents for each device.
        async let deviceSnapshotsTask = withTaskGroup(of: DeviceSnapshot?.self) { group -> [DeviceSnapshot] in
            for device in devices {
                group.addTask { try? await agent.fetchSnapshot(for: device) }
            }
            return await group.reduce(into: []) { acc, snap in
                if let snap { acc.append(snap) }
            }
        }

        let runnersFromAPI = await runnersTask
        let queue = await queueTask
        let recent = await recentTask
            .sorted { $0.finishedAt > $1.finishedAt }
        let deviceSnapshots = await deviceSnapshotsTask

        // Pull in-progress jobs (for currently-building runners) AND a map
        // of each runner's most-recent completed job (for idle/offline
        // runners). Both are independent of the runner list endpoint —
        // GitHub doesn't denormalize that data, so we stitch it client-side.
        async let inProgressJobsTask = withTaskGroup(of: [WorkflowJob].self) { group -> [WorkflowJob] in
            for repo in resolvedRepos {
                group.addTask { (try? await github.fetchInProgressJobs(for: repo)) ?? [] }
            }
            return await group.reduce(into: []) { $0.append(contentsOf: $1) }
        }
        async let lastJobsTask = withTaskGroup(of: [String: LastJobSummary].self) { group -> [String: LastJobSummary] in
            for repo in resolvedRepos {
                group.addTask { (try? await github.fetchLastJobsByRunner(for: repo, scanRuns: 20)) ?? [:] }
            }
            // Merge maps from all repos; if same runner_name appears in multiple
            // repos keep the newest.
            return await group.reduce(into: [:]) { acc, partial in
                for (name, summary) in partial {
                    if let existing = acc[name], existing.finishedAt >= summary.finishedAt {
                        continue
                    }
                    acc[name] = summary
                }
            }
        }
        let availableJobs = await inProgressJobsTask
        let lastJobsByRunner = await lastJobsTask

        // Build per-workflow historical average durations from the recent
        // success runs. Used to give each in-progress job a real progress
        // estimate (elapsed/avg) instead of the hardcoded 50% placeholder.
        var avgDurationByWorkflow: [String: Int] = [:]
        let successfulByWorkflow = Dictionary(grouping: recent.filter { $0.result == .success }, by: { $0.workflow })
        for (workflow, runs) in successfulByWorkflow where !runs.isEmpty {
            let sample = runs.prefix(10)   // last 10 successful runs
            avgDurationByWorkflow[workflow] = sample.map { $0.durationSeconds }.reduce(0, +) / sample.count
        }

        // Index in-progress jobs by runner_name for precise matching. Falls
        // back to a queue of unassigned jobs (jobs whose runner_name isn't
        // in our known runner list, OR jobs without runner_name at all) so
        // the second busy runner without a matching job still gets SOMETHING
        // to display.
        var jobsByRunner: [String: WorkflowJob] = [:]
        var unassigned: [WorkflowJob] = []
        for job in availableJobs {
            if let name = job.runnerName, !name.isEmpty {
                jobsByRunner[name] = job
            } else {
                unassigned.append(job)
            }
        }

        let runners = runnersFromAPI.map { runner -> Runner in
            var attached = runner
            // Building? Attach the matching in-progress job — first by exact
            // runner_name (the truth from GitHub), fall back to the
            // unassigned queue if no name match.
            if runner.state == .building {
                var job: WorkflowJob? = jobsByRunner[runner.name]
                if job == nil, !unassigned.isEmpty {
                    job = unassigned.removeFirst()
                }
                if var j = job {
                    let avg = avgDurationByWorkflow[j.workflow]
                    j.progress = j.estimatedProgress(historicalAvgSeconds: avg)
                    j.etaSeconds = j.estimatedEtaSeconds(historicalAvgSeconds: avg)
                    attached.currentJob = j
                }
            }
            // Always try to attach lastJob if we have one for this runner —
            // makes idle/offline cards informative instead of empty.
            if let last = lastJobsByRunner[runner.name] {
                attached.lastJob = last
            }
            return attached
        }

        let aggregate = DashboardSnapshot.computeAggregateState(
            runners: runners,
            queue: queue,
            recent: recent,
            deviceSnapshots: deviceSnapshots
        )

        return DashboardSnapshot(
            generatedAt: Date(),
            repositories: resolvedRepos,
            devices: devices,
            runners: runners,
            queue: queue,
            recent: recent,
            deviceSnapshots: deviceSnapshots,
            aggregateState: aggregate
        )
    }

    // MARK: - Actions

    public func restartRunner(on device: Device) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await agent.restartRunner(on: device)
            showActionToast("Runners restarted")
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func pruneCache(on device: Device) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await agent.pruneCache(on: device)
            showActionToast("BuildKit cache pruned")
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func showActionToast(_ message: String) {
        lastActionToast = message
        // Auto-dismiss. Capture the message to detect if a NEW toast
        // arrived in the interim — don't clear someone else's text.
        let captured = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(actionToastDuration * 1_000_000_000))
            if self?.lastActionToast == captured { self?.lastActionToast = nil }
        }
    }

    public func dismissToast() { lastActionToast = nil }
}
