// DeviceHealthCollector.swift
//
// Builds a DeviceSnapshot from local OS APIs + a few shell-outs. Mirrors
// the shape of the same struct in MacMonitor's Shared/ (we duplicate it
// here to keep this binary standalone — no Package dependency on the
// SwiftUI app).
//
// Data sources:
//   - disk:        statvfs() for the root and OrbStack VM mount points
//   - cpu load:    getloadavg() (1-minute average normalized by core count)
//   - memory:      vm_statistics64 via host_statistics64
//   - thermals:    NSProcessInfo.thermalState
//   - uptime:      sysctl kern.boottime
//   - OrbStack:    pgrep "OrbStack Helper" (running if any pids returned)
//   - Docker:      `docker ps -q | wc -l`
//   - BuildKit:    `du -sk ~/buildx-cache` (the CI's `type=local` cache —
//                  the store that actually grows build-to-build). Falls back
//                  to `docker system df` Build Cache when that dir is absent.
//
// Each shell-out has a fast-fail timeout (2s). If a tool isn't installed
// (no Docker, no OrbStack) we just report zero / false — the agent never
// errors out the whole snapshot for one missing data source.

import Foundation
import Darwin

enum DeviceHealthCollector {

    static func collect() -> DeviceSnapshot {
        let now = Date()
        return DeviceSnapshot(
            deviceID: deviceIdentifier(),
            capturedAt: now,
            cpuLoad: cpuLoadOneMinute(),
            memoryPressurePercent: memoryPressurePercent(),
            thermalState: thermalState(),
            uptimeSeconds: uptimeSeconds(),
            orbStackRunning: orbStackRunning(),
            dockerContainersRunning: dockerContainersRunning(),
            disks: disks(),
            agentVersion: "0.1.0"
        )
    }

    // MARK: - deviceID

    /// Stable per-machine identifier — uses the system's "ComputerName"
    /// (System Settings → General → About → Name).
    private static func deviceIdentifier() -> String {
        Host.current().localizedName ?? "mac"
    }

    // MARK: - CPU

