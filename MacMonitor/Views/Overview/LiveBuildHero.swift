// LiveBuildHero.swift
//
// The big card driven by the selected fleet runner. Building → the full live
// hero (workflow title, branch/PR/SHA meta, ticking progress + ETA, phase
// rail). Idle/offline → a calm summary of the last result. The prototype only
// drew the building state with hard-coded numbers; here the values tick off the
// real job via a 1-second TimelineView.

import SwiftUI

struct LiveBuildHero: View {
    let runner: Runner?
    var onOpenRun: (URL) -> Void = { _ in }

    var body: some View {
        Group {
            if let runner, runner.state == .building, let job = runner.currentJob {
                buildingHero(runner: runner, job: job)
            } else {
                calmHero(runner: runner)
            }
        }
    }

    // MARK: - Building

    private func buildingHero(runner: Runner, job: WorkflowJob) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = ctx.date
            let avg = job.historicalAvgSeconds
            let progress = avg != nil ? job.estimatedProgress(historicalAvgSeconds: avg, now: now) : job.progress
            let eta = avg != nil ? job.estimatedEtaSeconds(historicalAvgSeconds: avg, now: now) : job.etaSeconds
            let elapsed = job.elapsedSeconds(now: now)

            VStack(alignment: .leading, spacing: 14) {
                // Top row
                HStack(spacing: 10) {
                    StatusDot(tone: MMTokens.blue, glow: MMTokens.blueGlow, pulse: true, size: 9)
                    Text("Building · \(runner.label)")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.9).textCase(.uppercase)
                        .foregroundStyle(MMTokens.blue)
                    Text(hostText(runner))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Button { onOpenRun(job.runURL) } label: {
                        Label("Open run", systemImage: "arrow.up.forward")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.blue)
                }

                // Workflow + app
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(job.workflow)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                        if let app = job.app {
                            Text("· \(app)")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    metaRow(job)
                }

