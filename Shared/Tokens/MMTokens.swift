// MMTokens.swift
//
// 1:1 port of `shared.jsx`'s MM_TOKENS into SwiftUI. Values are intentionally
// kept verbatim from the design source so a `grep` for "0.78" or "#52C28C"
// returns hits in both the JSX prototype and the Swift code — that's the
// invariant that lets us pixel-match the design later.
//
// All colors are RGBA. SwiftUI `Color` takes 0...1 components so we wrap the
// RGB-255 conversion in `rgba(_:_:_:_:)` for readability.

import SwiftUI
import AppKit

public enum MMTokens {

    // MARK: - Color factory

    /// Convert CSS-style `rgba(r, g, b, a)` into SwiftUI `Color`. Lets us keep
    /// the design tokens visually parallel to the JSX source.
    @inlinable
    public static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(.sRGB, red: r / 255.0, green: g / 255.0, blue: b / 255.0, opacity: a)
    }

    /// Hex helper for the saturated brand colors. Hex is `0xRRGGBB`.
    @inlinable
    public static func hex(_ value: UInt32, opacity: Double = 1) -> Color {
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// Appearance-adaptive color. The dark value is the original design token
    /// (so dark mode is byte-for-byte unchanged); the light value is its
    /// counterpart so the whole app follows the system light/dark setting. The
    /// provider closure resolves at draw time against the view's effective
    /// `NSAppearance`, which SwiftUI drives from the `colorScheme` environment.
    public static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
    }

    // MARK: - Surface (adaptive glass)

    public static let glass         = dynamic(light: rgba(250, 249, 246, 0.72), dark: rgba(28, 28, 32, 0.78))
    public static let glassStrong   = dynamic(light: hex(0xF2F1ED),             dark: rgba(20, 20, 24, 0.92))
    public static let glassBorder   = dynamic(light: rgba(0, 0, 0, 0.10),       dark: rgba(255, 255, 255, 0.08))
    public static let glassDivider  = dynamic(light: rgba(0, 0, 0, 0.08),       dark: rgba(255, 255, 255, 0.06))
    public static let glassHairline = dynamic(light: rgba(0, 0, 0, 0.06),       dark: rgba(255, 255, 255, 0.04))
    public static let rowHover      = dynamic(light: rgba(0, 0, 0, 0.05),       dark: rgba(255, 255, 255, 0.05))

    // MARK: - Ink (adaptive text)

    public static let ink       = dynamic(light: hex(0x1A1A1A),               dark: hex(0xF4F2EE))
    public static let inkMuted  = dynamic(light: hex(0x1A1A1A, opacity: 0.64), dark: hex(0xF4F2EE, opacity: 0.62))
    public static let inkSoft   = dynamic(light: hex(0x1A1A1A, opacity: 0.46), dark: hex(0xF4F2EE, opacity: 0.42))
    public static let inkFaint  = dynamic(light: hex(0x1A1A1A, opacity: 0.30), dark: hex(0xF4F2EE, opacity: 0.26))

    // MARK: - Status (YRUI palette lifted onto dark)

    public static let mint         = hex(0x52C28C)
    public static let mintGlow     = rgba(82, 194, 140, 0.18)
    public static let amber        = hex(0xE8B23B)
    public static let amberGlow    = rgba(232, 178, 59, 0.20)
    public static let tomato       = hex(0xE5664A)
    public static let tomatoGlow   = rgba(229, 102, 74, 0.20)
    public static let slate        = hex(0x7B8597)

    public static let blue         = hex(0x5AA9FF)
    public static let blueGlow     = rgba(90, 169, 255, 0.22)

    public static let brand        = hex(0xE4B872)
    public static let brandDeep    = hex(0xC5894F)

    // MARK: - Radii (matches "Radii" swatch in the design system sheet)

    public static let radiusChip:    CGFloat = 6
    public static let radiusRow:     CGFloat = 10
    public static let radiusPopover: CGFloat = 14
    public static let radiusWidget:  CGFloat = 22

    // MARK: - Status → Color helpers

    /// Maps a `Runner.state` to the accent color used for chips, ring borders,
    /// and the menu bar icon dot.
    public static func tone(for state: RunnerState) -> Color {
        switch state {
        case .building: return blue
        case .idle:     return mint
        case .warning:  return amber
        case .failure:  return tomato
        case .offline:  return slate
        }
    }

    public static func glow(for state: RunnerState) -> Color {
        switch state {
        case .building: return blueGlow
        case .idle:     return mintGlow
        case .warning:  return amberGlow
        case .failure:  return tomatoGlow
        case .offline:  return rgba(123, 133, 151, 0.18)
        }
    }

    public static func tone(for aggregate: DashboardSnapshot.AggregateState) -> Color {
        switch aggregate {
        case .building: return blue
        case .idle:     return mint
        case .warning:  return amber
        case .failure:  return tomato
        case .offline:  return slate
        }
    }

    public static func glow(for aggregate: DashboardSnapshot.AggregateState) -> Color {
        switch aggregate {
        case .building: return blueGlow
        case .idle:     return mintGlow
        case .warning:  return amberGlow
        case .failure:  return tomatoGlow
        case .offline:  return rgba(123, 133, 151, 0.18)
        }
    }

    public static func tone(for diskState: DiskUsage.State) -> Color {
        switch diskState {
        case .ok:       return mint
        case .warn:     return amber
        case .critical: return tomato
        }
    }
}
