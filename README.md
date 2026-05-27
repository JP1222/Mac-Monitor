# Mac Monitor

A SwiftUI menu bar app + WidgetKit desktop widgets for monitoring self-hosted
GitHub Actions runners on a Mac mini build farm.

Implemented from the Claude Design handoff package
(`Mac Monitor-handoff.zip`). The HTML/CSS/JS prototype lives in
`docs/design-reference/` (not bundled in this commit — keep the original zip).

## What's in the box

- **`MacMonitor`** — the menu bar app target.
  - `MenuBarExtra` with a state-aware glyph (idle / building / warning / failure)
  - Popover dashboard: runners, queue, recent runs, three-layer disk meters
  - Quick actions: open Actions on GitHub, restart runner, prune cache
- **`MacMonitorWidgets`** — WidgetKit extension target.
  - `systemSmall` — at-a-glance progress ring for the active build
  - `systemMedium` — two runner mini-cards + last run strip
  - `systemLarge` — runner cards + queue/passed/failed counts + recent + disk
  - Reads cached `DashboardSnapshot` from the shared App Group — **never** calls
    GitHub directly.
- **`Shared/`** — code compiled into both targets.
  - `Models/` — `Repository`, `Device`, `Runner`, `WorkflowJob`, `QueueItem`,
    `RecentRun`, `DeviceSnapshot`, `DashboardSnapshot`
  - `Tokens/` — `MMTokens` (1:1 port of `shared.jsx` design tokens),
    `MMTypography`
  - `Components/` — `StatusDot`, `ProgressBarView`, `ResultGlyph`,
    `RunnerBrandGlyph`, `RunnerMenuBarGlyph`, `MMSection`
  - `Icons/` — SF Symbols mapping for the `MMIcon` set
  - `Storage/` — `SnapshotStore` (App Group `UserDefaults`) + mock data

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

Right now both data sources are mocks:

- `MacMonitor/Services/GitHubClient.swift` — `MockGitHubClient` returns the
  same shape the JSX prototype used. Swap for `GitHubClient` and implement
  the REST calls when ready.
- `MacMonitor/Services/AgentClient.swift` — `MockAgentClient`. Real
  implementation talks to `http://<device.host>:8080/health` on each Mac mini.

The agent itself (the launchd daemon that runs on each Mac mini and exposes
the HTTP endpoint) is a separate project — Phase 1 of the original plan.

### GitHub PAT

When you fill in the real `GitHubClient`, store the personal access token in
Keychain under service `MacMonitor.GitHubToken`. The placeholder reads
`GITHUB_TOKEN` from the environment so you can experiment without Keychain.

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
