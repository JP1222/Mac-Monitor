// AgentActions.swift
//
// Server-side handlers for the POST endpoints that mutate state on this
// Mac:
//
//   POST /actions/prune-cache    → `docker buildx prune -f`
//   POST /actions/restart-runners → kickstart all actions.runner.* launchd
//                                  services (your self-hosted GitHub
//                                  Actions runners)
//
// Returns a small JSON body so the menu bar app can surface success/error
// without parsing log noise.

import Foundation

enum AgentActions {

    struct Result: Codable {
        let ok: Bool
        let message: String?
        let affected: [String]?
    }

    // MARK: - Prune cache

    static func pruneCache() -> Result {
        // `docker buildx prune -f` reclaims BuildKit layer cache without
        // touching images or containers. Conservative — won't delete
        // anything users still need.
        let r = runShell(dockerBinary, args: ["buildx", "prune", "-f"], timeout: 60)
        if r.exitCode == 0 {
            return Result(ok: true, message: "BuildKit cache pruned", affected: nil)
        }
        return Result(ok: false, message: "docker buildx prune failed: \(r.stderr.prefix(200))", affected: nil)
    }

    // MARK: - Restart runners

    /// Discovers all self-hosted runner LaunchAgents on this Mac
    /// (label pattern: `actions.runner.<owner>-<repo>.<runner-name>`) and
    /// kickstarts them. The runner registers this LaunchAgent itself
    /// during `actions-runner/svc.sh install`.
    static func restartRunners() -> Result {
        let list = runShell("/bin/launchctl", args: ["list"], timeout: 5)
        guard list.exitCode == 0 else {
            return Result(ok: false, message: "launchctl list failed", affected: nil)
        }
        let labels: [String] = list.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 3 else { return nil }
                let label = String(parts[2])
                return label.hasPrefix("actions.runner.") ? label : nil
            }
        guard !labels.isEmpty else {
            return Result(ok: false, message: "No actions.runner.* LaunchAgents found. Install with actions-runner/svc.sh install.", affected: nil)
        }
        let uid = getuid()
        var restarted: [String] = []
        var errors: [String] = []
        for label in labels {
            let r = runShell("/bin/launchctl", args: ["kickstart", "-k", "gui/\(uid)/\(label)"], timeout: 10)
            if r.exitCode == 0 {
                restarted.append(label)
            } else {
                errors.append("\(label): \(r.stderr.prefix(80))")
            }
        }
        if errors.isEmpty {
            return Result(ok: true, message: "Restarted \(restarted.count) runner(s)", affected: restarted)
        }
        return Result(ok: !restarted.isEmpty, message: errors.joined(separator: "; "), affected: restarted)
    }

    // MARK: - Shared helpers

    private static var dockerBinary: String {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/usr/local/bin/docker"
    }

    @discardableResult
    private static func runShell(_ path: String, args: [String], timeout: TimeInterval) -> (exitCode: Int32, stdout: String, stderr: String) {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return (127, "", "binary not found: \(path)")
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do { try task.run() } catch { return (1, "", error.localizedDescription) }

        // Drain BOTH pipes CONCURRENTLY with the timeout watchdog. If we waited
        // for exit before reading, a child writing >64KB to a pipe would block
        // on the full buffer while we block on exit → deadlock. `docker buildx
        // prune` prints a "Deleted:" line per layer and easily exceeds 64KB.
        // readDataToEndOfFile returns when the child closes its fds (exits or
        // is killed).
        var outData = Data()
        var errData = Data()
        let readGroup = DispatchGroup()
        let ioQueue = DispatchQueue(label: "macmonitor.agent.actions.io", attributes: .concurrent)
        readGroup.enter()
        ioQueue.async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); readGroup.leave() }
        readGroup.enter()
        ioQueue.async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); readGroup.leave() }

        // Timeout watchdog: SIGTERM at the deadline and let the child wind
        // down. We don't SIGKILL — force-killing `docker` orphans its children
        // under launchd. The concurrent pipe draining above (not the kill) is
        // what prevents the >64KB deadlock for `docker buildx prune`; the
        // timeout only bounds a hung child, and SIGTERM does that cleanly.
        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning && Date() < deadline { usleep(20_000) }
        if task.isRunning { task.terminate() }
        task.waitUntilExit()
        readGroup.wait()
        return (
            task.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
