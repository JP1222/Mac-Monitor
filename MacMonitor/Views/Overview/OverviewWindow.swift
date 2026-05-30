// OverviewWindow.swift
//
// The primary window, now built on native macOS containers:
//   • NavigationSplitView      — real sidebar + detail with the system's own
//                                 collapse, toolbar integration, and materials.
//   • .toolbar                 — the unified titlebar/toolbar (segmented Picker,
//                                 .searchable field, native buttons) instead of
//                                 a hand-drawn bar.
//   • .navigationTitle/Subtitle — the live status rides in the native title area.
//   • .safeAreaInset(.bottom)  — the status strip as a native inset.
//
// The dense Overview content (fleet/KPI/hero/logs + rail) stays custom because
// macOS has no stock "KPI card" control, but every surface is now a real
// Material so it reads as native, elevated glass.

import SwiftUI
import AppKit

/// Toolbar time-range filter (presentational for now — no time-windowing yet).
enum TimeRange: String, CaseIterable, Identifiable {
    case live = "Live", today = "Today", sevenDay = "7d", thirtyDay = "30d"
    var id: String { rawValue }
}

struct OverviewWindow: View {
    @EnvironmentObject private var viewModel: DashboardViewModel
    @EnvironmentObject private var nav: NavModel

    @State private var selectedRunnerID: String?
    @State private var range: TimeRange = .live
    @State private var searchText = ""

    private var snapshot: DashboardSnapshot { viewModel.snapshot }

    var body: some View {
        NavigationSplitView {
            OverviewSidebar(snapshot: snapshot, selection: $nav.section)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            detail
                .navigationTitle(nav.section?.label ?? "Overview")
                // No navigationSubtitle — it forced a 2-line title block that
                // made the toolbar a tall band. The live status already shows in
                // the sidebar header and the FLEET row.
                .toolbar { toolbarContent }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search workflows, SHAs…")
        // No forced scheme — the adaptive MMTokens + Materials follow the
        // system light/dark setting now.
        .frame(minWidth: 1080, minHeight: 720)
        .onAppear { viewModel.start() }
    }

    // MARK: - Detail router

    @ViewBuilder
    private var detail: some View {
        switch nav.section ?? .overview {
        case .overview:
            overviewContent
        case .settings:
            // Settings shows INLINE in the window's detail — no popup window.
            SettingsView()
        case .runners, .queue, .history, .storage, .notifications:
            // Native empty-state component. These sections are real, selectable
            // destinations; their full detail views are the next build.
            ContentUnavailableView(
                (nav.section ?? .overview).label,
                systemImage: (nav.section ?? .overview).systemImage,
                description: Text("This view is coming next — the Overview has the full picture for now.")
            )
            .background(MMTokens.glassStrong)
        }
    }

    private var overviewContent: some View {
        GeometryReader { geo in
            let narrow = geo.size.width < 1150
            content(narrow: narrow)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(MMTokens.glassStrong)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OverviewStatusBar(snapshot: snapshot, narrow: false)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Range", selection: $range) {
                ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Time range")

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh now")
            .disabled(viewModel.isRefreshing)

            Button(action: openGitHub) {
                Label("Open on GitHub", systemImage: "arrow.up.forward.square")
            }
            .help("Open this repo's Actions on GitHub")

            Button {
                nav.section = .settings
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings (⌘,)")
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    // MARK: - Overview content

    @ViewBuilder
    private func content(narrow: Bool) -> some View {
        let fleet = OverviewData.fleet(from: snapshot, selectedID: selectedRunnerID)
        let kpis = OverviewData.kpis(from: snapshot)
        let hero = OverviewData.heroRunner(from: snapshot, selectedID: selectedRunnerID)
        let buckets = OverviewData.activityBuckets(from: snapshot)

        if narrow {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    mainColumn(fleet: fleet, kpis: kpis, hero: hero, logsMinHeight: 280)
                    ActivityTimeline(buckets: buckets)
                    QueueRail(items: snapshot.queue)
                    RecentRunsRail(runs: snapshot.recent, onOpen: open)
                }
                .padding(18)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                mainColumn(fleet: fleet, kpis: kpis, hero: hero, logsMinHeight: nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 14) {
                    ActivityTimeline(buckets: buckets)
                    QueueRail(items: snapshot.queue, fixedHeight: 150)
                    RecentRunsRail(runs: snapshot.recent, onOpen: open)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 340)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func mainColumn(fleet: [FleetEntry], kpis: [KpiMetric], hero: Runner?, logsMinHeight: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            FleetStrip(entries: fleet, onSelect: { selectedRunnerID = $0 })
            KpiStrip(metrics: kpis)
            LiveBuildHero(runner: hero, onOpenRun: open)
            LogsPanel(lines: logLines(for: hero), isLive: false, context: logContext(for: hero))
                .frame(minHeight: logsMinHeight, maxHeight: logsMinHeight == nil ? .infinity : nil)
        }
    }

    // MARK: - Logs wiring (sample until streaming lands)

    private func logLines(for hero: Runner?) -> [LogLine] {
        (hero?.state == .building) ? LogsPanel.sampleLines : []
    }
    private func logContext(for hero: Runner?) -> String {
        guard let job = hero?.currentJob else { return "" }
        return [job.workflow, job.app].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Derived + actions

    private func openGitHub() {
        if let url = snapshot.repositories.first?.actionsURL { open(url) }
    }
    private func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

#Preview("Overview window") {
    OverviewWindow()
        .environmentObject(DashboardViewModel())
        .frame(width: 1440, height: 940)
}
