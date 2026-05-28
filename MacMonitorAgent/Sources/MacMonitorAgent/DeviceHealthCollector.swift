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
//   - BuildKit:    `du -sk ~/.docker/buildx` (cached layer storage)
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
        let result = runShell("/usr/local/bin/docker", args: ["ps", "-q"])
        if result.exitCode != 0 { return 0 }
        return result.stdout.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }.count
    }

    // MARK: - Disks

    private static func disks() -> [DiskUsage] {
        var out: [DiskUsage] = []
        out.append(diskAt(path: "/", layer: .apfsHost, label: "APFS host", sub: "/ on macOS"))

        // OrbStack disk: ~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data
        // size is harder to read directly — fall back to its volume's free
        // space which approximates OrbStack VM disk.
        let orbStackPath = "\(NSHomeDirectory())/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data"
        if FileManager.default.fileExists(atPath: orbStackPath) {
            out.append(diskFolder(path: orbStackPath, layer: .orbStackVM, label: "OrbStack VM", sub: "linux arm64"))
        }

        // BuildKit cache from docker buildx — du on the cache dir.
        let buildxCache = "\(NSHomeDirectory())/.docker/buildx"
        if FileManager.default.fileExists(atPath: buildxCache) {
            out.append(diskFolder(path: buildxCache, layer: .buildKitCache, label: "BuildKit cache", sub: "docker buildx"))
        }
        return out
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
        // volume's total as the denominator.
        var stats = statvfs()
        statvfs(path, &stats)
        let total = Int64(stats.f_frsize) * Int64(stats.f_blocks)
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
    private static func runShell(_ path: String, args: [String], timeout: TimeInterval = 2) -> (exitCode: Int32, stdout: String) {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return (127, "")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return (1, "")
        }
        // crude timeout
        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning && Date() < deadline { usleep(20_000) }
        if task.isRunning { task.terminate() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
