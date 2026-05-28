// OnboardingView.swift
//
// First-launch screen shown when no GitHub PAT is in Keychain. Replaces
// the section list + quick actions footer inside the popover (header
// stays so the user has visual continuity + a way to dismiss).
//
// Three numbered steps, primary action opens the Settings window where
// the user pastes their PAT + configures repos.

import SwiftUI

public struct OnboardingView: View {
    @EnvironmentObject private var viewModel: DashboardViewModel

    public init() {}

    public var body: some View {
        VStack(spacing: 18) {
            // Welcome
            VStack(spacing: 6) {
                Text("Get started").mmEyebrow()
                Text("Connect to GitHub")
                    .font(MMFont.rounded(size: 18, weight: .heavy))
                    .kerning(-0.3)
                    .foregroundStyle(MMTokens.ink)
                Text("Three steps and you're monitoring your build farm.")
                    .font(MMFont.rounded(size: 11.5))
                    .foregroundStyle(MMTokens.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)

            // Steps
            VStack(alignment: .leading, spacing: 12) {
                step(
                    number: 1,
                    title: "Generate a fine-grained PAT",
                    subtitle: "Repository access: your repos · Permissions: Actions Read + Administration Read + Metadata Read",
                    link: URL(string: "https://github.com/settings/personal-access-tokens/new")!,
                    linkLabel: "Open GitHub →"
                )
                step(
                    number: 2,
                    title: "Open Settings",
                    subtitle: "Paste the token (it goes straight to your Keychain — never to disk or this chat)",
                    actionLabel: "Open Settings",
                    action: { SettingsWindowController.show(viewModel: viewModel) }
                )
                step(
                    number: 3,
                    title: "List the repos to watch",
                    subtitle: "One owner/name per line. Multi-repo is supported out of the box."
                )
            }
            .padding(.horizontal, 4)

            // Footer note
            Text("Storage section also needs the local agent — see README.md for the launchctl one-liner.")
                .font(MMFont.rounded(size: 10.5))
                .foregroundStyle(MMTokens.inkFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    // MARK: - Step row

    @ViewBuilder
    private func step(
        number: Int,
        title: String,
        subtitle: String,
        link: URL? = nil,
        linkLabel: String? = nil,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Number bubble
            Text("\(number)")
                .font(MMFont.rounded(size: 12, weight: .heavy))
                .foregroundStyle(MMTokens.ink)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(MMTokens.rgba(255, 255, 255, 0.08))
                )
                .overlay(
                    Circle().stroke(MMTokens.glassBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(MMFont.rounded(size: 12.5, weight: .bold))
                    .foregroundStyle(MMTokens.ink)
                Text(subtitle)
                    .font(MMFont.rounded(size: 11))
                    .foregroundStyle(MMTokens.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                if let link, let linkLabel {
                    Link(linkLabel, destination: link)
                        .font(MMFont.rounded(size: 11.5, weight: .semibold))
                        .foregroundStyle(MMTokens.blue)
                        .padding(.top, 2)
                }
                if let actionLabel, let action {
                    Button(action: action) {
                        Text(actionLabel)
                            .font(MMFont.rounded(size: 11.5, weight: .semibold))
                            .foregroundStyle(MMTokens.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(MMTokens.blue)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
    }
}
