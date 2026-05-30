// AgentInstaller.swift
//
// Registers the bundled MacMonitorAgent helper as a per-user LaunchAgent via
// SMAppService, so the local agent runs on login and answers on
// 127.0.0.1:8765 — no manual `cp` to ~/bin + `launchctl bootstrap` dance.
//
// The helper binary ships inside the app at Contents/MacOS/macmonitor-agent,
// and its launchd plist at Contents/Library/LaunchAgents/<plistName> (both
// placed there by build phases — see project.yml). SMAppService verifies the
// helper's code signature against the app's, which is why the plist uses
// `BundleProgram` (a bundle-relative path), not an absolute ProgramArguments
// path. Requires macOS 13+ (we target 14).
//
// LOCAL MAC ONLY. The build-farm Mac minis run their OWN copy of the agent,
// installed via the standalone /usr/local/bin LaunchAgent — the app polls them
// over HTTP and can't (and shouldn't) install software on another machine.

import Foundation
import ServiceManagement
import os.log

enum AgentInstaller {

    /// MUST match the filename the build phase writes into
    /// Contents/Library/LaunchAgents — SMAppService looks it up by name.
    static let plistName = "com.jp1222.macmonitor-agent.plist"

    private static let log = Logger(subsystem: "com.jp1222.macmonitor", category: "AgentInstaller")

    static var service: SMAppService { .agent(plistName: plistName) }

    /// Idempotent — safe to call on every launch. Registers the agent the
    /// first time; thereafter it's a cheap status read. Failure is non-fatal:
    /// the Storage panel just lacks local-device data until it's resolved, so
    /// we log and move on rather than blocking app startup.
    @discardableResult
    static func ensureRegistered() -> SMAppService.Status {
        let svc = service
        switch svc.status {
        case .enabled:
            log.debug("local agent already enabled")
        case .requiresApproval:
            // Left disabled in System Settings → General → Login Items (user
            // toggled it off, or a prior install needs re-approval). We can't
            // force-enable, and popping Settings on every launch is hostile —
            // so just note it. Surface a hint in the popover via status if you
            // want a nudge; openSettings() is the escalation.
            log.notice("local agent requires approval in Login Items")
        case .notRegistered, .notFound:
            register(svc)
        @unknown default:
            register(svc)
        }
        return svc.status
    }

    private static func register(_ svc: SMAppService) {
        do {
            try svc.register()
            log.notice("local agent registered")
        } catch {
            log.error("local agent register failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Opens System Settings → Login Items, for a popover affordance when the
    /// agent is stuck in `.requiresApproval`.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// For a future Settings "remove local agent" control. Not wired to UI yet.
    static func unregister() {
        do {
            try service.unregister()
            log.notice("local agent unregistered")
        } catch {
            log.error("local agent unregister failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
