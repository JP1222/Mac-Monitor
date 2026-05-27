// MMTypography.swift
//
// SwiftUI doesn't expose "SF Pro Rounded · 14 / 700" as a single API — you set
// design + weight + size separately. These convenience helpers keep the design
// vocabulary terse so views read like the JSX they came from.
//
// Mapping (from `app.jsx` System Sheet):
//   - Titles:       SF Pro Rounded · 22 / 800
//   - Body:         SF Pro Rounded · 14 / 700
//   - Mono:         JetBrains Mono · 12 / 500 (we substitute system monospaced)
//   - Eyebrows:     SF Pro Rounded · 10.5 / 800 · letterSpacing 1.1 · UPPERCASE

import SwiftUI

public enum MMFont {

    /// "SF Pro Rounded" — declared as `.system(design: .rounded)` so the
    /// system picks the actual face. No bundled font needed.
    public static func rounded(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// System monospaced substitute for JetBrains Mono. Used for SHAs,
    /// durations, branch names — anywhere a fixed-width column matters.
    public static func mono(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // Named roles taken from app.jsx's "Type" column.
    public static let title         = rounded(size: 22, weight: .heavy)         // "Yolo Runners"
    public static let popoverTitle  = rounded(size: 14, weight: .bold)          // header section
    public static let cardTitle     = rounded(size: 13.5, weight: .bold)        // runner label
    public static let body          = rounded(size: 14, weight: .bold)          // build-images · kds-api
    public static let small         = rounded(size: 11.5, weight: .medium)
    public static let micro         = rounded(size: 11, weight: .regular)
    public static let monoBranch    = mono(size: 12)
    public static let monoSmall     = mono(size: 11)
}

// MARK: - Reusable text styles

extension View {
    /// Eyebrow label: 10.5 / 800 / +1.1 tracking / UPPERCASE / inkSoft.
    /// Used for "RUNNERS", "QUEUE · 2 WAITING", "RECENT", "STORAGE".
    public func mmEyebrow(color: Color? = nil) -> some View {
        self
            .font(MMFont.rounded(size: 10.5, weight: .heavy))
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(color ?? MMTokens.inkSoft)
    }

    /// Inline mono text — fixed-width for SHAs/branches/durations.
    public func mmMono(
        size: CGFloat = 11.5,
        weight: Font.Weight = .medium,
        color: Color? = nil
    ) -> some View {
        self
            .font(MMFont.mono(size: size, weight: weight))
            .kerning(-0.2)
            .foregroundStyle(color ?? MMTokens.inkMuted)
    }
}
