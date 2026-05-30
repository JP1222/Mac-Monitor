// OverviewStatusBar.swift
//
// The 26pt monospaced footer: agent reachability + heartbeat, then host
// metrics (cpu / mem / orbstack), last sync, and agent version. Sheds the
// verbose middle metrics at the narrow breakpoint, exactly like `MWStatusBar`.
// Everything is read from the freshest device snapshot — no mock literals.

import SwiftUI

struct OverviewStatusBar: View {
    let snapshot: DashboardSnapshot
    var narrow: Bool

    private var snap: DeviceSnapshot? {
        snapshot.deviceSnapshots.max { $0.capturedAt < $1.capturedAt }
    }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                StatusDot(tone: online ? MMTokens.mint : MMTokens.slate,
                          glow: online ? MMTokens.mintGlow : MMTokens.rgba(123, 133, 151, 0.18),
                          size: 5)
                Text("agent · \(host)")
            }
            Text("♥ \(heartbeat)")

            if !narrow, let snap {
                Text("·")
                Text("cpu \(Int((snap.cpuLoad * 100).rounded()))%\(memSuffix(snap))")
                Text("·")
                Text("orbstack \(snap.orbStackRunning ? "ok" : "off") · \(snap.dockerContainersRunning) containers")
            }

            Spacer(minLength: 0)

            if !narrow {
                Text("last sync \(lastSync)")
                Text("·")
            }
            Text("v\(snap?.agentVersion ?? "—")")
        }
        .font(MMFont.mono(size: 10.5))
        .foregroundStyle(MMTokens.inkSoft)
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(.bar)   // native status/toolbar material
        .overlay(alignment: .top) {
            Rectangle().fill(MMTokens.glassHairline).frame(height: 1)
        }
    }

    private var online: Bool { (snap?.ageSeconds() ?? .infinity) < 120 }
    private var host: String { snapshot.devices.first?.host ?? snap?.deviceID ?? "—" }

    private func memSuffix(_ snap: DeviceSnapshot) -> String {
        guard let mem = snap.memoryUsedTotalGB() else { return "" }
        return " · mem \(String(format: "%.1f", mem.used))/\(Int(mem.total)) GB"
    }

    private var heartbeat: String {
        guard let snap else { return "—" }
        let s = Int(snap.ageSeconds())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }

    private var lastSync: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: snapshot.generatedAt)
    }
}
