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

    public init(runner: Runner) { self.runner = runner }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let job = runner.currentJob, runner.state == .building {
                buildingBody(job: job)
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
                .stroke(cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(state: runner.state, size: 9)
            Text(runner.label)
                .font(MMFont.rounded(size: 13.5, weight: .bold))
                .kerning(-0.1)
                .foregroundStyle(MMTokens.ink)
            Text(deviceHost)
                .font(MMFont.mono(size: 11))
                .foregroundStyle(MMTokens.inkFaint)
            Spacer()
            stateChip
        }
    }

    private var deviceHost: String {
        // The HTML mock displays "studio.local" — for a real multi-device
        // setup the row would actually find the Device by ID and read .host,
        // but for the per-runner card it stays a passthrough.
        "studio.local"
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

            ProgressBarView(value: job.progress, tone: MMTokens.blue, shimmer: true)

            HStack(spacing: 4) {
                Text("\(Int(job.progress * 100))%")
                    .font(MMFont.rounded(size: 11, weight: .bold))
                    .foregroundStyle(MMTokens.ink)
                Text("· \(job.step ?? "")")
                    .font(MMFont.rounded(size: 11))
                    .foregroundStyle(MMTokens.inkMuted)
                Spacer()
                Text("\(formatElapsed(job.elapsedSeconds()))").mmMono()
                if let eta = job.etaSeconds {
                    Text(" · eta ").foregroundStyle(MMTokens.inkFaint).font(MMFont.rounded(size: 11))
                    Text("~\(eta)s").mmMono()
                }
            }
            .padding(.top, 5)
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s"
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
