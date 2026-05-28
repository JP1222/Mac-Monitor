// DiskMeterView.swift
//
// One row in the "Storage · three-layer" panel: label + sub + used/total +
// percent + a thin (4pt) progress bar tinted by displayTone. Port of
// MBADiskMeter.

import SwiftUI

public struct DiskMeterView: View {
    public let disk: DiskUsage

    public init(disk: DiskUsage) { self.disk = disk }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(disk.label)
                    .font(MMFont.rounded(size: 12, weight: .semibold))
                    .foregroundStyle(MMTokens.ink)
                Text(disk.sub)
                    .font(MMFont.mono(size: 10.5))
                    .foregroundStyle(MMTokens.inkSoft)
                Spacer()
                Text(usedTotalPretty).mmMono()
                Text(percentPretty)
                    .font(MMFont.rounded(size: 10.5, weight: .bold))
                    .foregroundStyle(MMTokens.tone(for: disk.displayTone))
                    .frame(width: 34, alignment: .trailing)
            }
            ProgressBarView(value: disk.usedFraction,
                            tone: MMTokens.tone(for: disk.displayTone),
                            height: 4,
                            shimmer: false)
        }
    }

    /// Show used in its natural unit (KB/MB/GB) but keep the denominator in
    /// GB for consistency across rows. Example: "34.3 MB / 30 GB" — makes
    /// small caches visible instead of rounding to "0.0 / 30 GB".
    private var usedTotalPretty: String {
        let totalGB = Double(disk.totalBytes) / 1_000_000_000
        let totalStr = totalGB == totalGB.rounded() ? "\(Int(totalGB))" : String(format: "%.1f", totalGB)
        return "\(formatBytes(disk.usedBytes)) / \(totalStr) GB"
    }

    /// "1.2 GB" / "34.3 MB" / "812 KB" / "0 B". Adaptive unit so small
    /// values don't disappear into rounding noise.
    private func formatBytes(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1_000_000_000 { return String(format: "%.1f GB", b / 1_000_000_000) }
        if b >= 1_000_000     { return String(format: "%.1f MB", b / 1_000_000) }
        if b >= 1_000         { return String(format: "%.0f KB", b / 1_000) }
        return "\(bytes) B"
    }

    /// Round-to-zero protection: if the disk has ANY content but it's less
    /// than 1% of total, show "<1%" instead of "0%" so users can tell apart
    /// "literally empty" from "very small". Anything ≥1% rounds normally.
    private var percentPretty: String {
        let pct = disk.usedFraction * 100
        if disk.usedBytes > 0 && pct < 1 { return "<1%" }
        return "\(Int(pct))%"
    }
}
