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
                        .font(MMFont.rounded(size: 10.5, weight: .heavy))
                        .tracking(0.9).textCase(.uppercase)
                        .foregroundStyle(MMTokens.blue)
                    Text(hostText(runner))
                        .font(MMFont.mono(size: 11))
                        .foregroundStyle(MMTokens.inkFaint)
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
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .kerning(-0.4)
                            .foregroundStyle(MMTokens.ink)
                        if let app = job.app {
                            Text("· \(app)")
                                .font(MMFont.mono(size: 14))
                                .foregroundStyle(MMTokens.inkMuted)
                        }
                    }
                    metaRow(job)
                }

                // Progress
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(job.step ?? "Running…")
                            .font(MMFont.rounded(size: 13, weight: .semibold))
                            .foregroundStyle(MMTokens.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        progressLabel(progress: progress, elapsed: elapsed, eta: eta)
                    }
                    ProgressBarView(value: progress, tone: MMTokens.blue, height: 8)
                }

                PhaseRail(progress: progress)
            }
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
            .glassCard(cornerRadius: 14,
                       tint: MMTokens.blue.opacity(0.12),
                       strokeColor: MMTokens.blue.opacity(0.40))
        }
    }

    private func metaRow(_ job: WorkflowJob) -> some View {
        HStack(spacing: 10) {
            Label { Text(job.branch).mmMono(size: 12) } icon: {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
            }
            if let pr = job.pullRequest {
                dot
                Image(systemName: "arrow.triangle.pull").font(.system(size: 11))
                Text("#\(pr)").mmMono(size: 12)
            }
            dot
            Text(job.commitSHA.prefix(7)).mmMono(size: 12, color: MMTokens.inkSoft)
        }
        .foregroundStyle(MMTokens.inkMuted)
        .lineLimit(1)
    }

    private func progressLabel(progress: Double, elapsed: Int, eta: Int?) -> some View {
        HStack(spacing: 0) {
            Text("\(Int(progress * 100))%")
                .font(MMFont.rounded(size: 12, weight: .bold))
                .foregroundStyle(MMTokens.ink)
            Text(" · ").foregroundStyle(MMTokens.inkFaint)
            Text(OverviewData.prettyDuration(elapsed)).mmMono(size: 12)
            if let eta, eta > 0 {
                Text(" · eta ").foregroundStyle(MMTokens.inkFaint)
                Text("~\(OverviewData.prettyDuration(eta))").mmMono(size: 12)
            }
        }
        .font(MMFont.rounded(size: 12))
        .foregroundStyle(MMTokens.inkMuted)
    }

    // MARK: - Calm (idle / offline / no runner)

    private func calmHero(runner: Runner?) -> some View {
        let tone = MMTokens.tone(for: runner?.state ?? .offline)
        // Spacers center the content vertically across whatever height the
        // parent grants (fills in wide mode, ~minHeight in the narrow scroll) —
        // no internal maxHeight: .infinity, which collapses inside a ScrollView.
        return VStack(spacing: 12) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(tone.opacity(0.12)).frame(width: 56, height: 56)
                Image(systemName: idleIcon(runner))
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(tone)
            }
            Text(calmTitle(runner))
                .font(MMFont.rounded(size: 16, weight: .bold))
                .foregroundStyle(MMTokens.ink)
            Text(calmSubtitle(runner))
                .font(MMFont.rounded(size: 12.5))
                .foregroundStyle(MMTokens.inkMuted)
                .multilineTextAlignment(.center)
            if let last = runner?.lastJob {
                HStack(spacing: 8) {
                    ResultGlyph(result: last.result, size: 16)
                    Text("Last build \(last.result.rawValue) · \(OverviewData.prettyDuration(last.durationSeconds))")
                        .font(MMFont.rounded(size: 12))
                        .foregroundStyle(MMTokens.inkMuted)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(24)
        .glassCard()
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

    private var dot: some View { Text("·").foregroundStyle(MMTokens.inkFaint) }
    private func hostText(_ r: Runner) -> String { r.labels.contains("arm64") ? "arm64" : (r.labels.first ?? "") }

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

// MARK: - Phase rail
//
// GitHub's job API doesn't hand us a clean step list in our model (WorkflowJob
// carries one `step` string, not the whole sequence), so the rail visualizes a
// generic five-phase build estimated from `progress`. It's an honest
// approximation, labeled generically — not a claim about the real step names.

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
                    .font(MMFont.rounded(size: 11.5, weight: .semibold))
                    .foregroundStyle(state == .pending ? MMTokens.inkSoft : MMTokens.ink)
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
