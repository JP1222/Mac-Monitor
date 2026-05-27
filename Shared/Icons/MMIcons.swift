// MMIcons.swift
//
// SF Symbols substitutes for the custom SVG icons in MMIcon. Apple's SF
// Symbols catalog covers every glyph we needed except the Apple logo (which
// menu bar apps can't use for trademark reasons anyway). One-line mapping
// keeps view code readable.

import SwiftUI

public enum MMIcons {

    // Source control / build
    public static let branch    = Image(systemName: "arrow.triangle.branch")
    public static let pullRequest = Image(systemName: "arrow.triangle.pull")
    public static let github    = Image(systemName: "chevron.left.forwardslash.chevron.right")
    public static let bolt      = Image(systemName: "bolt.fill")

    // System
    public static let gear      = Image(systemName: "gearshape")
    public static let refresh   = Image(systemName: "arrow.clockwise")
    public static let bell      = Image(systemName: "bell")
    public static let search    = Image(systemName: "magnifyingglass")
    public static let cpu       = Image(systemName: "cpu")
    public static let plug      = Image(systemName: "powerplug")

    // Storage
    public static let disk      = Image(systemName: "internaldrive")
    public static let trash     = Image(systemName: "trash")
    public static let queue     = Image(systemName: "line.3.horizontal")

    // Indicators
    public static let check     = Image(systemName: "checkmark")
    public static let cross     = Image(systemName: "xmark")
    public static let restart   = Image(systemName: "arrow.counterclockwise")
    public static let chevron   = Image(systemName: "chevron.right")
    public static let arrow     = Image(systemName: "arrow.right")

    // Menubar system glyphs (for the menu bar artboard reproduction — not
    // used in the actual app's NSMenuBar slot since macOS owns those).
    public static let wifi      = Image(systemName: "wifi")
    public static let battery   = Image(systemName: "battery.100percent")
    public static let controlCenter = Image(systemName: "switch.2")
}
