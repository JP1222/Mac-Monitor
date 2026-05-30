// OverviewData.swift
//
// Maps the live `DashboardSnapshot` into the small view-models the Overview
// components render. Keeping this translation in one place means the views stay
// dumb (take a struct, draw it) and the "where does this number come from?"
// logic is testable in isolation — the opposite of the prototype, where every
// value was a hard-coded mock literal inlined into the JSX.

import SwiftUI

// MARK: - View models

/// One fleet card. A `Runner` joined to its host device's live stats.
struct FleetEntry: Identifiable {
    let runner: Runner
    let chip: String?         // "M2 Pro" (device model) or "arm64" (label fallback)
    let host: String
    let cpuPercent: Int?      // device cpuLoad × 100, nil when offline / no snapshot
    let memUsedGB: Double?
    let memTotalGB: Double?
    let cacheFraction: Double? // BuildKit cache fullness 0...1
    let isSelected: Bool

    var id: String { runner.id }
}

/// One KPI card in the top strip.
struct KpiMetric: Identifiable {
    let id: String
    let label: String
    let value: String
    let sub: String
    let tone: Color
    var trend: String? = nil       // "↑ 2%" — only set when truthfully derivable
    var trendTone: Color? = nil
}

/// One bar in the 24h activity sparkbar.
struct ActivityBucket: Identifiable {
    enum Kind { case success, failure, building, idle }
    let id: Int
    let kind: Kind
    let height: Double             // 0...1, scaled to the bar track height by the view
}

// MARK: - Builders

enum OverviewData {

    // MARK: Fleet

    /// Build the fleet cards for the strip. The selected runner (or the first
    /// building one, or the first overall) drives the live-build hero.
    static func fleet(from snapshot: DashboardSnapshot, selectedID: String?) -> [FleetEntry] {
        let effectiveSelection = selectedID
            ?? snapshot.runners.first(where: { $0.state == .building })?.id
            ?? snapshot.runners.first?.id

        return snapshot.runners.map { runner in
            let device = snapshot.devices.first { $0.id == runner.deviceID }
            let snap = deviceSnapshot(for: runner, in: snapshot)
            let offline = runner.status == .offline || runner.state == .offline

            // chip: prefer the marketing model ("M2 Pro"); fall back to the
            // first meaningful runner label (e.g. "arm64") so the pill isn't
            // empty with real GitHub data, which never carries a chip name.
            let chip = device?.model
                ?? runner.labels.first { $0 != "self-hosted" && $0 != "macOS" && $0 != "X64" }

            let mem = snap?.memoryUsedTotalGB()
            return FleetEntry(
                runner: runner,
                chip: chip,
                host: device?.host ?? snap?.deviceID ?? "—",
                cpuPercent: offline ? nil : snap.map { Int(($0.cpuLoad * 100).rounded()) },
                memUsedGB: offline ? nil : mem?.used,
                memTotalGB: offline ? nil : mem?.total,
                cacheFraction: offline ? nil : snap?.buildKitCacheFraction,
                isSelected: runner.id == effectiveSelection
            )
        }
    }

    /// The runner the hero should show: the live selection, else first building,
    /// else first runner. Returns nil only when there are no runners at all.
    static func heroRunner(from snapshot: DashboardSnapshot, selectedID: String?) -> Runner? {
        if let id = selectedID, let r = snapshot.runners.first(where: { $0.id == id }) { return r }
        return snapshot.runners.first(where: { $0.state == .building }) ?? snapshot.runners.first
    }

    /// Exact device-snapshot match for a runner, falling back to the freshest
    /// snapshot. Rationale: `GitHubClient` stamps every runner `deviceID:
    /// "local"` while the agent stamps the snapshot with the Mac's computer
    /// name — they never join by ID today. With one Mac hosting all runners,
    /// "they share the host's stats" is literally true, so the freshest
    /// snapshot is the correct fallback (same approach as `primaryDisks`).
    static func deviceSnapshot(for runner: Runner, in snapshot: DashboardSnapshot) -> DeviceSnapshot? {
        if let exact = snapshot.deviceSnapshots.first(where: { $0.deviceID == runner.deviceID }) {
            return exact
        }
        return snapshot.deviceSnapshots.max { $0.capturedAt < $1.capturedAt }
    }

    // MARK: KPIs

