# Mac Monitor — Design System (DESIGN.md)

> **Handoff spec: design → development.** `CLAUDE.md` governs *build/architecture rules*; this file governs *visual & UX decisions*. Every rule is grounded in Apple's macOS 26 (Tahoe) / Liquid Glass guidance (WWDC25 + HIG + framework docs). Confidence is tagged:
> **[verified]** = adversarially fact-checked against Apple **primary** sources (see §Sources).
> **[pattern]** = established Apple API / community-accepted pattern, lighter citation.
>
> Implementation (me, in dev sessions) follows this doc and cites it. Ambiguity → change the spec here first, then implement. Don't re-derive design ad hoc.

---

## 0. The one principle

**Native macOS = choose & follow system components, not draw them.** This app's "web-y / hand-written" feel comes from being a 1:1 pixel port of a JSX prototype (`MMTokens` mirrors `shared.jsx`). The cure is to express each surface with the native SwiftUI container Apple prescribes and let the system supply material, spacing, vibrancy, typography, and Liquid Glass. Design work here is *selection + conformance*, not pixel drawing.

---

## 1. Liquid Glass — the two-layer model  [verified]

Apple's governing rule: Liquid Glass is the **navigation/chrome layer that floats ABOVE an opaque content layer**. HIG Materials, verbatim: *"Don't use Liquid Glass in the content layer."* WWDC25-219: making a content table glass *"would make it compete with other elements and muddy the hierarchy."*

