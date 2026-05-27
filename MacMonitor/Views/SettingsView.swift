// SettingsView.swift
//
// Standalone window (hosted via SettingsWindowController, NOT a popover
// sheet — see that file for why) where the user configures:
//
//   - GitHub PAT (stored in Keychain via KeychainStore)
//   - Repositories to monitor (multi-line, persisted via UserSettings →
//     iCloud + UserDefaults)
//   - Refresh interval (segmented picker, persisted)
//   - Touch ID gate (toggle, persisted)
//
// The repo + interval changes post `UserSettings.didChangeNotification`,
// which DashboardViewModel listens for and triggers an immediate refresh.

import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: DashboardViewModel

    @State private var tokenInput: String = ""
    @State private var reposText: String = ""
    @State private var refreshInterval: Int = 15
    @State private var touchIDGate: Bool = false
    @State private var saveStatus: SaveStatus = .idle
    @State private var existingTokenSuffix: String? = nil

    private enum SaveStatus: Equatable {
        case idle
        case saved
        case error(String)
    }

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(MMTokens.glassDivider)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    repoSection
                    refreshSection
                    tokenSection
                    securitySection
                    statusSection
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }

            Divider().background(MMTokens.glassDivider)
            footer
        }
        .frame(width: 480, height: 620)
        .background(MMTokens.glassStrong)
        .foregroundStyle(MMTokens.ink)
        .onAppear(perform: loadCurrentValues)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            RunnerBrandGlyph(size: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text("Mac Monitor · Settings")
                    .font(MMFont.rounded(size: 14, weight: .bold))
                Text("Synced via iCloud · token in Keychain")
                    .font(MMFont.rounded(size: 11))
                    .foregroundStyle(MMTokens.inkSoft)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - Repo section (multi-line)

    private var repoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Repositories").mmEyebrow()
            // TextEditor for multi-line input — one slug per line.
            TextEditor(text: $reposText)
                .font(MMFont.mono(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 70, maxHeight: 110)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MMTokens.rgba(255, 255, 255, 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(MMTokens.glassBorder, lineWidth: 1)
                )
            Text("One `owner/name` per line. Workflow runs, queued jobs and self-hosted runners from each repo are merged into the dashboard.")
                .font(MMFont.rounded(size: 11))
                .foregroundStyle(MMTokens.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Refresh interval

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Refresh interval").mmEyebrow()
            Picker("", selection: $refreshInterval) {
                Text("15s").tag(15)
                Text("30s").tag(30)
                Text("1m").tag(60)
                Text("5m").tag(300)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("How often MacMonitor polls GitHub. Tighter intervals burn API quota faster (5000 req/hr authenticated).")
                .font(MMFont.rounded(size: 11))
                .foregroundStyle(MMTokens.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Token section

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Personal Access Token").mmEyebrow()
                Spacer()
                if let suffix = existingTokenSuffix {
                    Text("on file · …\(suffix)")
                        .font(MMFont.mono(size: 11))
                        .foregroundStyle(MMTokens.mint)
                }
            }

            SecureField("github_pat_…", text: $tokenInput)
                .textFieldStyle(.plain)
                .font(MMFont.mono(size: 13))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MMTokens.rgba(255, 255, 255, 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(MMTokens.glassBorder, lineWidth: 1)
                )

            Text("Fine-grained PAT with Actions: Read + Administration: Read + Metadata: Read scoped to the repos above. Stored in the macOS Keychain.")
                .font(MMFont.rounded(size: 11))
                .foregroundStyle(MMTokens.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if let url = URL(string: "https://github.com/settings/personal-access-tokens/new") {
                Link("Open GitHub token settings ↗", destination: url)
                    .font(MMFont.rounded(size: 11.5, weight: .semibold))
                    .foregroundStyle(MMTokens.blue)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Security").mmEyebrow()
            Toggle(isOn: $touchIDGate) {
                Text("Require Touch ID to read token from Keychain")
                    .font(MMFont.rounded(size: 11.5))
                    .foregroundStyle(MMTokens.ink)
            }
            .toggleStyle(.switch)
            Text("When enabled, MacMonitor prompts for Touch ID before fetching the token at app launch. Off by default — the Keychain item is already access-controlled to this app and device.")
                .font(MMFont.rounded(size: 10.5))
                .foregroundStyle(MMTokens.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        switch saveStatus {
        case .idle:
            EmptyView()
        case .saved:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MMTokens.mint)
                Text("Saved. Refreshing dashboard…")
                    .font(MMFont.rounded(size: 11.5))
                    .foregroundStyle(MMTokens.ink)
            }
        case .error(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MMTokens.tomato)
                Text(message)
                    .font(MMFont.rounded(size: 11.5))
                    .foregroundStyle(MMTokens.ink)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Remove token") {
                try? KeychainStore.deleteGitHubToken()
                refreshTokenStatus()
                saveStatus = .idle
            }
            .buttonStyle(.plain)
            .disabled(existingTokenSuffix == nil)
            .foregroundStyle(existingTokenSuffix == nil ? MMTokens.inkFaint : MMTokens.tomato)
            .font(MMFont.rounded(size: 11.5))

            Spacer()

            Button("Close") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(MMTokens.inkMuted)
                .font(MMFont.rounded(size: 12))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MMTokens.rgba(255, 255, 255, 0.06))
                )

            Button(action: save) {
                Text("Save")
                    .font(MMFont.rounded(size: 12, weight: .semibold))
                    .foregroundStyle(MMTokens.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(MMTokens.blue)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func loadCurrentValues() {
        reposText = UserSettings.repositorySlugs.joined(separator: "\n")
        refreshInterval = UserSettings.refreshIntervalSeconds
        touchIDGate = UserSettings.touchIDGateEnabled
        refreshTokenStatus()
    }

    private func save() {
        // Token (only if user typed something — empty field means "don't change").
        if !tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try KeychainStore.saveGitHubToken(tokenInput)
                tokenInput = ""
            } catch {
                saveStatus = .error(error.localizedDescription)
                return
            }
        }
        // Repos.
        let parsed = reposText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        UserSettings.repositorySlugs = parsed
        UserSettings.refreshIntervalSeconds = refreshInterval
        UserSettings.touchIDGateEnabled = touchIDGate

        refreshTokenStatus()
        saveStatus = .saved
        Task { await viewModel.refresh() }
    }

    private func refreshTokenStatus() {
        if let token = KeychainStore.readGitHubToken(), token.count >= 4 {
            existingTokenSuffix = String(token.suffix(4))
        } else {
            existingTokenSuffix = nil
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(DashboardViewModel(refreshInterval: 999))
}
