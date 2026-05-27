// DashboardSnapshot+Mock.swift
//
// Sample data that mirrors `shared.jsx`'s MM_RUNNERS / MM_QUEUE / MM_RECENT /
// MM_DISK exactly. Used for:
//
//   - SwiftUI #Preview blocks
//   - Widget placeholders (`Provider.placeholder` and `snapshot`)
//   - First launch before the real client has fetched anything
//   - Tests
//
// Keep this aligned with the JSX mock — if the design changes, update both.

import Foundation

extension DashboardSnapshot {

    public static let mock: DashboardSnapshot = {
        let now = Date()

        let repo = Repository(
            owner: "JP1222",
            name: "yolo-rollo",
            defaultBranch: "main"
        )

        let device = Device(
            id: "mac-mini-1",
            label: "mac-mini-1",
            host: "studio.local",
            model: "Mac mini (M2 Pro, 2023)",
            osVersion: "14.5",
            lastSeen: now.addingTimeInterval(-4)
        )

        let snapshot = DeviceSnapshot(
            deviceID: device.id,
            capturedAt: now.addingTimeInterval(-4),
            cpuLoad: 0.62,
            memoryPressurePercent: 41,
            thermalState: .nominal,
            uptimeSeconds: 3 * 24 * 3600 + 14_152,
            orbStackRunning: true,
            dockerContainersRunning: 7,
            disks: [
                DiskUsage(
                    layer: .apfsHost,
                    label: "APFS host",
                    sub: "/ on macOS",
                    usedBytes: 282 * 1_000_000_000,
                    totalBytes: 460 * 1_000_000_000,
                    state: .ok
                ),
                DiskUsage(
                    layer: .orbStackVM,
                    label: "OrbStack VM",
                    sub: "linux arm64",
                    usedBytes: 38 * 1_000_000_000,
                    totalBytes: 80 * 1_000_000_000,
                    state: .ok
                ),
                DiskUsage(
                    layer: .buildKitCache,
                    label: "BuildKit cache",
                    sub: "142 layers · docker buildx",
                    usedBytes: 23_400_000_000,
                    totalBytes: 30_000_000_000,
                    state: .warn
                ),
            ],
            agentVersion: "0.1.0"
        )

        let buildingJob = WorkflowJob(
            id: "j-9001",
            workflow: "build-images",
            app: "kds-api",
            repository: repo.slug,
            branch: "feat/clover-webhook-fanout",
            pullRequest: 247,
            commitSHA: "a4f1c2e",
            step: "docker buildx · linux/arm64",
            progress: 0.73,
            startedAt: now.addingTimeInterval(-134),
            etaSeconds: 48,
            runID: 7_812_300_001,
            runURL: URL(string: "https://github.com/JP1222/yolo-rollo/actions/runs/7812300001")!
        )

        let runners: [Runner] = [
            Runner(
                id: "r-101",
                name: "mac-mini-1",
                label: "mac-mini-1",
                deviceID: device.id,
                labels: ["self-hosted", "macOS", "arm64"],
                status: .online,
                state: .building,
                currentJob: buildingJob,
                lastJob: nil,
                lastHeartbeat: now.addingTimeInterval(-4)
            ),
            Runner(
                id: "r-102",
                name: "mac-mini-2",
                label: "mac-mini-2",
                deviceID: device.id,
                labels: ["self-hosted", "macOS", "arm64"],
                status: .online,
                state: .idle,
                currentJob: nil,
                lastJob: LastJobSummary(
                    result: .success,
                    finishedAt: now.addingTimeInterval(-180),
                    durationSeconds: 112
                ),
                lastHeartbeat: now.addingTimeInterval(-2)
            ),
        ]

        let queue: [QueueItem] = [
            QueueItem(
                jobID: "q-248",
                repository: repo.slug,
                workflow: "build-images",
                pullRequest: 248,
                branch: "fix/orbstack-disk-pressure",
                enqueuedAt: now.addingTimeInterval(-38)
            ),
            QueueItem(
                jobID: "q-251",
                repository: repo.slug,
                workflow: "test",
                pullRequest: 251,
                branch: "chore/bump-pnpm",
                enqueuedAt: now.addingTimeInterval(-12)
            ),
        ]

        let recent: [RecentRun] = [
            RecentRun(
                result: .success,
                workflow: "build-images · kds-web",
                app: "kds-web",
                branch: "main",
                commitSHA: "a4f1c2e",
                durationSeconds: 194,
                finishedAt: now.addingTimeInterval(-120)
            ),
            RecentRun(
                result: .success,
                workflow: "build-images · analytics-api",
                app: "analytics-api",
                branch: "feat/clover-webhook-fanout",
                commitSHA: "9b13ee0",
                durationSeconds: 242,
                finishedAt: now.addingTimeInterval(-1080)
            ),
            RecentRun(
                result: .failure,
                workflow: "test · kds-api",
                app: "kds-api",
                branch: "fix/passkey-csrf",
                commitSHA: "d22a8c1",
                durationSeconds: 12,
                finishedAt: now.addingTimeInterval(-2460),
                failureReason: "argon2 native bind"
            ),
            RecentRun(
                result: .success,
                workflow: "deploy · dokploy",
                app: nil,
                branch: "main",
                commitSHA: "771f4a3",
                durationSeconds: 112,
                finishedAt: now.addingTimeInterval(-3600)
            ),
            RecentRun(
                result: .success,
                workflow: "build-images · backoffice-web",
                app: "backoffice-web",
                branch: "main",
                commitSHA: "55e0b9d",
                durationSeconds: 178,
                finishedAt: now.addingTimeInterval(-7200)
            ),
        ]

        let aggregate = DashboardSnapshot.computeAggregateState(
            runners: runners,
            queue: queue,
            recent: recent,
            deviceSnapshots: [snapshot]
        )

        return DashboardSnapshot(
            generatedAt: now,
            repositories: [repo],
            devices: [device],
            runners: runners,
            queue: queue,
            recent: recent,
            deviceSnapshots: [snapshot],
            aggregateState: aggregate
        )
    }()

    /// A snapshot with everything idle — useful for previewing the "no
    /// activity" state of the menu bar icon.
    public static let mockIdle: DashboardSnapshot = {
        let base = DashboardSnapshot.mock
        let idleRunners = base.runners.map { r -> Runner in
            var copy = r
            copy.state = .idle
            copy.currentJob = nil
            return copy
        }
        return DashboardSnapshot(
            generatedAt: base.generatedAt,
            repositories: base.repositories,
            devices: base.devices,
            runners: idleRunners,
            queue: [],
            recent: base.recent,
            deviceSnapshots: base.deviceSnapshots,
            aggregateState: .idle
        )
    }()
}