- **Glass ONLY on chrome:** window toolbar, `NavigationSplitView` sidebar, the menu-bar **popover shell**, and the popover **header / action buttons** (custom floating controls). Standard components adopt glass automatically; custom floating controls use `glassEffect`.
- **Never glass (all content):** KPI cards, Fleet tiles, Queue/Recent rows, Build-step list, the hero panel, the status bar.
- Use glass **sparingly** — over-applying to custom controls "provide[s] a subpar user experience" and degrades rendering perf. [verified]
- **Never stack glass on glass** — elements sitting on a glass surface use *fills / transparency / vibrancy*, not a second glass layer. [verified, WWDC25-219]
- Any **custom** glass must be wrapped in a **`GlassEffectContainer`** (recommended for perf; required for cross-element morph). [verified] — ✅ done in `PopoverHeader`.
- **Glass needs content behind it to read.** In a dark, content-sparse area (e.g. the menu-bar popover footer) a `.glass` button has nothing to refract and blends into the background, while `.glassProminent` reads as a loud color block. Use **`.buttonStyle(.bordered)`** there — a clearly-defined standard button, no accent fill. Reserve `.glass`/`.glassProminent` for controls floating over actual content. [pattern — learned in PR #7]

## 2. Background ownership  [verified]

Content background = **the system window background**. Remove custom fills/darkening — they "overlay or interfere with Liquid Glass" and the **automatic scroll edge effect** (the system's subtle blur/fade of content passing under the toolbar). [verified, WWDC25-323 / Adopting Liquid Glass / HIG Layout]

- ✅ Done: removed `MMTokens.glassStrong` from the Overview detail.
- **Rule:** never reintroduce a custom window/detail background. Let the scroll-edge effect (not a fill) make the content→toolbar transition.

## 3. Containers — what each surface should BE

| Surface | Native container | Confidence |
|---|---|---|
| Window root | `NavigationSplitView` (sidebar + detail) with a `List(selection:)` first column — auto-coordinates selection, sidebar auto-glasses | **[verified]** NavigationSplitView doc; WWDC25-323 |
| Sidebar | `List` `.listStyle(.sidebar)` + `Label` + `.badge` | **[verified]** ✅ done |
| KPI / stat "card" | **`GroupBox`** (label = metric name) — Apple's prescribed primitive to "visually distinguish a portion of UI with an optional title" | **[verified]** GroupBox doc; HIG Boxes |
| Titled panel (24h activity, Queue, Recent, Build steps) | **`GroupBox`** (label = section title); keep boxes small vs. container, **don't nest** (HIG warns nesting "feels busy") | **[verified]** HIG Boxes |
| Fleet status tiles (selectable grid) | Lightweight content card (system background + `ConcentricRectangle`), selection = **`.accentColor`** stroke/tint. Bordered content cards are acceptable on macOS for distinct groups; GroupBox isn't selection-friendly so a card is the right call here | **[pattern]** HIG Boxes |
| Row collections (Queue, Recent, Build steps) | Native **`List`** rows; custom row *content* is fine (image + labels + trailing value) | **[pattern]** HIG Lists & tables |
| Empty / idle states (empty queue, empty recent, **idle hero**) | **`ContentUnavailableView`** — the modern macOS empty state; fixes the "huge empty whitespace" idle hero | **[pattern]** macOS 14+; ✅ already used in `StepTimelinePanel` |

## 4. Typography  [verified]

- Use **system text styles** for hierarchy — `.largeTitle / .title / .title2 / .title3 / .headline / .subheadline / .body / .callout / .caption / .caption2`. Not hardcoded `MMFont` sizes. [verified, HIG Typography]
- macOS base body = **13 pt**, minimum **10 pt**. macOS has **no Dynamic Type**, so text styles are for *hierarchy & legibility* (don't claim DT support). [verified]
- Metrics / durations / counts → `.monospacedDigit()` so live numbers don't jitter. [pattern]
- `.monospaced` design only where the value *is* data (commit SHAs, runner IDs). Everything else = SF Pro (system default). Retire `MMFont.rounded`/`MMFont.mono` for UI chrome.

## 5. Color  [verified principle + pattern]

- Prefer **system semantic colors**: window/`controlBackgroundColor` for surfaces, `separatorColor` for hairlines, `.secondary`/`.tertiary` for de-emphasis, and **`.accentColor`** (not a custom blue) for selection & primary actions. HIG: "be judicious with color in controls and navigation … allow your content to … shine through." [verified principle]
- Keep the **brand status palette** (`mint / amber / tomato / blue / slate`) **only for semantic status** — runner state, success/fail, disk pressure. That's meaningful signal, not decoration.
- Retire custom *neutral* tokens (`MMTokens.glass*`, `ink*`) in favor of `.primary/.secondary/.tertiary` + system backgrounds. (`MMTokens` keeps only the status colors + `rgba/hex` helpers.)

## 6. Corners & spacing  [verified + pattern]

- Concentric corners → use the **`ConcentricRectangle`** shape (macOS 26.0+). **Do NOT** use `.rect(cornerRadius: .containerConcentric)` — that spelling **failed verification** (not a confirmed API). [verified caveat]
- Use default SwiftUI spacing / standard insets; stop hand-tuning CSS-ported pixel paddings. [pattern]

## 7. Data visualization  [pattern]

- **Swift Charts** for the 24h activity (already `BarMark`). On macOS, use the extra width for axis labels / annotations rather than a bare sparkline. [Charts doc]
- **`Gauge`** for bounded 0–1 metrics where a dial/bar beats a number — e.g. **cache %** and **disk pressure**. Linear styles (`AccessoryLinearGaugeStyle` / `LinearCapacityGaugeStyle`) fit macOS monitoring UIs. Optional, evaluate per metric. [Gauge doc]

## 8. Anti-patterns — banned (things this codebase did)

- ❌ Glass on content cards, or glass-on-glass.
- ❌ Custom window/detail background fill (`glassStrong`) under native chrome.
- ❌ Hand-drawn "card" = `Material` + top-lit gradient hairline + custom shadow → use **GroupBox** / system colors.
- ❌ Hardcoded `MMFont` point sizes for chrome → **system text styles**.
- ❌ Custom accent blue for selection → **`.accentColor`**.
- ❌ `.rect(cornerRadius: .containerConcentric)` (unverified) → **`ConcentricRectangle`**.
- ❌ `.glass` / `.glassProminent` buttons in a dark, content-sparse area (they blend in / read too loud) → `.bordered`.
- ❌ Pixel-porting the JSX prototype as the source of truth.

## 9. Migration map (current code → target)

| File | Now | Target |
|---|---|---|
| `OverviewSupport.swift` `contentCard` | system bg + separator (good interim) | Split: **GroupBox** for titled cards; keep `contentCard` only for selectable Fleet tiles, add `ConcentricRectangle` |
| `KpiStrip.swift` | `contentCard` + system text ✅ | Wrap each metric in **`GroupBox`** (label = metric name) |
| `FleetStrip.swift` | system text + native progress ✅ | Keep as selectable cards; `.accentColor` selection ✅; `ConcentricRectangle` corners |
| `OverviewRails.swift` (Queue/Recent) | custom `RailCard` + custom rows | **`GroupBox`** titled + native **`List`** rows; **`ContentUnavailableView`** when empty |
| `StepTimelinePanel.swift` | custom rows + `ScrollView` | native **`List`** rows; keep `ContentUnavailableView` ✅; system text |
| `LiveBuildHero.swift` | heavy custom, `MMFont`, custom progress/phase bars | system text styles; native `ProgressView`; **idle state → `ContentUnavailableView`** (kills the empty whitespace) |
| `OverviewStatusBar.swift` | `.bar` material + `MMFont.mono` | keep `.bar`; swap `MMFont` → system `.caption`/monospaced |
| `OverviewWindow.swift` | `glassStrong` removed ✅ | never reintroduce a content background |
| `MMTokens.swift` | full custom palette | keep status colors + helpers; retire neutral/glass/ink tokens in favor of system semantic colors |

## Sources (Apple primary unless noted)

**Liquid Glass & layering** — [Liquid Glass overview](https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass) · [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) · [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views) · [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials) · [HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout) · [WWDC25-219 Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) · [WWDC25-323 Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
**Containers** — [GroupBox](https://developer.apple.com/documentation/swiftui/groupbox) · [HIG Boxes](https://developer.apple.com/design/human-interface-guidelines/boxes) · [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview) · [HIG Lists & tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)
**Typography & geometry** — [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography) · [ConcentricRectangle](https://developer.apple.com/documentation/swiftui/concentricrectangle)
**Data viz** — [HIG Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data) · [Swift Charts](https://developer.apple.com/documentation/Charts) · [Gauge](https://developer.apple.com/documentation/swiftui/gauge)
**Empty states / chrome** — [ContentUnavailableView](https://developer.apple.com/documentation/swiftui/contentunavailableview) · [HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)

_Research method: 6-angle fan-out, 26 sources fetched, 124 claims extracted, 25 adversarially verified (23 confirmed / 2 refuted). Refuted: the `.containerConcentric` corner API spelling, and a "glass can't sample glass" phrasing — neither is spec'd here. Current as of June 2026 (macOS 26 Tahoe)._
