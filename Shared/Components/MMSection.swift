// MMSection.swift
//
// Reusable section header + body container used by every panel in the popover
// ("Runners", "Queue", "Recent runs", "Storage"). Direct port of MBASection
// from menu-bar-app.jsx — top eyebrow row, optional trailing action label,
// content, optional bottom divider.

import SwiftUI

public struct MMSection<Content: View, Action: View>: View {
    public let title: String?
    public let action: Action
    public let divider: Bool
    public let content: () -> Content

    public init(
        title: String?,
        divider: Bool = true,
        @ViewBuilder action: () -> Action,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.action = action()
        self.divider = divider
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack {
                    Text(title).mmEyebrow()
                    Spacer()
                    action
                }
                .padding(.bottom, 8)
            }
            content()
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 12, trailing: 14))
        .overlay(alignment: .bottom) {
            if divider {
                Rectangle()
                    .fill(MMTokens.glassDivider)
                    .frame(height: 1)
            }
        }
    }
}

// Convenience overload when no trailing action is needed — keeps call sites
// from having to write `action: { EmptyView() }`.
extension MMSection where Action == EmptyView {
    public init(
        title: String?,
        divider: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, divider: divider, action: { EmptyView() }, content: content)
    }
}
