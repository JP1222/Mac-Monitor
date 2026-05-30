# Mac Monitor — AI Development Guide

SwiftUI menu bar app + WidgetKit + Swift daemon. Developed primarily by AI agents (Claude Code). Every claim below is backed by an Apple doc, WWDC session, or community-verified source — links inline.

## Repo layout

| Path | Role |
| --- | --- |
| `MacMonitor/` | Main app (MenuBarExtra + Popover) |
| `MacMonitorWidgets/` | Widget extension (small / medium / large) |
| `MacMonitorAgent/` | Swift Package, local daemon on `http://127.0.0.1:8765` |
| `Shared/` | Shared model, design tokens, App Group storage |
| `project.yml` | XcodeGen source of truth. `MacMonitor.xcodeproj` is generated — gitignored. |

## Before you start coding

1. `git pull --ff-only` — sync with `origin/main` first.
2. If `project.yml` changed: `xcodegen generate`.
3. If touching the agent: `cd MacMonitorAgent && swift build -c release`.
4. Skim recent commits: `git log --oneline -20`.

## Build & run

```bash
# App build via CLI
xcodebuild -scheme MacMonitor -configuration Debug build

# Agent — LOCAL Mac: bundled in the app, auto-registered via SMAppService
# (AgentInstaller). Just build + run the app; no manual install. The agent
# binary lives at MacMonitor.app/Contents/MacOS/macmonitor-agent, its plist at
# Contents/Library/LaunchAgents/. The app is NOT sandboxed for this to work
# (macOS blocks a sandboxed app from registering a non-sandboxed helper).

# Agent — REMOTE build-farm Macs: standalone (the app can't install on them)
cd MacMonitorAgent && swift build -c release
sudo cp .build/release/macmonitor-agent /usr/local/bin/
cp launchd/com.jp1222.macmonitor-agent.plist ~/Library/LaunchAgents/   # absolute-path variant
launchctl bootout gui/$(id -u)/com.jp1222.macmonitor-agent 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jp1222.macmonitor-agent.plist

# Agent logs (remote variant only — the bundled one omits Std*Path; see below)
tail -f /tmp/macmonitor-agent.{out,err}.log
```

GUI iteration: open `MacMonitor.xcodeproj`, ⌘R the `MacMonitor` scheme.

### Rebuilding the bundled agent (SMAppService) — three non-obvious gotchas
The bundled-agent path is finicky to sign; all three of these are verified and
each produces a confusing `register()` failure:
1. **DerivedData must live OUTSIDE the git worktree.** Inside `.claude/worktrees/…`
   the linked binaries inherit the `com.apple.provenance` xattr → codesign fails
   `"resource fork, Finder information, or similar detritus not allowed"`. Use the
   default `~/Library/Developer/Xcode/DerivedData`, or `xattr -cr` the bundle.
2. **Clean build (`xcodebuild clean build`), not incremental.** Incremental leaves
   the embedded plist/helper signature stale → `SMAppServiceErrorDomain code 3,
   "Codesigning failure loading plist" (-67054)`.
