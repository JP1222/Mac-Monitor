// SettingsView.swift
//
// Modal sheet for one-off configuration: GitHub PAT entry, repo slug, and
// status of the wiring. Surfaced from PopoverHeader's gear button.
//
// UX notes:
//   - Token is rendered with `SecureField` so it's masked in the UI and not
//     captured by Screen Recording (per Apple's guidance).
//   - We confirm save + show the masked tail of the stored token (last 4
//     chars), which lets the user verify they pasted the right one without
//     re-exposing it.
//   - Saving writes to Keychain via KeychainStore; the field is then
//     cleared so it doesn't linger in memory longer than needed.

import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: DashboardViewModel

    @State private var tokenInput: String = ""
    @State private var repoSlug: String = "JP1222/Yolo-Rollo"
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
                    tokenSection
                    statusSection
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }

            Divider().background(MMTokens.glassDivider)
            footer
        }
        .frame(width: 460, height: 480)
        .background(MMTokens.glassStrong)
        .foregroundStyle(MMTokens.ink)
        .onAppear(perform: refreshTokenStatus)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            RunnerBrandGlyph(size: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text("Mac Monitor · Settings")
                    .font(MMFont.rounded(size: 14, weight: .bold))
                Text("GitHub credentials live in your Keychain")
                    .font(MMFont.rounded(size: 11))
                    .foregroundStyle(MMTokens.inkSoft)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - Repo section

    private var repoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Repository").mmEyebrow()
            TextField("owner/name", text: $repoSlug)
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
            Text("Workflow runs, queued jobs and self-hosted runners come from this repository.")
                .font(MMFont.rounded(size: 11))
                .foregroundStyle(MMTokens.inkSoft)
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

            Text("Paste a fine-grained PAT scoped to this repo with Actions: Read + Administration: Read + Metadata: Read. Stored in the macOS Keychain, never in plain files.")
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
                Text("Token saved to Keychain. Refreshing dashboard…")
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
                Text("Save token")
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
            .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func save() {
        do {
            try KeychainStore.saveGitHubToken(tokenInput)
            saveStatus = .saved
            tokenInput = ""    // clear input field so token isn't in memory
            refreshTokenStatus()
            // Kick a refresh so the UI immediately reflects the new token.
            Task { await viewModel.refresh() }
        } catch {
            saveStatus = .error(error.localizedDescription)
        }
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
