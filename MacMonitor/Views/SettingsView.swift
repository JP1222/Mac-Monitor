// SettingsView.swift
//
// Native macOS settings, rebuilt as a grouped `Form` (the System-Settings
// look). Hosted in an AppKit window via SettingsWindowController — see that
// file for why a SwiftUI `Settings` scene is avoided in this LSUIElement app.
//
// Native settings apply LIVE: toggles, the interval picker, and the repo/device
// lists persist to UserSettings on change (which posts didChangeNotification →
// DashboardViewModel refreshes). The GitHub PAT is the one exception — a secret
// shouldn't be written to the Keychain on every keystroke, so it keeps an
// explicit Save/Update button.

import SwiftUI
import ServiceManagement

public struct SettingsView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    // Live-editable state, seeded from UserSettings on appear.
    @State private var repos: [String] = []
    @State private var devices: [String] = []
    @State private var refreshInterval: Int = 15
    @State private var touchIDGate: Bool = false

    // Add-row fields.
    @State private var newRepo: String = ""
    @State private var newDevice: String = ""

    // Token (explicit save).
    @State private var tokenInput: String = ""
    @State private var existingTokenSuffix: String? = nil
    @State private var tokenNotice: String? = nil

    public init() {}

    public var body: some View {
        Form {
            githubSection
            repositoriesSection
            devicesSection
            pollingSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 600)
        .onAppear(perform: load)
    }

    // MARK: - GitHub

    private var githubSection: some View {
        Section {
            // PAT field + explicit save.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SecureField("Personal access token", text: $tokenInput, prompt: Text("github_pat_…"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(saveToken)
                    Button(existingTokenSuffix == nil ? "Save" : "Update", action: saveToken)
                        .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                HStack(spacing: 8) {
                    if let suffix = existingTokenSuffix {
                        Label("On file · ····\(suffix)", systemImage: "key.fill")
                            .font(.caption).foregroundStyle(MMTokens.mint)
                        Button("Remove", role: .destructive, action: removeToken)
                            .buttonStyle(.link).font(.caption)
                    } else {
                        Label("No token — the dashboard stays empty until you add one", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let notice = tokenNotice {
                        Text(notice).font(.caption).foregroundStyle(MMTokens.mint)
                    }
                }
            }
            Link(destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!) {
                Label("Create a fine-grained token on GitHub", systemImage: "arrow.up.forward.square")
            }
            .font(.callout)
            Toggle(isOn: $touchIDGate) {
                Text("Require Touch ID to read the token")
                Text("Prompts for biometrics before fetching the token at launch. Off by default — the Keychain item is already access-controlled to this app and device.")
            }
            .onChange(of: touchIDGate) { UserSettings.touchIDGateEnabled = touchIDGate }
        } header: {
            Text("GitHub")
        } footer: {
            Text("Fine-grained PAT needs Actions: Read · Administration: Read · Metadata: Read, scoped to the repositories below. Stored in the macOS Keychain.")
        }
    }

    // MARK: - Repositories

    private var repositoriesSection: some View {
        Section {
            if repos.isEmpty {
                Text("No repositories yet").foregroundStyle(.secondary)
            }
            ForEach(repos, id: \.self) { repo in
                HStack {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(.secondary)
                    Text(repo).font(.system(.body, design: .monospaced))
                    Spacer()
                    Button {
                        repos.removeAll { $0 == repo }; persistRepos()
                    } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(MMTokens.tomato)
                }
            }
            HStack {
                TextField("owner/name", text: $newRepo, prompt: Text("owner/name"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(addRepo)
                Button("Add", action: addRepo)
                    .disabled(!isValidSlug(newRepo))
            }
        } header: {
            Text("Repositories")
        } footer: {
            Text("Workflow runs, queued jobs, and self-hosted runners from each repo are merged into the dashboard.")
        }
    }

    // MARK: - Devices + local agent

    private var devicesSection: some View {
        Section {
            // Local bundled agent status (SMAppService).
            LabeledContent {
                HStack(spacing: 8) {
                    Circle().fill(agentTone).frame(width: 7, height: 7)
                    Text(agentStatusText).foregroundStyle(.secondary)
                }
            } label: {
                Label("Local agent", systemImage: "cpu")
            }
            if agentStatus == .requiresApproval {
                Button("Open Login Items…") { AgentInstaller.openLoginItemsSettings() }
                    .font(.callout)
            }

            // Remote devices.
            ForEach(devices, id: \.self) { device in
                HStack {
                    Image(systemName: "network").foregroundStyle(.secondary)
                    Text(device).font(.system(.body, design: .monospaced))
                    Spacer()
                    Button {
                        devices.removeAll { $0 == device }; persistDevices()
                    } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(MMTokens.tomato)
                }
            }
            HStack {
                TextField("label@host", text: $newDevice, prompt: Text("mac-mini-1@100.x.x.x"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(addDevice)
                Button("Add", action: addDevice)
                    .disabled(!newDevice.contains("@"))
            }
        } header: {
            Text("Devices")
        } footer: {
            Text("The local agent is bundled and auto-starts. Add remote build Macs as `label@host` (host can be a Tailscale IP) to see their disk/CPU — health is read-only over the agent's /health.")
        }
    }

    // MARK: - Polling

    private var pollingSection: some View {
        Section {
            Picker("Refresh interval", selection: $refreshInterval) {
                Text("15 seconds").tag(15)
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
                Text("5 minutes").tag(300)
            }
            .onChange(of: refreshInterval) { UserSettings.refreshIntervalSeconds = refreshInterval }
        } header: {
            Text("Polling")
        } footer: {
            Text("How often Mac Monitor polls GitHub. Tighter intervals burn API quota faster (5000 requests/hour authenticated).")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App version", value: appVersion)
            LabeledContent("Agent version", value: agentVersion)
            LabeledContent("Synced via", value: "iCloud Key-Value + Keychain")
        }
    }

    // MARK: - Derived

    private var agentStatus: SMAppService.Status { AgentInstaller.service.status }
    private var agentStatusText: String {
        switch agentStatus {
        case .enabled:         return "Enabled · auto-starts on login"
        case .requiresApproval: return "Needs approval in Login Items"
        case .notRegistered:   return "Not registered"
        case .notFound:        return "Not found"
        @unknown default:      return "Unknown"
        }
    }
    private var agentTone: Color {
        switch agentStatus {
        case .enabled: return MMTokens.mint
        case .requiresApproval: return MMTokens.amber
        default: return MMTokens.slate
        }
    }
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
    private var agentVersion: String {
        guard let v = viewModel.snapshot.deviceSnapshots
            .max(by: { $0.capturedAt < $1.capturedAt })?.agentVersion else { return "—" }
        return "v\(v)"
    }

    // MARK: - Actions

    private func load() {
        repos = UserSettings.repositorySlugs
        devices = UserSettings.deviceEndpoints
        refreshInterval = UserSettings.refreshIntervalSeconds
        touchIDGate = UserSettings.touchIDGateEnabled
        refreshTokenStatus()
    }

    private func isValidSlug(_ s: String) -> Bool {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: "/")
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty }
    }

    private func addRepo() {
        let slug = newRepo.trimmingCharacters(in: .whitespaces)
        guard isValidSlug(slug), !repos.contains(slug) else { return }
        repos.append(slug); newRepo = ""; persistRepos()
    }
    private func persistRepos() {
        UserSettings.repositorySlugs = repos
        Task { await viewModel.refresh() }
    }

    private func addDevice() {
        let d = newDevice.trimmingCharacters(in: .whitespaces)
        guard d.contains("@"), !devices.contains(d) else { return }
        devices.append(d); newDevice = ""; persistDevices()
    }
    private func persistDevices() {
        UserSettings.deviceEndpoints = devices
        Task { await viewModel.refresh() }
    }

    private func saveToken() {
        let t = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        do {
            try KeychainStore.saveGitHubToken(t)
            tokenInput = ""
            tokenNotice = "Saved"
            refreshTokenStatus()
            viewModel.refreshTokenStatus()
            Task { await viewModel.refresh() }
        } catch {
            tokenNotice = "Save failed"
        }
    }
    private func removeToken() {
        try? KeychainStore.deleteGitHubToken()
        tokenNotice = "Removed"
        refreshTokenStatus()
        viewModel.refreshTokenStatus()
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
