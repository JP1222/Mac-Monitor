// LogsPanel.swift
//
// Streaming-logs surface. The handoff spec (§05.03) is explicit: don't fake a
// fixed-height div with a blinking caret — use `ScrollViewReader` + `LazyVStack`
// appending to a published array, auto-scrolling to the last line. That's
// exactly what this builds. The log *stream* backend (agent → app) isn't wired
// yet, so the window feeds representative SAMPLE lines and the header shows a
// "sample" badge instead of a live indicator — the structure is real, the data
// is honestly labeled until the stream lands.

import SwiftUI

struct LogLine: Identifiable, Hashable {
    enum Level: String { case info, step, cache, warn, error }
    let id: Int
    let time: String
    let level: Level
    let text: String
}

struct LogsPanel: View {
    let lines: [LogLine]
    /// True once a real stream feeds `lines`. False = the sample preview.
    var isLive: Bool = false
    /// Header context, e.g. "build-images · kds-api · step 14/22".
    var context: String = ""

    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable { case all = "All", warn = "Warn+", step = "Step"; var id: String { rawValue } }

    private var filtered: [LogLine] {
        switch filter {
        case .all: return lines
        case .warn: return lines.filter { $0.level == .warn || $0.level == .error }
        case .step: return lines.filter { $0.level == .step }
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(spacing: 0) {
            header
            Divider().overlay(MMTokens.glassHairline)
            logBody
        }
        // A console stays solid-dark (not frosted) like Xcode's debug area, but
        // gets the same top-lit hairline + shadow as the Material cards so it
        // reads as part of the same elevated surface family.
        .background(MMTokens.rgba(10, 10, 12, 0.92), in: shape)
        .overlay {
            shape.strokeBorder(
                LinearGradient(colors: [MMTokens.rgba(255, 255, 255, 0.12), MMTokens.rgba(255, 255, 255, 0.03)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(0.25), radius: 7, x: 0, y: 3)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            if isLive {
                StatusDot(tone: MMTokens.blue, glow: MMTokens.blueGlow, pulse: true, size: 6)
            } else {
                StatusDot(tone: MMTokens.slate, glow: MMTokens.rgba(123, 133, 151, 0.18), size: 6)
            }
            Text(isLive ? "Logs · streaming" : "Logs")
                .font(MMFont.rounded(size: 11.5, weight: .bold))
                .tracking(0.5).textCase(.uppercase)
                .foregroundStyle(MMTokens.ink)
            if !isLive {
                Text("sample")
                    .font(MMFont.rounded(size: 9.5, weight: .heavy))
                    .tracking(0.5).textCase(.uppercase)
                    .foregroundStyle(MMTokens.amber)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(MMTokens.amberGlow, in: Capsule())
            }
            if !context.isEmpty {
                Text(context).font(MMFont.mono(size: 11)).foregroundStyle(MMTokens.inkSoft).lineLimit(1)
            }
            Spacer(minLength: 8)
            filterTabs
            Button {} label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(MMTokens.inkMuted)
                .help("Pop out logs")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(MMTokens.rgba(255, 255, 255, 0.02))
    }

    private var filterTabs: some View {
        HStack(spacing: 4) {
            ForEach(Filter.allCases) { f in
                let active = f == filter
                Button { filter = f } label: {
                    Text(f.rawValue)
                        .font(MMFont.rounded(size: 10.5, weight: .semibold))
                        .foregroundStyle(active ? MMTokens.ink : MMTokens.inkMuted)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(active ? MMTokens.rgba(255, 255, 255, 0.10) : .clear,
                                    in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(MMTokens.rgba(255, 255, 255, 0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Body

    @ViewBuilder
    private var logBody: some View {
        if lines.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "text.alignleft").font(.system(size: 22)).foregroundStyle(MMTokens.inkFaint)
                Text("No active build")
                    .font(MMFont.rounded(size: 13, weight: .semibold)).foregroundStyle(MMTokens.inkMuted)
                Text("Logs stream here while a runner is building.")
                    .font(MMFont.rounded(size: 11.5)).foregroundStyle(MMTokens.inkSoft)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered) { line in
                            logRow(line).id(line.id)
                        }
                        if isLive { liveCaret.id(-1) }
                    }
                    .padding(.vertical, 10)
                }
                .background(
                    RadialGradient(colors: [MMTokens.blue.opacity(0.04), .clear],
                                   center: .bottom, startRadius: 0, endRadius: 320)
                )
                .onAppear { scrollToEnd(proxy) }
                .onChange(of: filtered.count) { scrollToEnd(proxy) }
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if isLive { proxy.scrollTo(-1, anchor: .bottom) }
        else if let last = filtered.last { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private func logRow(_ line: LogLine) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(line.time)
                .foregroundStyle(MMTokens.inkFaint)
                .frame(width: 78, alignment: .trailing)
            Text(line.text)
                .foregroundStyle(color(for: line.level))
                .fontWeight(line.level == .step ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(MMFont.mono(size: 11.5))
        .padding(.horizontal, 14).padding(.vertical, 1)
        .background(rowTint(line.level))
    }

    private var liveCaret: some View {
        HStack(spacing: 12) {
            Text("…now").foregroundStyle(MMTokens.inkFaint).frame(width: 78, alignment: .trailing)
            HStack(spacing: 6) {
                ResultGlyph(result: .building, size: 12)
                Text("waiting on layer cache…").foregroundStyle(MMTokens.blue)
            }
            Spacer(minLength: 0)
        }
        .font(MMFont.mono(size: 11.5))
        .padding(.horizontal, 14).padding(.vertical, 2)
    }

    private func color(for level: LogLine.Level) -> Color {
        switch level {
        case .warn: return MMTokens.amber
        case .error: return MMTokens.tomato
        case .step: return MMTokens.blue
        case .cache: return MMTokens.inkSoft
        case .info: return MMTokens.ink
        }
    }
    private func rowTint(_ level: LogLine.Level) -> Color {
        switch level {
        case .warn: return MMTokens.amber.opacity(0.06)
        case .error: return MMTokens.tomato.opacity(0.06)
        case .step: return MMTokens.blue.opacity(0.05)
        default: return .clear
        }
    }
}

// MARK: - Sample data

extension LogsPanel {
    /// Representative lines mirroring `MW_LOG_LINES` from the prototype — shown
    /// with the "sample" badge until real log streaming is wired through the
    /// agent. Kept here (not in the data layer) because it's view-fixture data.
    static let sampleLines: [LogLine] = [
        .init(id: 0, time: "14:32:08.214", level: .info, text: "→ docker buildx build --platform linux/arm64 --target prod ."),
        .init(id: 1, time: "14:32:08.301", level: .step, text: "[+] Building 12.4s (14/22)"),
        .init(id: 2, time: "14:32:09.142", level: .info, text: "  => [internal] load build definition from Dockerfile     0.0s"),
        .init(id: 3, time: "14:32:10.022", level: .cache, text: "  => CACHED [base 2/3] RUN apk add --no-cache curl tini   0.0s"),
        .init(id: 4, time: "14:32:10.118", level: .cache, text: "  => CACHED [deps 1/4] COPY package.json pnpm-lock.yaml   0.0s"),
        .init(id: 5, time: "14:32:10.620", level: .info, text: "  => [deps 2/4] RUN corepack enable && pnpm fetch          4.8s"),
        .init(id: 6, time: "14:32:15.404", level: .info, text: "  => [build 1/3] COPY . .                                  0.3s"),
        .init(id: 7, time: "14:32:15.711", level: .step, text: "  => [build 2/3] RUN pnpm -F kds-api build"),
        .init(id: 8, time: "14:32:16.020", level: .info, text: "    ↳ kds-api: tsc --noEmit  ✓ 0 errors"),
        .init(id: 9, time: "14:32:17.412", level: .info, text: "    ↳ kds-api: vite build  modules transformed: 487"),
        .init(id: 10, time: "14:32:18.011", level: .warn, text: "    ⚠ unused export 'legacyPasskeyShim' in src/auth/passkey.ts"),
        .init(id: 11, time: "14:32:19.044", level: .info, text: "    ↳ kds-api: built in 3.61s · 412.8 kB"),
        .init(id: 12, time: "14:32:19.412", level: .step, text: "  => [build 3/3] RUN pnpm -F kds-api prune --prod"),
    ]
}
