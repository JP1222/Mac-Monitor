# Development notes

## Why XcodeGen?

A two-target macOS project (menu bar app + WidgetKit extension) generates a
`.pbxproj` of ~2,000 lines with file UUIDs, build-phase ordering, embed-app-
extension settings, and entitlement file references. Hand-editing that file
is brittle and merge conflicts are awful.

XcodeGen converts a 60-line YAML spec into the project file deterministically.
Source of truth lives in `project.yml`; `.xcodeproj` is gitignored.

### Day-to-day

Pull, regenerate, open:

```sh
git pull
xcodegen generate
open MacMonitor.xcodeproj
```

If you add a new file, XcodeGen picks it up on next `xcodegen generate`
because `sources:` includes whole directories. No manual project file edits.

## Design ↔ code parity

The JSX prototype is the design source. Keep these in sync:

| Design file                                | Swift counterpart                                |
|--------------------------------------------|--------------------------------------------------|
| `shared.jsx` → `MM_TOKENS`                 | `Shared/Tokens/MMTokens.swift`                   |
| `shared.jsx` → `MMStatusDot`               | `Shared/Components/StatusDot.swift`              |
| `shared.jsx` → `MMProgressBar`             | `Shared/Components/ProgressBarView.swift`        |
| `shared.jsx` → `MMResultGlyph`             | `Shared/Components/ResultGlyph.swift`            |
| `shared.jsx` → mock data arrays            | `Shared/Storage/DashboardSnapshot+Mock.swift`    |
| `menu-bar-app.jsx` → `MBAPopover`          | `MacMonitor/Views/PopoverView.swift`             |
| `menu-bar-app.jsx` → `MBARunnerCard`       | `MacMonitor/Views/RunnerCardView.swift`          |
| `menu-bar-app.jsx` → `MBAQueueRow`         | `MacMonitor/Views/QueueRowView.swift`            |
| `menu-bar-app.jsx` → `MBARecentRow`        | `MacMonitor/Views/RecentRunRowView.swift`        |
| `menu-bar-app.jsx` → `MBADiskMeter`        | `MacMonitor/Views/DiskMeterView.swift`           |
| `menu-bar-app.jsx` → `MBAAppGlyph`         | `Shared/Components/RunnerGlyph.swift`            |
| `desktop-widget.jsx` → `DWSmall`           | `MacMonitorWidgets/SmallWidgetView.swift`        |
| `desktop-widget.jsx` → `DWMedium`/`Mini`   | `MacMonitorWidgets/MediumWidgetView.swift`       |
| `desktop-widget.jsx` → `DWLarge`/`CountTile` | `MacMonitorWidgets/LargeWidgetView.swift`      |

When iterating on the design, do it in the JSX prototype first (it has fast
hot-reload via Babel-in-browser), then port the diff over.

## App Group: the one piece you have to get right

The widget can only read the snapshot if all three of these declare the same
group ID:

1. `MacMonitor.entitlements` → `com.apple.security.application-groups`
2. `MacMonitorWidgets.entitlements` → same
3. `SnapshotStore.appGroupID` → same string

If you change the group ID, change all three and re-`xcodegen generate`.
You'll know it's wrong because `SnapshotStore.containerURL` returns nil and
the widget will fall back to mock data forever.

## Refresh timing

| Component               | Refresh cadence           | Notes                                |
|-------------------------|---------------------------|--------------------------------------|
| `DashboardViewModel`    | every 15s + on-demand     | controlled by `refreshInterval` arg  |
| `RunnersTimelineProvider` | every 30s + push        | host app pings `WidgetCenter` on write |
| Menu bar icon           | bound to ViewModel.snapshot | repaints whenever VM publishes     |

15s/30s are starting points — once you're hitting real GitHub APIs, watch the
rate limit (5000 req/hr authenticated). With 1 repo × 4 endpoints × 4 req/min
you're at ~16 req/min = 960/hr, safely under limit.

## Troubleshooting: "the menu bar icon doesn't appear"

If you launched MacMonitor and can't find the hexagon icon in your menu bar,
**verify the app is alive before assuming the icon is broken**:

```sh
# 1. App actually running?
ps aux | grep "MacMonitor.app/Contents/MacOS" | grep -v grep

# 2. macOS sees it as a registered background-only app?
osascript -e 'tell application "System Events" to get name of every process whose background only is true' \
  | tr ',' '\n' | grep -i macmonitor
```

If MacMonitor appears in BOTH lists, the SwiftUI `MenuBarExtra` registration
succeeded — the icon is *somewhere* in your menu bar.

Most common reason you can't see it: a third-party menu bar manager is hiding
it. Scan for them:

```sh
ps aux | grep -iE "bartender|ice|dozer|barhider|vanilla|hidden" | grep -v grep
```

Bartender / Ice / Dozer / Hidden Bar default to **hiding new menu bar items**
until you explicitly promote them. Click the manager's chevron, find the
MacMonitor hexagon, and pin it to the always-visible section.

If none of the above apply, also rule out:

- **MacBook with notch + crowded menu bar**: macOS hides items that don't fit.
  Try fewer items via System Settings → Control Center.
- **`lsappinfo info -only StatusLabel <pid>` returns NULL** is NOT a bug —
  SwiftUI MenuBarExtra uses a private status item subsystem that `lsappinfo`
  doesn't enumerate. NULL there does not mean "not registered".

## Adding a new widget size

For `accessoryRectangular` (Lock Screen on iOS) or `systemExtraLarge` (iPad):

1. Add to `supportedFamilies([...])` in `RunnersWidget.body`.
2. Add a switch case in `RunnersWidgetView.body`.
3. Build the new view in `MacMonitorWidgets/<Family>WidgetView.swift`.

The TimelineProvider is family-agnostic — no changes needed there.