3. **`MacMonitorAgent/launchd/agent-bundle.plist` must NOT set `Standard{Out,Error}Path`.**
   macOS 14.4+ rejects them for an app-registered job → `code 22 "Invalid argument"`.
   (The /usr/local/bin remote variant keeps them — it's not SMAppService-registered.)
Debug tip: this app's os_log isn't readable via `log show` from a headless shell;
write the `register()` NSError to the App Group container to see it. `sfltool dumpbtm`
(no sudo) shows the Login Items / BTM state.

## SwiftUI / WidgetKit / macOS pitfalls (verified)

### `ScrollView` inside `MenuBarExtra(.window)` shrinks on second open
- Apply `.fixedSize(horizontal: false, vertical: true)` to the `ScrollView` to pin intrinsic height. ([Apple Forums #741601](https://developer.apple.com/forums/thread/741601))
- This project uses plain `VStack` + `.prefix(N)` row caps + "+N more" footer instead, because predictable max-height is a feature (popover can't grow unbounded for noisy repos). If you switch back to `ScrollView`, use `fixedSize`.

### Opening Settings / secondary windows from an `LSUIElement` app
- SwiftUI `Window` / `Settings` scenes **do** work, but the window opens behind other apps — macOS won't foreground a windowed app with no Dock icon. ([steipete.me — 5-hour journey](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items), [FB10184971](https://github.com/feedback-assistant/reports/issues/327))
- Fix: flip `NSApp.setActivationPolicy(.regular)` → open window → flip back to `.accessory` on close.
- This project hosts Settings via AppKit `NSWindow` (`SettingsWindowController`) — equivalent solution, predates the flip-pattern writeup.

### App Group state sync is real, but the symptom you'll chase is the wrong one
- The `cfprefsd` warning when reading `UserDefaults(suiteName:)` from the widget process is **benign** — reads work. ([Apple Forums #659448](https://developer.apple.com/forums/thread/659448))
- The real issue: `UserDefaults.didChangeNotification` does **not** cross processes. After the app writes, the widget won't know. ([pointfreeco #3459](https://github.com/pointfreeco/swift-composable-architecture/discussions/3459))
- Fix: every write that affects widget content calls `WidgetCenter.shared.reloadAllTimelines()`.
- This project also uses a JSON file in the App Group container (`SnapshotStore`) — file IO is simpler than KVO for the snapshot payload.

### `WidgetCenter.reloadAllTimelines()` is rate-limited
- WidgetKit budgets ~40–70 reloads/day per visible widget; the OS silently throttles excess. ([WWDC21-10048](https://wwdcnotes.com/documentation/wwdcnotes/wwdc21-10048-principles-of-great-widgets/), [Apple — Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date))
- Debounce to ≥5s minimum. This project uses 5s in `SnapshotStore`.

### Secrets must live in Keychain, NOT App Group containers
- Shared `UserDefaults` and App Group files are **not encrypted**. Only Keychain access groups encrypt across app + widget + daemon. ([Apple — Sharing keychain items across apps](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps))
- This project's `KeychainStore` is already correct; don't "simplify" PAT storage to UserDefaults.

### `Process` (NSTask) has two foot-guns
- `task.terminationStatus` before `task.waitUntilExit()` throws `NSInvalidArgumentException`. ([Apple docs](https://developer.apple.com/documentation/foundation/process/1415801-terminationstatus))
- If the child writes >~64KB to a pipe, calling `waitUntilExit()` before draining it **deadlocks** — and this includes **stderr even if you discard it**: an undrained stderr pipe fills and blocks the child just like stdout. Drain BOTH concurrently (background `readDataToEndOfFile`) alongside a timeout watchdog that escalates `SIGTERM → SIGKILL` so a wedged child can't hang forever. ([Swift Forums — frozen Process](https://forums.swift.org/t/the-problem-with-a-frozen-process-in-swift-process-class/39579))
- Both `runShell` impls (`DeviceHealthCollector`, `AgentActions`) had this; fixed in `2511969`. `docker buildx prune` / `system df -v` easily exceed 64KB.

### `withTaskGroup` vs `withThrowingTaskGroup`
- For "fetch N independent endpoints, tolerate per-endpoint failure": `withTaskGroup` (non-throwing) + `try? await ... ?? defaultValue`.
- `withThrowingTaskGroup` cancels siblings as soon as a throw propagates out via `try await next()` or iteration. ([SE-0304](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md), [HWS](https://www.hackingwithswift.com/quick-start/concurrency/how-to-cancel-a-task-group))
- This project uses non-throwing groups in `DashboardViewModel.refresh` — one broken endpoint must not blank the whole popover.

### Live-ticking elapsed / progress
- `TimelineView(.periodic(from: .now, by: 1))` wraps a subtree and rerenders every second — system-managed, power-aware. ([Apple — TimelineSchedule.periodic](https://developer.apple.com/documentation/swiftui/timelineschedule/periodic(from:by:)))
- SwiftUI's animation engine only ticks on data change; TimelineView bridges to wall clock. Don't use `Timer.publish` for the same job.

### Snapshot values are not live values — store the constant on the model
- If the ViewModel computes a snapshot derivative (e.g. `etaSeconds = avg − elapsed_at_snapshot`), **do NOT** try to recover the original constant in the view as `derivative + elapsed_now`. The view sees `elapsed_now`, not `elapsed_at_snapshot` — the "recovered" constant drifts every second by `(elapsed_now − elapsed_snapshot)`, which pins the live value to its snapshot. The TimelineView reruns every second but the displayed number never changes.
- **Rule**: store the source-of-truth constant on the model so live = `constant − elapsed_now` cleanly. See `WorkflowJob.historicalAvgSeconds` and the comment on that property.
- This bit ETA in `RunnerCardView`: appeared to tick but was mathematically frozen at the snapshot value, and disappeared entirely once snapshot eta hit 0 (build over historical avg).

### LaunchAgent lifecycle
- `KeepAlive=true` implicitly sets `RunAtLoad=true`. ([launchd.plist(5)](https://keith.github.io/xcode-man-pages/launchd.plist.5.html))
- launchd sends `SIGTERM`, then `SIGKILL` after ~5–20s grace. Daemons that don't flush on `SIGTERM` lose state on logout/reboot. Our agent is stateless, so this is a non-issue today — install a signal handler if you add caching.

### Local agent HTTP server: loopback + authenticated
- The agent exposes **mutating** POSTs (prune cache, restart runners). `NWListener` with no `requiredLocalEndpoint` binds `0.0.0.0` — the whole LAN can hit it. Pin to `.ipv4(.loopback)`. Fixed in `2511969`.
- Loopback alone doesn't stop browser CSRF (a page can `fetch('http://127.0.0.1:8765/...')`). Gate mutating routes behind a shared-secret `Bearer` token the app provisions in the App Group container (`SnapshotStore.agentToken` ↔ agent's `AgentToken`, same file by absolute path). GET stays open. The agent parses request-line + headers only, so header auth lives in `HTTPServer.serve`.
- Don't block the accept loop: run shell-outs on a concurrent work queue, not the serial connection queue.

## GitHub Actions API specifics

### Job → runner stitching
- `GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs` returns `runner_name` per job (nullable string). ([GitHub REST docs](https://docs.github.com/en/rest/actions/workflow-jobs))
- Match `WorkflowJob.runner_name == Runner.name` exactly. The old `availableJobs.removeFirst()` fallback silently misassigned a (possibly cross-repo) job to the wrong card — removed in `ecc2a28`. No match → leave `currentJob` nil (placeholder).

### A run can be `queued` while its jobs are `in_progress`
- A run's `status` stays `queued` until ALL its jobs leave queued. So a parallel run is `queued` at the run level while individual jobs already run `in_progress` on runners. Querying only `runs?status=in_progress` misses them → busy runners stuck on "Job starting…". Fetch `in_progress` AND `queued` runs, then filter to `in_progress` jobs. Fixed in `16ddf2d`.
- Nullable fields bite: `head_branch`/`head_sha` are `null` for tag pushes & fork PRs; a non-optional decode fails the WHOLE response. Keep run/job DTO fields optional, and branch result mapping on `status` first (a completed run with an unknown `conclusion` is a failure, not a perpetual spinner).

### `/runners` and `/runs|/jobs` skew
- The two endpoints can disagree in the same poll window: `runs/jobs` may show `queued` while `runners` shows the runner as `online & not busy` (or vice versa). ([Community #186811](https://github.com/orgs/community/discussions/186811))
- Render best-available data with a placeholder when state conflicts. This project's "Building card with no job metadata" placeholder (`RunnerCardView.buildingPlaceholderBody`) handles the case where the runner says "busy" but no job payload has surfaced.

### Rate limit
- Authenticated calls: 5000 req/hr. Each refresh ≈ 1 call per repo per endpoint. Settings caps the picker at 15s minimum interval for this reason.

## Settings & user state

- GitHub PAT → `KeychainStore`. Touch ID gate optional via `LAContext.deviceOwnerAuthentication`.
- Repo list / refresh interval / Touch ID toggle → `UserSettings` (iCloud KV with `UserDefaults` fallback — free Apple ID has no iCloud entitlement, falls back silently).
- Setters post `UserSettings.didChangeNotification`; `DashboardViewModel` listens and triggers immediate refresh. No manual wiring needed.

## Dogfood loop

Mac Monitor watches Yolo-Rollo CI, which runs on this MacBook Pro via self-hosted runners (`macbook-pro-1`, `macbook-pro-2`). To verify a change end-to-end:

1. Push to Yolo-Rollo or `gh workflow run ci.yml -R JP1222/Yolo-Rollo`.
2. Watch the popover within ~15s.
3. Verify: building card lights → progress fills → result glyph → recent runs entry appears.

## Commit style

- Imperative subject ≤72 chars: `Runner card: distinct placeholder for BUILDING but no job metadata`.
- Body explains **why** when fixing a regression — reference the symptom and root cause so the lesson survives in `git log`.
- One concern per commit. Solo dev project — no Co-Authored-By tags.

## When you're stuck

| Symptom | First check |
| --- | --- |
| Build errors after pull | `xcodegen generate` — `project.yml` often drifts ahead of cached `.xcodeproj` state |
| Widget shows stale data | does `~/Library/Group Containers/group.com.jp1222.macmonitor/Library/Application Support/dashboard.snapshot.v1.json` exist? if not, launch the app once. (Note: a degraded refresh deliberately does NOT overwrite this, to preserve last-good for the widget.) |
| Widget never updates | App must call `WidgetCenter.shared.reloadAllTimelines()` after writing — `didChangeNotification` doesn't cross processes |
| Agent unreachable | `curl http://127.0.0.1:8765/health` and `launchctl list \| grep macmonitor-agent` |
| Settings window opens behind other apps | Need the `setActivationPolicy(.regular)` flip pattern (or AppKit `NSWindow` like this project uses) |
| `Process` hangs | Child wrote >64KB to a pipe you haven't drained — see Process pitfall above |
| Popover content blank | PAT missing or lacks scope — needs `Actions: Read + Administration: Read + Metadata: Read` for monitored repos |
