// RunnerCardView.swift
//
// One runner per card. Two layouts based on state:
//
//   building → big card: workflow + app, branch + PR, shimmer progress bar,
//              percent + step + elapsed/eta footer
//   idle/etc → small card: result glyph + "Last job · 1m 52s · 3m ago" + heartbeat
//
// Port of MBARunnerCard. The card subtly tints blue when building (matches
// the design's `linear-gradient` background).

import SwiftUI

public struct RunnerCardView: View {
    public let runner: Runner
    @State private var isHovering = false

    public init(runner: Runner) { self.runner = runner }

    public var body: some View {
        Button(action: openCurrentRun) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let job = runner.currentJob, runner.state == .building {
                    buildingBody(job: job)
                        .padding(.top, 10)
                } else if runner.state == .building {
                    // BUILDING but GitHub hasn't surfaced the job metadata
                    // yet (race window between /runners reporting busy=true
                    // and the new workflow_run/jobs appearing). Show a
                    // placeholder so users don't see contradictory state
                    // ("Building" chip + "Last job" idle text).
                    buildingPlaceholderBody
                        .padding(.top, 10)
                } else if let last = runner.lastJob {
                    idleBody(last: last)
                        .padding(.top, 8)
                }
            }
            .padding(12)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isHovering && hasClickableTarget ? MMTokens.blue.opacity(0.5) : cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!hasClickableTarget)
        .onHover { isHovering = $0 }
        .help(currentRunURL?.absoluteString ?? "")
    }

    /// Only the in-progress job's runURL is clickable today. Idle cards don't
    /// have a single "last run URL" to navigate to (we'd need to also pull
    /// the run URL into LastJobSummary — follow-up).
    private var hasClickableTarget: Bool { currentRunURL != nil }

    private var currentRunURL: URL? {
        runner.state == .building ? runner.currentJob?.runURL : nil
    }

    private func openCurrentRun() {
        guard let url = currentRunURL else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(state: runner.state, size: 9)
            Text(runner.label)
                .font(MMFont.rounded(size: 13.5, weight: .bold))
                .kerning(-0.1)
                .foregroundStyle(MMTokens.ink)
            Text(displayLabels)
                .font(MMFont.mono(size: 11))
                .foregroundStyle(MMTokens.inkFaint)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            stateChip
        }
    }

    /// Skip `self-hosted` (every self-hosted runner has it — redundant) and
    /// join the rest with a middle dot. Falls back to the host-like
    /// "studio.local" mock string only when no labels exist (shouldn't
    /// happen with real GitHub data, but defensive for previews).
    private var displayLabels: String {
        let useful = runner.labels.filter { $0.lowercased() != "self-hosted" }
        return useful.isEmpty ? "studio.local" : useful.joined(separator: " · ")
    }

    @ViewBuilder
    private var stateChip: some View {
        let tone = MMTokens.tone(for: runner.state)
        let glow = MMTokens.glow(for: runner.state)
        Text(label(for: runner.state))
            .font(MMFont.rounded(size: 10.5, weight: .bold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(tone)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(glow, in: Capsule())
    }

    private func label(for s: RunnerState) -> String {
        switch s {
        case .idle:     return "Idle"
        case .building: return "Building"
        case .warning:  return "Warning"
        case .failure:  return "Failed"
        case .offline:  return "Offline"
        }
    }

    // MARK: - Building body

    @ViewBuilder
    private func buildingBody(job: WorkflowJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(job.workflow)
                    .font(MMFont.rounded(size: 14, weight: .bold))
                    .foregroundStyle(MMTokens.ink)
                if let app = job.app {
                    Text("· \(app)").mmMono()
                }
            }
            HStack(spacing: 8) {
                MMIcons.branch
                    .font(.system(size: 11))
                    .foregroundStyle(MMTokens.inkMuted)
                Text(job.branch).mmMono()
                Text("·").foregroundStyle(MMTokens.inkFaint)
                MMIcons.pullRequest
                    .font(.system(size: 11))
                    .foregroundStyle(MMTokens.inkMuted)
                if let pr = job.pullRequest {
                    Text("#\(pr)").mmMono()
                }
            }
            .padding(.bottom, 6)

            // TimelineView re-renders this subtree every second so elapsed
            // ticks up live + progress bar advances smoothly. SwiftUI's
            // animation engine on its own would only update on data change,
            // not wall-clock change — TimelineView bridges that gap.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = job.elapsedSeconds(now: context.date)
                // Recompute progress/eta against the same historical average
                // the ViewModel used. If etaSeconds was set on the job by
                // ViewModel, derive avg = elapsed + eta_at_snapshot_time.
                let avg = (job.etaSeconds.map { Int($0) + job.elapsedSeconds(now: job.startedAt.addingTimeInterval(Double(elapsed))) })
                    ?? Int(Double(elapsed) / max(job.progress, 0.01))
                let livePct = min(0.95, max(0.02, Double(elapsed) / Double(max(avg, 1))))
                let liveEta = max(0, avg - elapsed)

                VStack(alignment: .leading, spacing: 5) {
                    ProgressBarView(value: livePct, tone: MMTokens.blue, shimmer: true)

                    HStack(spacing: 4) {
                        Text("\(Int(livePct * 100))%")
                            .font(MMFont.rounded(size: 11, weight: .bold))
                            .foregroundStyle(MMTokens.ink)
                        Text("· \(job.step ?? "")")
                            .font(MMFont.rounded(size: 11))
                            .foregroundStyle(MMTokens.inkMuted)
                        Spacer()
                        Text(formatElapsed(elapsed)).mmMono()
                        if liveEta > 0 {
                            Text(" · eta ").foregroundStyle(MMTokens.inkFaint).font(MMFont.rounded(size: 11))
                            Text("~\(formatElapsed(liveEta))").mmMono()
                        }
                    }
                }
            }
            .padding(.top, 1)
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s"
    }

    // MARK: - Building placeholder (BUILDING chip but no job metadata yet)

    private var buildingPlaceholderBody: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .tint(MMTokens.blue)
            Text("Job starting…")
                .font(MMFont.rounded(size: 11.5))
                .foregroundStyle(MMTokens.inkMuted)
            Spacer()
            if let last = runner.lastJob {
                Text("last · \(formatElapsed(last.durationSeconds))")
                    .font(MMFont.mono(size: 10.5))
                    .foregroundStyle(MMTokens.inkSoft)
            }
        }
    }

    // MARK: - Idle body

    @ViewBuilder
    private func idleBody(last: LastJobSummary) -> some View {
        HStack(spacing: 8) {
            ResultGlyph(result: last.result, size: 18)
            Text("Last job")
                .font(MMFont.rounded(size: 11.5))
                .foregroundStyle(MMTokens.inkMuted)
            Text(formatElapsed(last.durationSeconds)).mmMono()
            Text("·").foregroundStyle(MMTokens.inkFaint)
            Text(relativeWhen(last.finishedAt))
                .font(MMFont.rounded(size: 11.5))
                .foregroundStyle(MMTokens.inkMuted)
            Spacer()
            Text("♥ \(runner.heartbeatRelative())")
                .font(MMFont.rounded(size: 10.5))
                .foregroundStyle(MMTokens.inkFaint)
        }
    }

    private func relativeWhen(_ date: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(date)))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }

    // MARK: - Background

    private var cardBackground: some View {
        Group {
            if runner.state == .building {
                LinearGradient(
                    colors: [
                        MMTokens.rgba(90, 169, 255, 0.10),
                        MMTokens.rgba(90, 169, 255, 0.02),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                MMTokens.rgba(255, 255, 255, 0.03)
            }
        }
    }

    private var cardBorder: Color {
        runner.state == .building
            ? MMTokens.rgba(90, 169, 255, 0.22)
            : MMTokens.glassBorder
    }
}

#if canImport(AppKit)
import AppKit
#endif

#Preview("Runner cards") {
    VStack(spacing: 12) {
        ForEach(DashboardSnapshot.mock.runners) { r in
            RunnerCardView(runner: r)
        }
    }
    .padding(20)
    .frame(width: 360)
    .background(MMTokens.glassStrong)
}
