// StepTimelinePanel.swift
//
// The build-detail surface under the live hero. Replaces the old fake "logs"
// terminal (which streamed fixture lines from the prototype and read as real
// data). GitHub's API can't stream raw in-progress log text — but every job
// DOES carry a real `steps[]` array, so this shows the genuine build progress:
// real step names, live status, and per-step durations, refreshed each poll.
//
// It's a `.glassCard()` (not a hardcoded dark terminal) so it adapts to the
// system light/dark setting like every other Overview card — the old solid
// black panel looked broken sitting in the light-mode window.

import SwiftUI

struct StepTimelinePanel: View {
    let steps: [WorkflowStep]
    /// Header context, e.g. "CI · kds-api".
    var context: String = ""
    /// When present, a native "Open run" button links to the full logs on
    /// GitHub — the honest home for raw log text we can't stream here.
    var runURL: URL? = nil
    var onOpenRun: (URL) -> Void = { _ in }

    private var completedCount: Int { steps.filter { $0.status == .completed }.count }
    private var isBuilding: Bool { steps.contains { $0.status == .inProgress } }

    /// The step the build is currently on (first in-progress), used to keep the
    /// scroll pinned to the action. Falls back to the last step.
    private var activeStepID: Int? {
        steps.first { $0.status == .inProgress }?.id ?? steps.last?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(MMTokens.glassHairline)
            content
        }
        .glassCard(cornerRadius: 14)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            if isBuilding {
                StatusDot(tone: MMTokens.blue, glow: MMTokens.blueGlow, pulse: true, size: 6)
            } else {
                StatusDot(tone: MMTokens.slate, glow: MMTokens.rgba(123, 133, 151, 0.18), size: 6)
            }
            SectionCap(text: "Build steps")
            if !context.isEmpty {
                Text(context)
                    .font(MMFont.mono(size: 11))
                    .foregroundStyle(MMTokens.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !steps.isEmpty {
                Text("\(completedCount)/\(steps.count) done")
                    .font(MMFont.rounded(size: 11, weight: .semibold))
                    .foregroundStyle(MMTokens.inkMuted)
                    .monospacedDigit()
            }
            if let runURL {
                Button { onOpenRun(runURL) } label: {
                    Label("Open run", systemImage: "arrow.up.forward")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .tint(.blue)
                .help("Open the full run (and raw logs) on GitHub")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if steps.isEmpty {
            // Native empty state — honest about there being nothing to show,
            // not a fake terminal pretending to stream.
            ContentUnavailableView {
                Label("No active build", systemImage: "checklist")
            } description: {
                Text("Real build steps stream here while a runner is building.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // A normal WindowGroup, so ScrollView behaves (the MenuBarExtra
            // shrink-on-reopen bug is popover-only). Tick once a second so the
            // active step's elapsed time counts up.
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(steps) { step in
                                stepRow(step, now: ctx.date).id(step.id)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onAppear { scrollToActive(proxy) }
                    .onChange(of: activeStepID) { scrollToActive(proxy) }
                }
            }
        }
    }

    private func scrollToActive(_ proxy: ScrollViewProxy) {
        guard let id = activeStepID else { return }
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
    }

    private func stepRow(_ step: WorkflowStep, now: Date) -> some View {
        HStack(spacing: 10) {
            Text("\(step.number)")
                .font(MMFont.mono(size: 10.5))
                .foregroundStyle(MMTokens.inkFaint)
                .frame(width: 20, alignment: .trailing)
            ResultGlyph(result: step.displayResult, size: 15)
            Text(step.name)
                .font(MMFont.rounded(size: 12.5, weight: step.status == .inProgress ? .semibold : .regular))
                .foregroundStyle(nameColor(step))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(durationText(step, now: now))
                .font(MMFont.mono(size: 11))
                .foregroundStyle(step.status == .inProgress ? MMTokens.blue : MMTokens.inkFaint)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(step.status == .inProgress ? MMTokens.blue.opacity(0.07) : .clear)
    }

    private func nameColor(_ step: WorkflowStep) -> Color {
        switch step.status {
        case .inProgress:       return MMTokens.ink
        case .completed:        return step.conclusion == .skipped ? MMTokens.inkSoft : MMTokens.inkMuted
        case .queued, .pending: return MMTokens.inkSoft
        }
    }

    /// Completed → fixed wall-clock. In-progress → live `now − startedAt`.
    /// Queued/pending → blank (no honest number to show yet).
    private func durationText(_ step: WorkflowStep, now: Date) -> String {
        if let seconds = step.durationSeconds { return OverviewData.prettyDuration(seconds) }
        if step.status == .inProgress, let started = step.startedAt {
            return OverviewData.prettyDuration(max(0, Int(now.timeIntervalSince(started))))
        }
        return ""
    }
}

#Preview("Step timeline") {
    StepTimelinePanel(
        steps: [
            .init(number: 1, name: "Set up job", status: .completed, conclusion: .success,
                  startedAt: Date(timeIntervalSinceNow: -90), completedAt: Date(timeIntervalSinceNow: -88)),
            .init(number: 2, name: "Checkout repository", status: .completed, conclusion: .success,
                  startedAt: Date(timeIntervalSinceNow: -88), completedAt: Date(timeIntervalSinceNow: -85)),
            .init(number: 3, name: "Set up Docker Buildx", status: .completed, conclusion: .success,
                  startedAt: Date(timeIntervalSinceNow: -85), completedAt: Date(timeIntervalSinceNow: -70)),
            .init(number: 4, name: "Build and push images (GHCR)", status: .inProgress,
                  startedAt: Date(timeIntervalSinceNow: -42)),
            .init(number: 5, name: "Run tests", status: .queued),
            .init(number: 6, name: "Deploy", status: .queued),
        ],
        context: "CI · kds-api",
        runURL: URL(string: "https://github.com")
    )
    .frame(width: 560, height: 320)
    .padding(24)
    .background(MMTokens.glassStrong)
}
