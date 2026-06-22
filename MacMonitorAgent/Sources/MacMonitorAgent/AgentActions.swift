// AgentActions.swift
//
// Server-side handlers for the POST endpoints that mutate state on this
// Mac:
//
//   POST /actions/prune-cache    → `docker buildx prune -f`
//   POST /actions/restart-runners → kickstart all actions.runner.* launchd
//                                  services (your self-hosted GitHub
//                                  Actions runners)
//   POST /actions/start-runners  → bootstrap (load) all actions.runner.*
//                                  LaunchAgents — this Mac's runners join the
//                                  CI pool (online)
//   POST /actions/stop-runners   → bootout (unload) them — this Mac's runners
//                                  leave the pool (offline)
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

    // MARK: - Start / stop runners

    /// Bring this Mac's self-hosted runner LaunchAgents online or offline by
    /// (un)loading them through launchd — the in-app equivalent of
    /// `actions-runner/svc.sh start|stop`. `online == true` bootstraps every
    /// installed `actions.runner.*` agent that isn't already loaded;
    /// `online == false` boots out every one that is. Idempotent: a runner
    /// already in the requested state is left untouched and still counts as ok.
    static func setRunners(online: Bool) -> Result {
        let installed = installedRunnerLaunchAgents()
        guard !installed.isEmpty else {
            return Result(ok: false, message: "No actions.runner.*.plist in ~/Library/LaunchAgents. Install with actions-runner/svc.sh install.", affected: nil)
        }
        // Signal intent to the runner-priority autoscaler (Mac Mini primary /
        // MacBook failover) BEFORE touching launchd, so a racing 60s tick already
        // sees it: pinned => keep this Mac's runners online alongside the Mac Mini
        // (2-wide; both take jobs); unpinned => let mini-priority retire them when
        // idle. No-op when ~/runner-bin (the autoscaler's home) is absent.
        setRunnerPin(online)
        let uid = getuid()
        let loaded = Set(loadedRunnerLabels())
        var changed: [String] = []
        var errors: [String] = []
        for agent in installed {
            let alreadyInState = online ? loaded.contains(agent.label) : !loaded.contains(agent.label)
            if alreadyInState { continue }
            let r = online
                ? runShell("/bin/launchctl", args: ["bootstrap", "gui/\(uid)", agent.path], timeout: 15)
                : runShell("/bin/launchctl", args: ["bootout", "gui/\(uid)/\(agent.label)"], timeout: 15)
            if r.exitCode == 0 {
                changed.append(agent.label)
            } else {
                errors.append("\(agent.label): \(r.stderr.prefix(80))")
            }
        }
        let verb = online ? "online" : "offline"
        guard errors.isEmpty else {
            return Result(ok: !changed.isEmpty, message: errors.joined(separator: "; "), affected: changed)
        }
        return Result(
            ok: true,
            message: changed.isEmpty ? "Runner(s) already \(verb)" : "\(changed.count) runner(s) \(verb)",
            affected: changed.isEmpty ? installed.map(\.label) : changed
        )
    }

    /// A self-hosted runner LaunchAgent installed on this Mac.
    private struct RunnerLaunchAgent { let label: String; let path: String }

    /// All `actions.runner.*.plist` files the runner dropped in
    /// ~/Library/LaunchAgents during `svc.sh install`. The launchd label is the
    /// filename without the `.plist` suffix.
    private static func installedRunnerLaunchAgents() -> [RunnerLaunchAgent] {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return names
            .filter { $0.hasPrefix("actions.runner.") && $0.hasSuffix(".plist") }
            .sorted()
            .map { RunnerLaunchAgent(label: String($0.dropLast(".plist".count)), path: (dir as NSString).appendingPathComponent($0)) }
    }

    /// Labels of the currently-loaded `actions.runner.*` LaunchAgents (those in
    /// `launchctl list`). Empty on failure or when none are loaded.
    private static func loadedRunnerLabels() -> [String] {
        let list = runShell("/bin/launchctl", args: ["list"], timeout: 5)
        guard list.exitCode == 0 else { return [] }
        return list.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 3 else { return nil }
                let label = String(parts[2])
                return label.hasPrefix("actions.runner.") ? label : nil
            }
    }

    /// Path of the runner-priority autoscaler's manual-override sentinel.
    private static let runnerPinPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent("runner-bin/.macbook-pinned")

    /// Write (pin) or remove (unpin) the autoscaler override sentinel. Best-effort
    /// and only when ~/runner-bin (the watchdog's home) exists, so it's a harmless
    /// no-op on a Mac that doesn't run the mini-priority autoscaler.
    private static func setRunnerPin(_ pinned: Bool) {
        let fm = FileManager.default
        let dir = (runnerPinPath as NSString).deletingLastPathComponent
        guard fm.fileExists(atPath: dir) else { return }
        if pinned {
            fm.createFile(atPath: runnerPinPath, contents: Data())
        } else {
            try? fm.removeItem(atPath: runnerPinPath)
        }
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
        // what prevents the >64KB deadlock for `docker buildx prune`.
        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning && Date() < deadline { usleep(20_000) }
        if task.isRunning { task.terminate() }
        // BOUND the post-SIGTERM wait. `waitUntilExit()` has NO timeout, so a
        // child that ignores/blocks SIGTERM (a trap handler) or is wedged in an
        // uninterruptible state (a hung docker daemon socket) would pin this
        // work-queue thread FOREVER — and since serve() runs route work on a
        // shared concurrent queue, enough such events exhaust the agent's pool
        // and it stops answering. We still refuse to SIGKILL (orphans docker's
        // children); we just poll for exit with a hard cap instead of blocking
        // unboundedly. The (possibly still-running) child winds down on its own.
        let exitDeadline = Date().addingTimeInterval(3)
        while task.isRunning && Date() < exitDeadline { usleep(20_000) }
        // Only touch outData/errData once the io tasks have finished writing
        // them — reading mid-write (if the child never closed its fds) is a data
        // race. If the drain didn't complete, give up on the output.
        let drained = readGroup.wait(timeout: .now() + 1) == .success
        // `terminationStatus` throws NSInvalidArgumentException if read before
        // the process exits — guard it. A child we gave up on reports as -1.
        let code: Int32 = task.isRunning ? -1 : task.terminationStatus
        return (
            code,
            drained ? (String(data: outData, encoding: .utf8) ?? "") : "",
            drained ? (String(data: errData, encoding: .utf8) ?? "") : ""
        )
    }
}