    /// The five top-strip metrics, derived from what the snapshot actually
    /// carries. Trend arrows are only attached when we can compute them
    /// truthfully — we don't fabricate "↑ 2%" deltas without a baseline.
    static func kpis(from snapshot: DashboardSnapshot, now: Date = Date()) -> [KpiMetric] {
        let recent = snapshot.recent
        let terminal = recent.filter { $0.result == .success || $0.result == .failure }
        let successes = terminal.filter { $0.result == .success }.count

        // Success rate over the runs we have.
        let rate = terminal.isEmpty ? nil : Int((Double(successes) / Double(terminal.count) * 100).rounded())

        // Today: runs finished in the last 24h, with a success/fail breakdown.
        let last24h = recent.filter { now.timeIntervalSince($0.finishedAt) <= 86_400 }
        let todaySuccess = last24h.filter { $0.result == .success }.count
        let todayFail = last24h.filter { $0.result == .failure }.count
        let todayCancel = last24h.filter { $0.result == .cancelled }.count

        // Median duration of successful runs (resistant to one slow outlier).
        let med = medianDuration(of: recent.filter { $0.result == .success })

        // BuildKit cache fullness from the primary device snapshot.
        let cacheFrac = snapshot.deviceSnapshots
            .max { $0.capturedAt < $1.capturedAt }?
            .buildKitCacheFraction

        // Queue.
        let longest = snapshot.longestWaitingSeconds

        return [
            KpiMetric(
                id: "success",
                label: "Success rate",
                value: rate.map { "\($0)%" } ?? "—",
                sub: terminal.isEmpty ? "no completed runs yet" : "last \(terminal.count) runs",
                tone: MMTokens.mint
            ),
            KpiMetric(
                id: "today",
                label: "Today",
                value: "\(last24h.count)",
                sub: "\(todaySuccess) success · \(todayFail) fail · \(todayCancel) cancelled",
                tone: MMTokens.blue
            ),
            KpiMetric(
                id: "median",
                label: "Median duration",
                value: med.map { prettyDuration($0) } ?? "—",
                sub: "successful runs · last seen",
                tone: MMTokens.amber
            ),
            KpiMetric(
                id: "cache",
                label: "Cache",
                value: cacheFrac.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                sub: "BuildKit cache used",
                tone: (cacheFrac ?? 0) > 0.7 ? MMTokens.amber : MMTokens.mint
            ),
            KpiMetric(
                id: "queue",
                label: "Queue",
                value: "\(snapshot.queue.count)",
                sub: longest > 0 ? "longest \(prettyDuration(longest))" : "empty",
                tone: snapshot.queue.isEmpty ? MMTokens.inkMuted : MMTokens.amber
            ),
        ]
    }

    // MARK: 24h activity sparkbar
    //
    // ── OVER TO YOU ──────────────────────────────────────────────────────
    // This is the one piece I've left for you to shape, because it's a real
    // design decision rather than boilerplate. We have `snapshot.recent` (the
    // last ~10 runs per repo: each a `RecentRun` with `result`, `finishedAt`,
    // and `durationSeconds`). The sparkbar wants `bucketCount` bars covering
    // the last 24 hours, oldest → newest, where each bar's:
    //   • `kind`   = the run that landed in that hour (failure should "win"
    //                over success so a red bar is never hidden; .idle when the
    //                hour had no runs), and
    //   • `height` = 0...1, your choice of what magnitude to show (run
    //                duration normalized? run count? a flat value?).
    //
    // Trade-offs to weigh: an hour can hold several runs (which one represents
    // it?), most hours will be empty (how tall is "idle"?), and durations vary
    // wildly (normalize against what — a fixed cap, or the max in the window?).
    //
    // Implement `activityBuckets` below. The stub returns a flat idle baseline
    // so everything compiles and the window renders; swap in your logic.
    // See `MW_TIMELINE` in main-window.jsx for the visual target.
    // ─────────────────────────────────────────────────────────────────────

    static func activityBuckets(
        from snapshot: DashboardSnapshot,
        bucketCount: Int = 24,
        now: Date = Date()
    ) -> [ActivityBucket] {
        // One bucket per hour, oldest (bucketCount-1 h ago) → newest (this hour).
        let cap = 300.0   // a 5-minute run fills the bar; longer just clamps to 1.
        var kinds = [ActivityBucket.Kind](repeating: .idle, count: bucketCount)
        var heights = [Double](repeating: 0, count: bucketCount)

        for run in snapshot.recent {
            let hoursAgo = Int(now.timeIntervalSince(run.finishedAt) / 3600)
            guard hoursAgo >= 0, hoursAgo < bucketCount else { continue }
            let idx = bucketCount - 1 - hoursAgo
            let h = min(1.0, Double(run.durationSeconds) / cap)
            // Failure wins the hour so a red bar is never hidden by a green one;
            // otherwise the taller (longer) run represents the hour.
            if run.result == .failure {
                kinds[idx] = .failure
                heights[idx] = max(heights[idx], h)
            } else if kinds[idx] != .failure {
                kinds[idx] = .success
                heights[idx] = max(heights[idx], h)
            }
        }

        // Anything building right now lights the most-recent bucket blue.
        if snapshot.runners.contains(where: { $0.state == .building }) {
            kinds[bucketCount - 1] = .building
            heights[bucketCount - 1] = max(heights[bucketCount - 1], 0.6)
        }

        return (0..<bucketCount).map { ActivityBucket(id: $0, kind: kinds[$0], height: heights[$0]) }
    }

    // MARK: - Small helpers

    private static func medianDuration(of runs: [RecentRun]) -> Int? {
        let sorted = runs.map(\.durationSeconds).sorted()
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func prettyDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s"
    }
}