                // Progress
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(currentStepName(job) ?? "Running…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        progressLabel(progress: progress, elapsed: elapsed, eta: eta)
                    }
                    ProgressView(value: progress)
                        .tint(.blue)
                }

                BuildStepRail(steps: job.steps ?? [], progressFallback: progress)
            }
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
            .contentCard(cornerRadius: 14,
                       tint: MMTokens.blue.opacity(0.12),
                       strokeColor: MMTokens.blue.opacity(0.40))
        }
    }

    private func metaRow(_ job: WorkflowJob) -> some View {
        HStack(spacing: 10) {
            Label { Text(job.branch).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) } icon: {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
            }
            if let pr = job.pullRequest {
                dot
                Image(systemName: "arrow.triangle.pull").font(.system(size: 11))
                Text("#\(pr)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            dot
            Text(job.commitSHA.prefix(7)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func progressLabel(progress: Double, elapsed: Int, eta: Int?) -> some View {
        HStack(spacing: 0) {
            Text("\(Int(progress * 100))%")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(" · ").foregroundStyle(.tertiary)
            Text(OverviewData.prettyDuration(elapsed)).font(.system(.caption, design: .monospaced)).monospacedDigit().foregroundStyle(.secondary)
            if let eta, eta > 0 {
                Text(" · eta ").foregroundStyle(.tertiary)
                Text("~\(OverviewData.prettyDuration(eta))").font(.system(.caption, design: .monospaced)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    // MARK: - Calm (idle / offline / no runner)

    private func calmHero(runner: Runner?) -> some View {
        // Native macOS idle/empty state (DESIGN.md §3): ContentUnavailableView's
        // centered symbol + title + message replaces the old huge whitespace
        // with a tiny glyph. No custom card — it fills the focal area itself.
        ContentUnavailableView {
            Label(calmTitle(runner), systemImage: idleIcon(runner))
        } description: {
            VStack(spacing: 6) {
                Text(calmSubtitle(runner))
                if let last = runner?.lastJob {
                    Label(
                        "Last build \(last.result.rawValue) · \(OverviewData.prettyDuration(last.durationSeconds))",
                        systemImage: last.result == .success ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .font(.callout)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func idleIcon(_ r: Runner?) -> String {
        switch r?.state {
        case .idle: return "checkmark.circle"
        case .offline: return "powerplug"
        case .failure: return "xmark.circle"
        default: return "bolt.slash"
        }
    }

    // MARK: - Helpers

    private var dot: some View { Text("·").foregroundStyle(.tertiary) }
    private func hostText(_ r: Runner) -> String { r.labels.contains("arm64") ? "arm64" : (r.labels.first ?? "") }

    /// The real step the build is currently on. Falls back to `job.step` (the
    /// job name) only when GitHub hasn't surfaced a live step yet.
    private func currentStepName(_ job: WorkflowJob) -> String? {
        if let active = job.steps?.first(where: { $0.status == .inProgress }) {
            return active.name
        }
        return job.step
    }

    private func calmTitle(_ r: Runner?) -> String {
        switch r?.state {
        case .idle: return "Idle · \(r?.label ?? "")"
        case .offline: return "Offline · \(r?.label ?? "")"
        case .failure: return "Failed · \(r?.label ?? "")"
        default: return r == nil ? "No runner selected" : "\(r?.label ?? "")"
        }
    }
    private func calmSubtitle(_ r: Runner?) -> String {
        guard let r else { return "Select a fleet card to see its build" }
        switch r.state {
        case .idle: return "Ready for the next job"
        case .offline: return "Runner is offline — last seen \(r.heartbeatRelative())"
        default: return r.label
        }
    }
}

// MARK: - Step rail
//
// Picks the real step rail when GitHub gave us the job's `steps[]`, else falls
// back to the generic five-phase approximation (e.g. a queued job whose steps
// haven't populated yet).

private struct BuildStepRail: View {
    let steps: [WorkflowStep]
    let progressFallback: Double

    var body: some View {
        if steps.isEmpty {
            PhaseRail(progress: progressFallback)
        } else {
            RealStepRail(steps: steps)
        }
    }
}

// Real steps, compact: one thin segment per step (scales to a 20-step build,
// unlike the fixed 5-phase strip), colored by each step's true state, plus an
// honest "Step N of M" caption pinned to the in-progress step.
private struct RealStepRail: View {
    let steps: [WorkflowStep]

    private var activeIndex: Int? { steps.firstIndex { $0.status == .inProgress } }
    private var doneCount: Int { steps.filter { $0.status == .completed }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 3) {
                ForEach(steps) { step in
                    Capsule()
                        .fill(segmentColor(step))
                        .frame(height: 5)
                        .frame(maxWidth: .infinity)
                }
            }
            Text(caption)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var caption: String {
        if let i = activeIndex { return "Step \(i + 1) of \(steps.count)" }
        if doneCount == steps.count { return "All \(steps.count) steps complete" }
        return "\(doneCount) of \(steps.count) steps complete"
    }

    private func segmentColor(_ step: WorkflowStep) -> Color {
        switch step.displayResult {
        case .success:   return MMTokens.mint
        case .failure:   return MMTokens.tomato
        case .building:  return MMTokens.blue
        case .cancelled: return MMTokens.slate
        case .skipped:   return Color(.tertiaryLabelColor)
        case .queued:    return MMTokens.glassBorder   // adaptive faint = "not yet"
        }
    }
}

// Generic fallback when no real steps are available: a five-phase build
// estimated from `progress`. Honest approximation, labeled generically.

private struct PhaseRail: View {
    let progress: Double

    private let phases = ["Setup", "Fetch deps", "Build", "Test", "Push"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(phases.enumerated()), id: \.offset) { idx, name in
                let lower = Double(idx) / Double(phases.count)
                let upper = Double(idx + 1) / Double(phases.count)
                let state: PhaseState = progress >= upper ? .done : (progress >= lower ? .active : .pending)
                phaseCell(name, state)
            }
        }
    }

    private enum PhaseState { case done, active, pending }

    private func phaseCell(_ name: String, _ state: PhaseState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                switch state {
                case .done:
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MMTokens.mint)
                case .active:
                    ResultGlyph(result: .building, size: 12)
                case .pending:
                    Circle().strokeBorder(MMTokens.inkFaint, lineWidth: 1.2).frame(width: 8, height: 8)
                }
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state == .pending ? .secondary : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(phaseFill(state), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(phaseStroke(state), lineWidth: 1)
        )
    }

    private func phaseFill(_ s: PhaseState) -> Color {
        switch s {
        case .active: return MMTokens.blue.opacity(0.14)
        case .done: return MMTokens.mint.opacity(0.10)
        case .pending: return MMTokens.rgba(255, 255, 255, 0.025)
        }
    }
    private func phaseStroke(_ s: PhaseState) -> Color {
        switch s {
        case .active: return MMTokens.blue.opacity(0.30)
        case .done: return MMTokens.mint.opacity(0.22)
        case .pending: return MMTokens.glassBorder
        }
    }
}
