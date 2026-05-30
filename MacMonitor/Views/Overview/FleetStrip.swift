// FleetStrip.swift
//
// The runner-machine fleet at a glance — the feature the design chat explicitly
// added to answer "多设备?" (does the UI handle multiple devices?). One card per
// runner: status dot, label, chip pill, current job or idle/offline line, and a
// CPU / Mem / Cache footer fed by the host's live device snapshot. The selected
// card drives the live-build hero below.
//
// Layout = `LazyVGrid(.adaptive(minimum: 178))`, the spec's direct mapping of
// the prototype's `repeat(auto-fit, minmax(178px, 1fr))` grid.

import SwiftUI

struct FleetStrip: View {
    let entries: [FleetEntry]
    var onSelect: (String) -> Void = { _ in }

    private let columns = [GridItem(.adaptive(minimum: 178), spacing: 10)]

    private var onlineCount: Int { entries.filter { $0.runner.status != .offline }.count }
    private var buildingCount: Int { entries.filter { $0.runner.state == .building }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SectionCap(text: "Fleet")
                Text("\(onlineCount)/\(entries.count) online · \(buildingCount) building")
                    .font(MMFont.mono(size: 11))
                    .foregroundStyle(MMTokens.inkMuted)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    StatusDot(tone: MMTokens.blue, glow: MMTokens.blueGlow, size: 5)
                    Text("selected drives the hero below")
                        .font(MMFont.rounded(size: 10.5))
                        .foregroundStyle(MMTokens.inkSoft)
                }
            }

            if entries.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(entries) { entry in
                        FleetCard(entry: entry)
                            .onTapGesture { onSelect(entry.id) }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "cpu").foregroundStyle(MMTokens.inkSoft)
            Text("No runners registered — check the PAT's Administration:Read scope.")
                .font(MMFont.rounded(size: 12))
                .foregroundStyle(MMTokens.inkMuted)
            Spacer()
        }
        .padding(14)
        .glassCard()
    }
}

private struct FleetCard: View {
    let entry: FleetEntry

    private var runner: Runner { entry.runner }
    private var offline: Bool { runner.status == .offline || runner.state == .offline }
    private var accent: Color { MMTokens.tone(for: runner.state) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            stateLine
            Divider().overlay(MMTokens.glassHairline)
            footerStats
        }
        .padding(EdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12))
        .glassCard(cornerRadius: 11,
                   tint: entry.isSelected ? MMTokens.blue.opacity(0.16) : nil,
                   strokeColor: entry.isSelected ? MMTokens.blue.opacity(0.45) : nil)
        .opacity(offline ? 0.62 : 1)
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(spacing: 7) {
            StatusDot(state: runner.state, size: 7)
            Text(runner.label)
                .font(MMFont.mono(size: 12, weight: .bold))
                .foregroundStyle(MMTokens.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let chip = entry.chip {
                Text(chip)
                    .font(MMFont.rounded(size: 9.5, weight: .semibold))
                    .foregroundStyle(MMTokens.inkSoft)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(MMTokens.rgba(255, 255, 255, 0.06), in: RoundedRectangle(cornerRadius: 5))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var stateLine: some View {
        if runner.state == .building, let job = runner.currentJob {
            VStack(alignment: .leading, spacing: 5) {
                (Text(job.workflow).foregroundStyle(MMTokens.ink).fontWeight(.semibold)
                 + Text(job.app.map { " · \($0)" } ?? "").foregroundStyle(MMTokens.inkMuted))
                    .font(MMFont.rounded(size: 11))
                    .lineLimit(1)
                ProgressBarView(value: job.progress, tone: MMTokens.blue, height: 4)
                Text("\(Int(job.progress * 100))%\(etaSuffix(job))")
                    .font(MMFont.mono(size: 10))
                    .foregroundStyle(MMTokens.inkSoft)
            }
        } else {
            HStack(spacing: 6) {
                if offline {
                    Image(systemName: "powerplug").font(.system(size: 11))
                        .foregroundStyle(MMTokens.inkSoft)
                    Text("Offline · last seen \(runner.heartbeatRelative())")
                } else {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MMTokens.mint)
                    Text(idleLine)
                }
                Spacer(minLength: 0)
            }
            .font(MMFont.rounded(size: 11))
            .foregroundStyle(MMTokens.inkMuted)
            .frame(minHeight: 33, alignment: .center)
            .lineLimit(1)
        }
    }

    private var footerStats: some View {
        HStack(spacing: 8) {
            FleetMiniStat(label: "CPU",
                          value: entry.cpuPercent.map { "\($0)%" } ?? "—",
                          tone: (entry.cpuPercent ?? 0) > 85 ? MMTokens.amber : nil)
            FleetMiniStat(label: "Mem", value: memValue, tone: nil)
            FleetMiniStat(label: "Cache",
                          value: entry.cacheFraction.map { "\(Int($0 * 100))%" } ?? "—",
                          tone: (entry.cacheFraction ?? 0) > 0.7 ? MMTokens.amber : MMTokens.mint)
        }
    }

    private var memValue: String {
        guard let used = entry.memUsedGB, let total = entry.memTotalGB else { return "—" }
        return "\(String(format: "%.1f", used))/\(Int(total))"
    }

    private var idleLine: String {
        if let last = runner.lastJob {
            return "Idle · last \(last.result.rawValue) \(relative(last.finishedAt))"
        }
        return "Idle"
    }

    private func etaSuffix(_ job: WorkflowJob) -> String {
        guard let eta = job.etaSeconds, eta > 0 else { return "" }
        return " · eta ~\(OverviewData.prettyDuration(eta))"
    }

    private func relative(_ date: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(date)))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }
}

private struct FleetMiniStat: View {
    let label: String
    let value: String
    let tone: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(MMFont.rounded(size: 9, weight: .bold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(MMTokens.inkFaint)
            Text(value)
                .font(MMFont.mono(size: 11, weight: .semibold))
                .foregroundStyle(tone ?? MMTokens.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
