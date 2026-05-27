// MediumWidgetView.swift
//
// 338×158 — two runner mini-cards stacked side by side + a single bottom
// "last run" strip. Port of `DWMedium` + `DWRunnerMini`.

import SwiftUI

public struct MediumWidgetView: View {
    public let snapshot: DashboardSnapshot

    public init(snapshot: DashboardSnapshot) { self.snapshot = snapshot }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(
                title: "Runners · \(snapshot.runners.count) hosts",
                accent: snapshot.aggregateState
            )
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(snapshot.runners.prefix(2)) { r in
                        RunnerMiniCard(runner: r)
                    }
                }
                lastRunStrip
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 14, trailing: 14))
        }
    }

    @ViewBuilder
    private var lastRunStrip: some View {
        if let last = snapshot.recent.first {
            HStack(spacing: 6) {
                ResultGlyph(result: last.result, size: 16)
                Text(last.app ?? last.workflow)
                    .font(MMFont.rounded(size: 11, weight: .semibold))
                    .foregroundStyle(MMTokens.ink)
                Text("· \(last.branch) · \(last.durationPretty)")
                    .mmMono(size: 11)
                Spacer()
                Text(last.whenRelative())
                    .font(MMFont.rounded(size: 10.5))
                    .foregroundStyle(MMTokens.inkSoft)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(MMTokens.rgba(255, 255, 255, 0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MMTokens.glassDivider, lineWidth: 1)
            )
        }
    }
}

/// Shared between medium + large widgets. Port of `DWRunnerMini`.
public struct RunnerMiniCard: View {
    public let runner: Runner

    public init(runner: Runner) { self.runner = runner }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                StatusDot(state: runner.state, size: 7)
                Text(runner.label)
                    .font(MMFont.rounded(size: 11, weight: .bold))
                    .foregroundStyle(MMTokens.ink)
                    .lineLimit(1)
            }
            if let job = runner.currentJob, runner.state == .building {
                buildingBody(job: job)
            } else if let last = runner.lastJob {
                idleBody(last: last)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 10, leading: 11, bottom: 10, trailing: 11))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func buildingBody(job: WorkflowJob) -> some View {
        Text(job.app ?? job.workflow)
            .font(MMFont.rounded(size: 12.5, weight: .heavy))
            .kerning(-0.2)
            .foregroundStyle(MMTokens.ink)
            .lineLimit(1)
        Text(job.branch)
            .font(MMFont.mono(size: 10))
            .foregroundStyle(MMTokens.inkMuted)
            .lineLimit(1)
            .truncationMode(.tail)
        ProgressBarView(value: job.progress, tone: MMTokens.blue, height: 3, shimmer: true)
            .padding(.top, 2)
        HStack {
            Text("\(Int(job.progress * 100))%")
                .font(MMFont.mono(size: 10, weight: .bold))
                .foregroundStyle(MMTokens.ink)
            Spacer()
            Text("\(job.elapsedSeconds() / 60)m \(String(format: "%02d", job.elapsedSeconds() % 60))s")
                .font(MMFont.mono(size: 10))
                .foregroundStyle(MMTokens.inkMuted)
        }
    }

    @ViewBuilder
    private func idleBody(last: LastJobSummary) -> some View {
        Text("IDLE")
            .font(MMFont.rounded(size: 12.5, weight: .heavy))
            .kerning(-0.2)
            .foregroundStyle(MMTokens.mint)
        Spacer(minLength: 0)
        Text("last · \(last.durationSeconds / 60)m \(String(format: "%02d", last.durationSeconds % 60))s")
            .font(MMFont.mono(size: 10))
            .foregroundStyle(MMTokens.inkMuted)
        Text(relative(from: last.finishedAt))
            .font(MMFont.mono(size: 10))
            .foregroundStyle(MMTokens.inkSoft)
    }

    private func relative(from date: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(date)))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }

    @ViewBuilder
    private var background: some View {
        if runner.state == .building {
            LinearGradient(
                colors: [
                    MMTokens.rgba(90, 169, 255, 0.14),
                    MMTokens.rgba(90, 169, 255, 0.02),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            MMTokens.rgba(255, 255, 255, 0.04)
        }
    }

    private var borderColor: Color {
        runner.state == .building
            ? MMTokens.rgba(90, 169, 255, 0.30)
            : MMTokens.glassDivider
    }
}
