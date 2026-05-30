# Mac Monitor

[![Build](https://github.com/JP1222/Mac-Monitor/actions/workflows/build.yml/badge.svg)](https://github.com/JP1222/Mac-Monitor/actions/workflows/build.yml)

A SwiftUI menu bar app + WidgetKit desktop widgets for monitoring self-hosted
GitHub Actions runners on a Mac mini build farm.

Implemented from the Claude Design handoff package
(`Mac Monitor-handoff.zip`). The HTML/CSS/JS prototype lives in
`docs/design-reference/` (not bundled in this commit — keep the original zip).

## What's in the box

- **`MacMonitor`** — the menu bar app target.
  - `MenuBarExtra` with a state-aware glyph (idle / building / warning / failure)
  - Popover dashboard: runners, queue, recent runs, three-layer disk meters
  - Live-ticking progress + ETA on building cards (1Hz `TimelineView`)
  - Settings window (AppKit-hosted, see below) for repos + interval + Touch ID
  - macOS notifications when CI transitions to failure (deduped per-run)
  - Clickable Recent runs → open the run on github.com
  - Inline error banner when GitHub API can't reach the configured repos
- **`MacMonitorWidgets`** — WidgetKit extension target.
  - `systemSmall` — at-a-glance progress ring for the active build
  - `systemMedium` — two runner mini-cards + last run strip
  - `systemLarge` — runner cards + queue/passed/failed counts + recent + disk
  - Reads cached `DashboardSnapshot` from the App Group's JSON file —
    **never** calls GitHub directly.
- **`MacMonitorAgent`** — standalone Swift package (LaunchAgent daemon).
  - Single binary `macmonitor-agent`, runs on each Mac in the build farm
  - `GET /health` on port 8765 returns a JSON `DeviceSnapshot` of the local
    machine's disk / CPU / memory / thermals / OrbStack / Docker state
  - No external dependencies — `NWListener` HTTP server in one file
  - `launchd/com.jp1222.macmonitor-agent.plist` for `launchctl bootstrap`
- **`Shared/`** — code compiled into both Swift targets.
  - `Models/` — `Repository`, `Device`, `Runner`, `WorkflowJob`, `QueueItem`,
    `RecentRun`, `DeviceSnapshot`, `DashboardSnapshot`
  - `Tokens/` — `MMTokens` (1:1 port of `shared.jsx` design tokens),
    `MMTypography`
  - `Components/` — `StatusDot`, `ProgressBarView`, `ResultGlyph`,
    `RunnerBrandGlyph`, `RunnerMenuBarGlyph`, `MMSection`
  - `Icons/` — SF Symbols mapping for the `MMIcon` set
  - `Storage/` — `SnapshotStore` (App Group JSON file + WidgetCenter
    debounce), `KeychainStore` (GitHub PAT with optional Touch ID gate),
    `UserSettings` (repo list + refresh interval + Touch ID toggle,
    iCloud-synced via `NSUbiquitousKeyValueStore` with local fallback),
    `DashboardSnapshot+Mock`

## Setup

### 1. Install XcodeGen

The Xcode project is generated from `project.yml` (a YAML spec). Generated
`.xcodeproj` is gitignored on purpose — regenerate after pulling.

```sh
brew install xcodegen
```

### 2. Generate the project

```sh
xcodegen generate
open MacMonitor.xcodeproj
```

### 3. Sign with your team

Open the project, select each target, and set your Apple Developer team under
*Signing & Capabilities*. The App Group `group.com.jp1222.macmonitor` must
appear (and be checked) for BOTH targets — that's the only way the widget can
read the snapshot the menu bar app writes.

If you want a different bundle prefix or group ID, edit `project.yml`
(`bundleIdPrefix:` and search for `group.com.jp1222.macmonitor`) and the two
`.entitlements` files, then re-run `xcodegen generate`.

### 4. Build + run

`MacMonitor` scheme → ⌘R. The menu bar app appears with a runner glyph; click
it to see the popover with mock data.

To pin the widgets: right-click the desktop → Edit Widgets → drag the Mac
Monitor small/medium/large widgets out.

## Wiring to real data

Both data sources are now live by default:

- **GitHub**: `GitHubClient` reads your fine-grained PAT from Keychain and
  hits `/repos/{owner}/{repo}/actions/{runners,runs,...}` for each repo
  configured in Settings. Multi-repo supported.
- **Agent**: `AgentClient` hits `http://<device.host>:8765/health` on each
  monitored Mac. Build & install per `MacMonitorAgent/README` (or the
  Package.swift comment).

### Setting up the PAT (one-time)

1. Generate at https://github.com/settings/personal-access-tokens/new
   - Repository access: only the repos you want to monitor (or "All
     repositories" if you're lazy)
   - Permissions: **Actions: Read** + **Administration: Read** +
     **Metadata: Read** (auto when other repo perms selected)
   - Expiration: 1 year (GitHub max)
2. Copy the `github_pat_...` value
3. In MacMonitor: click the menu bar glyph → gear icon → Settings window
4. Paste into the **Personal Access Token** SecureField → Save
5. Token is stored in the macOS Keychain (service `MacMonitor.GitHubToken`,
   account `github.com`). Survives reinstalls; never written to plain files.

Toggle **Require Touch ID to read token** in Settings to enable biometric
gating — MacMonitor prompts at launch before fetching, and the token isn't
released to subprocesses without your fingerprint.

### Installing the agent

**Local Mac — automatic.** The app ships the agent inside its bundle
(`Contents/MacOS/macmonitor-agent`) and registers it as a LaunchAgent via
`SMAppService` on first launch (`AgentInstaller`). Nothing to install — just run
the app, then `curl http://127.0.0.1:8765/health` to verify. (This is why the
app is **not** sandboxed: macOS forbids a sandboxed app from registering a
non-sandboxed helper, and the agent must be non-sandboxed to drive docker.)

**Remote Macs — standalone.** The app can't install software on another machine,
so build & install the agent there by hand (same single binary):

```sh
cd MacMonitorAgent
swift build -c release
sudo cp .build/release/macmonitor-agent /usr/local/bin/
mkdir -p ~/Library/LaunchAgents
cp launchd/com.jp1222.macmonitor-agent.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jp1222.macmonitor-agent.plist
curl http://127.0.0.1:8765/health   # verify
```

Then add each remote Mac in Settings as a `label@host` device endpoint (host can
be a Tailscale IP). The app polls `http://<host>:8765/health` on each.

## Architecture

```
┌──────────────────────┐                  ┌──────────────────────┐
│  MacMonitor (app)    │                  │  Widget extension    │
│  ────────────────    │                  │  ────────────────    │
│  GitHubClient        │                  │  TimelineProvider    │
│  AgentClient         │                  │       │              │
│       │              │                  │       ▼              │
│       ▼              │                  │  read DashboardSnap  │
│  DashboardViewModel  │                  │                      │
│       │              │                  │                      │
│       ▼              │                  │                      │
│  SnapshotStore.write ├──────────────────┤  (App Group: shared  │
│  (App Group writer)  │   UserDefaults   │   UserDefaults)      │
│       │              │   group.com.     │                      │
│       ▼              │   jp1222.mac     │                      │
│  WidgetCenter.reload │   monitor        │                      │
└──────────────────────┘                  └──────────────────────┘
```

The widget is a pure reader — it never touches the network. This keeps it:
- fast (no async waits in `getTimeline`)
- power-efficient (the system can render placeholder timelines without waking
  network stacks)
- secure (no token in the widget extension's keychain)

## Design tokens

All color, spacing, and radius values come from `Shared/Tokens/MMTokens.swift`,
which is a 1:1 port of `shared.jsx`'s `MM_TOKENS`. If you tweak a design value,
update both files in lockstep.

## What's NOT here

Per the original brief, the following are intentionally out of scope:

- **Design canvas** (`design-canvas.jsx`, `Mac Monitor.html`) — those were
  the prototype renderer, not deliverables.
- **Notch companion** (`notch-widget.jsx`) — Phase 2.
- **Mac mini agent daemon** — separate project; this app only consumes its
  HTTP contract.

## License

Personal project. No license declared yet.
