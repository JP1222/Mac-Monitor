// OverviewSidebar.swift
//
// Native sidebar — a `List` with `.listStyle(.sidebar)`, the genuine macOS
// source-list look (vibrancy material, system selection pill, hover, disclosure
// behavior) instead of hand-drawn rows. Nav items are `Label`s with native
// `.badge()` counts; the org header and agent-status footer ride in via
// `safeAreaInset` so they sit inside the sidebar's material.

import SwiftUI

/// The sidebar's selectable sections. Only `.overview` has a full detail today;
/// the rest are real, selectable destinations wired to lightweight detail views.
enum NavSection: String, Hashable, Identifiable, CaseIterable {
    case overview, runners, queue, history, storage, notifications
    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return "Overview"
        case .runners: return "Runners"
        case .queue: return "Queue"
        case .history: return "History"
        case .storage: return "Storage"
        case .notifications: return "Notifications"
        }
    }
    var systemImage: String {
        switch self {
        case .overview: return "bolt.fill"
        case .runners: return "cpu"
        case .queue: return "line.3.horizontal"
        case .history: return "clock.arrow.circlepath"
        case .storage: return "internaldrive"
        case .notifications: return "bell"
        }
    }
}

struct OverviewSidebar: View {
    let snapshot: DashboardSnapshot
    @Binding var selection: NavSection?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(NavSection.allCases) { section in
                    Label(section.label, systemImage: section.systemImage)
                        .badge(badge(for: section))
                        .tag(section)
                }
            }

            if !snapshot.repositories.isEmpty {
                Section("Repos") {
                    ForEach(Array(snapshot.repositories.enumerated()), id: \.element.id) { idx, repo in
                        repoRow(repo, color: repoColors[idx % repoColors.count])
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { orgHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) { agentFooter }
    }

    // MARK: - Badges

    private func badge(for section: NavSection) -> Int {
        switch section {
        case .runners: return snapshot.runners.count
        case .queue: return snapshot.queue.count
        case .notifications: return snapshot.recent.filter { $0.result == .failure }.count
        default: return 0   // 0 → no badge
        }
    }

    // MARK: - Org header

    private var orgHeader: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [MMTokens.brand, MMTokens.brandDeep],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: "hexagon.fill").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92)))
            VStack(alignment: .leading, spacing: 1) {
                Text(orgName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                HStack(spacing: 4) {
                    StatusDot(aggregate: snapshot.aggregateState, pulse: false, size: 5)
                    Text(orgSubtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func repoRow(_ repo: Repository, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(repo.slug).font(.system(size: 11.5, design: .monospaced)).lineLimit(1)
                Text(repo.defaultBranch).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    // MARK: - Agent footer

    private var agentFooter: some View {
        let snap = snapshot.deviceSnapshots.max { $0.capturedAt < $1.capturedAt }
        let online = snap != nil && snap!.ageSeconds() < 120
        return VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "powerplug").font(.system(size: 10, weight: .semibold))
                Text(online ? "Agent connected" : "Agent offline")
                    .font(.system(size: 11, weight: .bold)).tracking(0.3).textCase(.uppercase)
            }
            .foregroundStyle(online ? MMTokens.mint : .secondary)
            Text(agentSubtitle(snap))
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Derived strings

    private var orgName: String { snapshot.repositories.first?.owner ?? "Mac Monitor" }
    private var orgSubtitle: String {
        let online = snapshot.runners.filter { $0.status == .online }.count
        let offline = snapshot.runners.count - online
        if snapshot.runners.isEmpty { return "no runners" }
        return "\(online) online · \(offline) offline"
    }
    private func agentSubtitle(_ snap: DeviceSnapshot?) -> String {
        guard let snap else { return "no agent reachable" }
        let host = snapshot.devices.first?.host ?? snap.deviceID
        return "\(host) · v\(snap.agentVersion)"
    }

    private let repoColors: [Color] = [MMTokens.brand, MMTokens.blue, MMTokens.mint]
}
