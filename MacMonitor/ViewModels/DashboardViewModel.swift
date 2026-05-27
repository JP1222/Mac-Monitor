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

    // MARK: - Dependencies

    private let github: GitHubClienting
    private let agent: AgentClienting
    private let refreshInterval: TimeInterval

    private var timerCancellable: AnyCancellable?

    public init(
        github: GitHubClienting = MockGitHubClient(),
        agent: AgentClienting = MockAgentClient(),
        refreshInterval: TimeInterval = 15
    ) {
        self.github = github
        self.agent = agent
        self.refreshInterval = refreshInterval
        // Seed from disk so the popover and widgets render instantly on launch.
        self.snapshot = SnapshotStore.readOrMock()
    }

    // MARK: - Lifecycle

    /// Start the refresh timer. Call from `MacMonitorApp.init()` or on first
    /// popover open.
    public func start() {
        // Fire once immediately so the UI updates without waiting `refreshInterval`.
        Task { await refresh() }

        timerCancellable = Timer.publish(every: refreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in await self?.refresh() }
            }
    }

    public func stop() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    // MARK: - Refresh pipeline

    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let composed = await composeSnapshot()
        self.snapshot = composed
        self.lastError = nil
        SnapshotStore.write(composed)
    }

    private func composeSnapshot() async -> DashboardSnapshot {
        // Use whatever the previous snapshot knew about — topology rarely
        // changes mid-session, so we treat repositories/devices as durable.
        let repositories = snapshot.repositories.isEmpty
            ? DashboardSnapshot.mock.repositories
            : snapshot.repositories
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
            for repo in repositories {
                group.addTask { (try? await github.fetchRunners(for: repo)) ?? [] }
            }
            return await group.reduce(into: []) { $0.append(contentsOf: $1) }
        }
        async let queueTask = withTaskGroup(of: [QueueItem].self) { group -> [QueueItem] in
            for repo in repositories {
                group.addTask { (try? await github.fetchQueuedJobs(for: repo)) ?? [] }
            }
            return await group.reduce(into: []) { $0.append(contentsOf: $1) }
        }
        async let recentTask = withTaskGroup(of: [RecentRun].self) { group -> [RecentRun] in
            for repo in repositories {
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

        // Also pull in-progress jobs and stitch them onto busy runners. The
        // runners endpoint reports `busy: true` but doesn't tell us WHICH
        // job a runner is on; we approximate by handing the first available
        // job to the first busy runner.
        async let jobsTask = withTaskGroup(of: [WorkflowJob].self) { group -> [WorkflowJob] in
            for repo in repositories {
                group.addTask { (try? await github.fetchInProgressJobs(for: repo)) ?? [] }
            }
            return await group.reduce(into: []) { $0.append(contentsOf: $1) }
        }
        var availableJobs = await jobsTask

        let runners = runnersFromAPI.map { runner -> Runner in
            guard runner.state == .building, !availableJobs.isEmpty else { return runner }
            var attached = runner
            attached.currentJob = availableJobs.removeFirst()
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
            repositories: repositories,
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
        do { try await agent.restartRunner(on: device); await refresh() }
        catch { lastError = error.localizedDescription }
    }

    public func pruneCache(on device: Device) async {
        do { try await agent.pruneCache(on: device); await refresh() }
        catch { lastError = error.localizedDescription }
    }
}