    private static func cpuLoadOneMinute() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        let count = getloadavg(&loads, 3)
        guard count >= 1 else { return 0 }
        let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
        return min(1.0, max(0, loads[0] / max(cores, 1)))
    }

    // MARK: - Memory

    private static func memoryPressurePercent() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { p in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, p, &size)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        return min(100, max(0, (used / total) * 100))
    }

    // MARK: - Thermals

    private static func thermalState() -> ThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return .nominal
        case .fair:     return .fair
        case .serious:  return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }

    // MARK: - Uptime

    private static func uptimeSeconds() -> TimeInterval {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0 else { return 0 }
        let boot = Double(bootTime.tv_sec) + Double(bootTime.tv_usec) / 1_000_000.0
        return Date().timeIntervalSince1970 - boot
    }

    // MARK: - OrbStack / Docker

    private static func orbStackRunning() -> Bool {
        // pgrep returns 0 (found) or 1 (not found).
        runShell("/usr/bin/pgrep", args: ["-q", "OrbStack"]).exitCode == 0
    }

    private static func dockerContainersRunning() -> Int {
        let result = runShell(dockerBinary, args: ["ps", "-q"])
        if result.exitCode != 0 { return 0 }
        return result.stdout.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }.count
    }

    /// Resolve a docker binary across Docker Desktop (/usr/local/bin),
    /// Homebrew (/opt/homebrew/bin), and OrbStack (/Applications/OrbStack.app/...).
    private static var dockerBinary: String {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/usr/local/bin/docker"   // best-effort default for error path
    }

    // MARK: - Disks

    private static func disks() -> [DiskUsage] {
        var out: [DiskUsage] = []
        out.append(diskAt(path: "/", layer: .apfsHost, label: "APFS host", sub: "/ on macOS"))

        // OrbStack VM data dir.
        let orbStackPath = "\(NSHomeDirectory())/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data"
        if FileManager.default.fileExists(atPath: orbStackPath) {
            out.append(diskFolder(path: orbStackPath, layer: .orbStackVM, label: "OrbStack VM", sub: "linux arm64"))
        }

        // BuildKit cache — measure the CI's `type=local` cache at
        // ~/buildx-cache (the workflow's `cache-to: type=local,dest=
        // $HOME/buildx-cache/<app>`). That's a content-addressed file store
        // that actually grows build-to-build and is the thing worth watching
        // for "time to prune". It is NOT visible to `docker system df`, which
        // only reports the daemon's internal buildkit cache (the `docker`
        // driver) — not the type=local export, and not a transient
        // docker-container builder's volume. So `du` the dir directly. Fall
        // back to `docker system df` only when ~/buildx-cache is absent (e.g.
        // a Mac that caches via the GHA/registry exporter instead).
        let localBuildxCache = "\(NSHomeDirectory())/buildx-cache"
        if FileManager.default.fileExists(atPath: localBuildxCache) {
            out.append(buildKitCacheViaLocalDir(path: localBuildxCache))
        } else if let cache = buildKitCacheViaDockerDF() {
            out.append(cache)
        }
        return out
    }

    /// Measure the `type=local` buildx cache dir (`~/buildx-cache`, summed
    /// across its per-app subdirs) via `du -sk`. This is the cache the build
    /// workflow writes with `cache-to: type=local` — a content-addressed file
    /// store, invisible to `docker system df`, that actually grows build-to-
    /// build (snapshot: ~12GB across 6 apps, capped per-app at 8GB by the
    /// workflow's prune step). Denominator fixed at 30GB to match the "cache
    /// pressure" meter: past 30GB the bar clamps to 100% and tone goes
    /// critical → a clear "time to prune" signal.
    private static func buildKitCacheViaLocalDir(path: String) -> DiskUsage {
        // `du -sk` is stat-only (no file reads), but a multi-GB cache has many
        // small blob files — give it 6s (vs the 3s default) so a busy disk
        // can't truncate it to 0. Mutually exclusive with the docker df
        // fallback (the caller picks exactly one), so this never stacks toward
        // /health's 12s ceiling. Tiny stdout ("<kb>\t<path>") → post-exit drain
        // is safe (no 64KB-pipe deadlock risk).
        let result = runShell("/usr/bin/du", args: ["-sk", path], timeout: 6)
        let kb = Int64(result.stdout.split(separator: "\t").first?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
        let used = kb * 1024
        let denominator: Int64 = 30_000_000_000   // 30 GB design threshold
        return DiskUsage(
            layer: .buildKitCache,
            label: "BuildKit cache",
            sub: "~/buildx-cache",
            usedBytes: used,
            totalBytes: max(used, denominator),
            state: tone(for: used, total: denominator)
        )
    }

    /// Parse `docker system df` and return the Build Cache row as a
    /// DiskUsage. Fallback for Macs with no ~/buildx-cache (e.g. caching via
    /// the GHA/registry exporter). The denominator is fixed at 30GB to match
    /// the design's "cache pressure" semantics — when cache > 30GB the meter
    /// shows 100% (clamped) and the user gets a clear "time to prune" signal.
    private static func buildKitCacheViaDockerDF() -> DiskUsage? {
        // 6s (vs the 3s default): under launchd / a busy Docker, `docker
        // system df` is slow. Too tight a timeout makes this fail → we fall
        // back to host-side `du` on ~/.docker/buildx, which for Docker Desktop
        // is just metadata (KB) — wildly under the real cache size. The app's
        // /health timeout is 12s, comfortably above this.
        let result = runShell(dockerBinary, args: ["system", "df"], timeout: 6)
        guard result.exitCode == 0 else { return nil }
        // Lines look like:
        //   Build Cache     216       0         21.26GB   21.26GB
        for raw in result.stdout.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard line.hasPrefix("Build Cache") else { continue }
            // Whitespace-collapse split.
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            // Columns: ["Build", "Cache", TOTAL, ACTIVE, SIZE, RECLAIMABLE, ...]
            // SIZE is index 4 because "Build" and "Cache" are 2 tokens.
            guard parts.count >= 5, let used = parseDockerSize(String(parts[4])) else { continue }
            let denominator: Int64 = 30_000_000_000   // 30 GB design threshold
            let total = max(used, denominator)
            return DiskUsage(
                layer: .buildKitCache,
                label: "BuildKit cache",
                sub: "docker buildx",
                usedBytes: used,
                totalBytes: total,
                state: tone(for: used, total: denominator)
            )
        }
        return nil
    }

    /// Parse Docker's human-readable size strings: "21.26GB", "151.6kB",
    /// "0B", "1.718GB". Docker uses decimal units (1 GB = 1_000_000_000).
    private static func parseDockerSize(_ s: String) -> Int64? {
        // Longest/largest units FIRST so two-char suffixes match before the
        // bare "B" branch — otherwise "5.5TB".hasSuffix("B") matches "B",
        // drops 1 char → Double("5.5T") = nil → the whole row is dropped.
        let units: [(suffix: String, multiplier: Double)] = [
            ("PB", 1_000_000_000_000_000),
            ("TB", 1_000_000_000_000),
            ("GB", 1_000_000_000),
            ("MB", 1_000_000),
            ("kB", 1_000),
            ("B",  1),
        ]
        for (suffix, mult) in units where s.hasSuffix(suffix) {
            let numStr = String(s.dropLast(suffix.count))
            if let num = Double(numStr) {
                return Int64(num * mult)
            }
        }
        return nil
    }

    private static func diskAt(path: String, layer: DiskUsage.Layer, label: String, sub: String) -> DiskUsage {
        var stats = statvfs()
        guard statvfs(path, &stats) == 0 else {
            return DiskUsage(layer: layer, label: label, sub: sub, usedBytes: 0, totalBytes: 1, state: .ok)
        }
        let total = Int64(stats.f_frsize) * Int64(stats.f_blocks)
        let free  = Int64(stats.f_frsize) * Int64(stats.f_bavail)
        let used  = total - free
        return DiskUsage(layer: layer, label: label, sub: sub, usedBytes: used, totalBytes: total, state: tone(for: used, total: total))
    }

    private static func diskFolder(path: String, layer: DiskUsage.Layer, label: String, sub: String) -> DiskUsage {
        // du -sk <path> → "<kb>\t<path>"
        let result = runShell("/usr/bin/du", args: ["-sk", path])
        let kb = Int64(result.stdout.split(separator: "\t").first?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
        let usedBytes = kb * 1024
        // We don't really know the "total" for an arbitrary folder; use the
        // volume's total as the denominator. If statvfs fails, fall back to the
        // folder's own size rather than leaving a zeroed struct (which would
        // make total = 0 and mislabel the folder as 100% of itself).
        var stats = statvfs()
        let total: Int64 = statvfs(path, &stats) == 0
            ? Int64(stats.f_frsize) * Int64(stats.f_blocks)
            : usedBytes
        return DiskUsage(layer: layer, label: label, sub: sub, usedBytes: usedBytes, totalBytes: max(usedBytes, total), state: tone(for: usedBytes, total: total))
    }

    private static func tone(for used: Int64, total: Int64) -> DiskUsage.State {
        guard total > 0 else { return .ok }
        let pct = Double(used) / Double(total)
        if pct > 0.85 { return .critical }
        if pct > 0.7  { return .warn }
        return .ok
    }

    // MARK: - Shell helper

    @discardableResult
    private static func runShell(_ path: String, args: [String], timeout: TimeInterval = 3) -> (exitCode: Int32, stdout: String) {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return (127, "")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do {
            try task.run()
        } catch {
            return (1, "")
        }
        // Every caller here emits SMALL output — `docker ps -q`, `docker
        // system df` (~6 lines), `du -sk`, `pgrep` — all far under the 64KB
        // pipe buffer, so reading after exit can't deadlock (that only happens
        // when a child fills the buffer and blocks before we read). Poll with a
        // timeout; on overrun send SIGTERM and let the child wind down.
        //
        // We deliberately do NOT SIGKILL: force-killing a slow `docker` under
        // launchd's minimal environment orphans its child processes, which pile
        // up and make every subsequent /health call slower (observed: 2.5s →
        // 11s → 20s). SIGTERM lets docker reap its children cleanly.
        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning && Date() < deadline { usleep(20_000) }
        if task.isRunning { task.terminate() }
        task.waitUntilExit()
        // Drain both pipes (discard stderr). Safe post-exit given tiny outputs.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (task.terminationStatus, String(data: outData, encoding: .utf8) ?? "")
    }
}
