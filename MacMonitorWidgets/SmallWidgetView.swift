// SmallWidgetView.swift
//
// 158×158 — at-a-glance current build. Big progress ring + app name + PR.
// Bottom row: idle-runner count + elapsed timer. Port of `DWSmall`.

import SwiftUI

public struct SmallWidgetView: View {
    public let snapshot: DashboardSnapshot

    public init(snapshot: DashboardSnapshot) { self.snapshot = snapshot }

    private var primaryRunner: Runner? {
        snapshot.runners.first { $0.state == .building } ?? snapshot.runners.first
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: "Runners", accent: snapshot.aggregateState)
            content
                .padding(EdgeInsets(top: 10, leading: 14, bottom: 14, trailing: 14))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let runner = primaryRunner, let job = runner.currentJob {
            buildingContent(runner: runner, job: job)
        } else {
            idleContent
        }
    }

    @ViewBuilder
    private func buildingContent(runner: Runner, job: WorkflowJob) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                BigRing(value: job.progress, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Building").mmEyebrow()
                    Text(job.app ?? job.workflow)
                        .font(MMFont.rounded(size: 14, weight: .heavy))
                        .kerning(-0.2)
                        .foregroundStyle(MMTokens.ink)
                    if let pr = job.pullRequest {
                        Text("#\(pr)").mmMono(size: 10.5)
                    }
                }
            }
            Spacer(minLength: 8)
            footerStrip(elapsed: job.elapsedSeconds())
        }
    }

    @ViewBuilder
    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All quiet").mmEyebrow()
            Text("\(snapshot.onlineRunnerCount) runners")
                .font(MMFont.rounded(size: 18, weight: .heavy))
                .foregroundStyle(MMTokens.ink)
            Spacer()
            Text("\(snapshot.recent.first?.whenRelative() ?? "—") · last")
                .font(MMFont.mono(size: 10.5))
                .foregroundStyle(MMTokens.inkMuted)
        }
    }

    @ViewBuilder
    private func footerStrip(elapsed: Int) -> some View {
        HStack {
            HStack(spacing: 4) {
                StatusDot(state: .idle, pulse: false, size: 5)
                Text("\(snapshot.runners.filter { $0.state == .idle }.count) idle")
                    .font(MMFont.rounded(size: 10.5))
                    .foregroundStyle(MMTokens.inkMuted)
            }
            Spacer()
            Text("\(elapsed / 60)m \(String(format: "%02d", elapsed % 60))s")
                .font(MMFont.mono(size: 10.5))
                .foregroundStyle(MMTokens.inkMuted)
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(MMTokens.glassDivider).frame(height: 1)
        }
    }
}

/// Circular progress ring used by the small widget.
public struct BigRing: View {
    public let value: Double
    public let size: CGFloat

    public init(value: Double, size: CGFloat = 56) {
        self.value = value
        self.size = size
    }

    public var body: some View {
        let stroke: CGFloat = 5
        ZStack {
            Circle()
                .stroke(MMTokens.rgba(255, 255, 255, 0.08), lineWidth: stroke)
            Circle()
                .trim(from: 0, to: value)
                .stroke(MMTokens.blue, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: MMTokens.blue.opacity(0.55), radius: 6)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int(value * 100))")
                        .font(MMFont.mono(size: 15, weight: .heavy))
                        .kerning(-0.5)
                        .foregroundStyle(MMTokens.ink)
                    Text("%")
                        .font(MMFont.mono(size: 9))
                        .foregroundStyle(MMTokens.ink.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
    }
}
