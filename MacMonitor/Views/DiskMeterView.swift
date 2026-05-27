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
                Text("\(Int(disk.usedFraction * 100))%")
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

    private var usedTotalPretty: String {
        // Display in the unit that fits the JSX prototype (GB).
        let used = Double(disk.usedBytes) / 1_000_000_000
        let total = Double(disk.totalBytes) / 1_000_000_000
        let usedStr = used == used.rounded() ? "\(Int(used))" : String(format: "%.1f", used)
        let totalStr = total == total.rounded() ? "\(Int(total))" : String(format: "%.1f", total)
        return "\(usedStr)/\(totalStr) GB"
    }
}
