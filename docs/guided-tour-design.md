# Guided tour — design

**Status:** draft for review · **Owner:** Jun Seki · **Date:** 2026-05-06
**Companion docs:** [`promptly-prd.md`](./promptly-prd.md), [`policy-integration.md`](./policy-integration.md)

---

## 1. Goals + non-goals

### What we're building

After the 4-step onboarding sheet dismisses, brand-new Promptly users land on the dashboard. Right now they see the Control Panel cold — a status card, a button, three stats tiles, a suggestion overview — with no in-context teaching. This doc proposes an **in-app guided tour**: a sequence of coachmarks that highlights the key UI elements and explains what they do.

### Goals

1. **Reduce time-to-first-success.** A user who's never used Promptly should be able to (a) turn it on, (b) understand what an "Activity Log" is, and (c) find the floating chat — within ~60 seconds of landing on the dashboard.
2. **Trigger discovery without blocking.** Coachmarks must be dismissable per-step and globally — never a modal that traps the user.
3. **Re-runnable.** "Show tour" lives in the Help menu so users can replay a tour later and admins can demo without uninstalling.
4. **Architecturally aligned with the eventual tutorial overlay** (PR-04/05/06 in the PRD) so we're not building two parallel systems. This doc proposes one tour engine that can later host both *Promptly UI* tours and *AI-tool tutorials*.

### Non-goals

- **Inside-the-host-app coachmarks** (e.g. pointing at ChatGPT's Send button on chat.openai.com). That's the `tutorialOverlay` in the Promptly PRD; it shares this engine but lives in a separate window and is dashboard-driven. **In scope for v2 only.**
- **Branching tours.** Linear sequences only. No "if user X did Y, skip to step 5."
- **Built-in authoring UI.** Tour content is shipped as bundled JSON for v1; admin authoring lands later.
- **Replacing onboarding.** The 4-step sheet stays — onboarding teaches the *product proposition* before the user has any context. Tours teach the *UI* after they're in.

---

## 2. The two tour layers (now + later)

| Layer | Lives in | Anchored to | Authored by | Status |
|---|---|---|---|---|
| **Meta-tour** | Promptly's own dashboard window | Promptly's own SwiftUI views | Promptly engineering | **v1 (this doc)** |
| **Tutorial overlay** | Floating panel pinned next to the host AI app | Glyph coordinates inside the host app's text field, via AX | Customer L&D + Promptly catalog team | v2 — see PR-04/05/06 in promptly-prd.md |

The same `TourCoordinator` runs both. They differ in:
- **Anchor resolution**: meta-tours look up SwiftUI views by id; tutorial overlays use AX coordinates from the focused element.
- **Visual treatment**: meta-tours render coachmarks inside the dashboard window; tutorial overlays render in a `.statusBar`-level panel beside the host app.
- **Storage**: meta-tour catalog is bundled JSON; tutorial catalog is fetched from the dashboard's `/api/tutorials` endpoint (future).

**This doc only specifies the meta-tour layer.** Section 7 lists the abstractions we keep generic to land tutorial overlays on the same engine later.

---

## 3. Information architecture

### Tours we'll ship in v1

| Tour ID | When it fires | Steps | Approx duration |
|---|---|---|---|
| `dashboard-intro` | Auto on first dashboard mount after onboarding completes | 6 | ~45 s |
| `chat-intro` | Auto the first time the floating chat panel expands | 4 | ~20 s |
| `settings-intro` | Manually from Help → "Show tour" | 5 | ~30 s |
| `activity-log-intro` | Auto the first time `.suggestions` content state activates | 3 | ~15 s |

Each tour ID maps 1:1 to a `TourCompletion` flag in UserDefaults. Completion = user clicks "Got it" on the last step OR explicitly dismisses.

### `dashboard-intro` step-by-step

1. **Header — "Promptly active"** → "This pill tells you whether Promptly is monitoring your prompts. Toggle it from the status card below."
2. **Status card "Activate Shield" button** → "One click turns Promptly on. We'll only read text in the AI tools you've allowed."
3. **Quick stats row** → "Counts reset every day. Risks caught means PII or policy violations Promptly stopped from leaving your Mac."
4. **Suggestion Types overview** → "These are the rewrites Promptly can apply. Click *Manage in Settings* to enable or customise them."
5. **Sidebar — Activity Log** → "Every prompt Promptly inspects shows up here so you can audit what was caught."
6. **Floating chat button (off-window)** → "Have a question? Cmd+Shift+P opens the chat from anywhere — even when the dashboard is closed."

Step 6 is unusual because the anchor is in a *different window*. Section 6 explains how the engine handles that.

### `chat-intro` step-by-step

1. **Instruction chip bar** → "Toggle these to apply tone, format, or language to every reply."
2. **Composer + Cmd↵ shortcut** → "Type a question. Cmd↵ sends. Active instructions are prepended automatically."
3. **Conversation area** → "Replies appear here. Use the trash icon to clear the conversation."
4. **Settings handoff** → "Build your own instructions in Settings → Custom Instructions."

### `settings-intro` and `activity-log-intro`

Specced lighter — content authored alongside implementation.

---

## 4. Component architecture

### High-level

```
┌─────────────────────────────────────────────────────────────────┐
│ TourCoordinator (singleton, MainActor)                          │
│ · activeTour: Tour?                                             │
│ · currentStepIndex: Int                                         │
│ · start(_ tourId:) / next() / skip() / complete()               │
│ · publishes @Published activeStep for SwiftUI to observe        │
└─────────────────────────────────────────────────────────────────┘
               │                            │
               │ reads                      │ writes
               ▼                            ▼
┌──────────────────────────┐   ┌────────────────────────────────────┐
│ TourCatalog (static)     │   │ TourCompletion (UserDefaults)      │
│ · loads Resources/       │   │ · key prefix:                      │
│   Tours.json             │   │   ai.bit-pulse.promptly.tour.<id>  │
│ · returns Tour by id     │   │ · markCompleted / hasCompleted     │
└──────────────────────────┘   └────────────────────────────────────┘
               │
               │ rendered by
               ▼
┌─────────────────────────────────────────────────────────────────┐
│ TourOverlay  ← attached as .modifier on each window's root      │
│   ├── TourBackdrop        (semi-transparent, with cutout)       │
│   ├── TourSpotlight       (clear circle/rect around anchor)     │
│   └── TourCoachmark       (popover with title/body/buttons)     │
└─────────────────────────────────────────────────────────────────┘
                         │
                         │ asks for anchor frame
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ TourAnchor (preference-key based)                               │
│ · .tourAnchor("activate-shield")  modifier                      │
│ · publishes the anchor's frame in window-space via              │
│   AnchorPreference                                              │
│ · TourOverlay reads the dictionary [String: CGRect] and         │
│   positions the spotlight + coachmark                           │
└─────────────────────────────────────────────────────────────────┘
```

### Why preference keys (not GeometryReader hacks)

SwiftUI's `AnchorPreference` is the idiomatic way to bubble a child's frame up to a parent without explicit binding. The view that owns the anchor declares:

```swift
.tourAnchor("activate-shield")
```

…which expands to an `.anchorPreference(key:value:transform:)` writing into a `[String: Anchor<CGRect>]` dictionary. The window's root reads the merged dictionary, resolves the anchor for the current step, and positions the coachmark over it. No `GeometryReader` chains, no view-tree pollution.

### Off-window anchors (e.g. floating chat button)

The floating chat lives in its own `.statusBar`-level window. The `dashboard-intro` step 6 anchor is in a *different window* than the coordinator's host. Two options:

**A. Cross-window coachmark** — the coordinator broadcasts `Notification.Name.tourActiveStep` carrying step id + tour id. The chat window listens; when its anchored step is active, it renders its own `TourOverlay` modifier on top.

**B. Skip cross-window steps** — only step within the dashboard window; for off-window UI we use a "look at the bottom-right of your screen" coachmark anchored to the dashboard's bottom-right corner.

**Recommendation: A.** It's the same pattern we already use for `showOnboarding` and `devSkipLogin` notifications. A `TourCoordinator` posting to `NotificationCenter` with the active tour+step lets every window decide whether it owns an anchor for the current step.

---

## 5. Data model

```swift
// Resources/Tours.json (+ generated Swift loader)

struct Tour: Codable, Sendable {
    let id: String                    // "dashboard-intro"
    let title: String                 // shown only on the first step
    let trigger: TourTrigger          // when does this auto-fire?
    let steps: [TourStep]
}

enum TourTrigger: String, Codable {
    case manual                       // only via Help menu
    case firstDashboardMount
    case firstChatExpand
    case firstActivityLogVisit
}

struct TourStep: Codable, Sendable, Identifiable {
    let id: String                    // step-local, e.g. "activate-button"
    let anchorId: String              // matches a .tourAnchor(...) somewhere
    let placement: CoachmarkPlacement // .below | .above | .leading | .trailing | .auto
    let title: String
    let body: String
    let primaryLabel: String?         // default "Next →" — last step shows "Got it"
    let secondaryLabel: String?       // default "Skip tour"
    /// Optional spotlight padding (pts). Default 8.
    let spotlightPadding: Double?
    /// Allow click-through onto the underlying control even while the
    /// coachmark is up. Defaults to false (backdrop blocks taps).
    let interactionAllowed: Bool?
}

enum CoachmarkPlacement: String, Codable {
    case auto, above, below, leading, trailing
}
```

**Why a separate `anchorId`** rather than reusing `step.id`: the same step might attach to different physical anchors depending on platform / locale / A-B variant. Loose coupling lets us move the anchor without renaming the step.

### Storage keys

```
ai.bit-pulse.promptly.tour.<tourId>.completedAt    : ISO date string
ai.bit-pulse.promptly.tour.<tourId>.dismissedAt    : ISO date string  (manually skipped)
ai.bit-pulse.promptly.tour.disableAll              : Bool             (escape hatch for QA)
```

A tour fires when `trigger != .manual` AND neither `completedAt` nor `dismissedAt` is set AND `disableAll` is false. Manual triggers via Help menu always fire and don't check completion state.

---

## 6. UI specification

### Coachmark visual

- **Container**: `RoundedRectangle(cornerRadius: 12)` filled with `Color.psSurface`, 1 pt `Color.psBorder` stroke, 16 pt shadow (radius 16, y 8, opacity 0.15).
- **Width**: 280 pt (matches the chat panel chip column for consistency).
- **Padding**: 16 pt all sides.
- **Title**: 13 pt semibold, `Color.psText`.
- **Body**: 12 pt regular, `Color.psText2`, line height 1.45.
- **Footer row**:
    - Step counter top-left: "2 / 6" in 11 pt mono `Color.psText3`.
    - "Skip tour" link bottom-left, 11 pt regular `Color.psText3`, underline on hover.
    - "Next →" / "Got it" primary button bottom-right, 11 pt semibold, blue background, 8 pt corner radius, 6×12 pt padding.
- **Arrow**: 12 pt × 8 pt triangle in `Color.psSurface` with the same border, pointing at the spotlight. Side determined by `placement`.

### Spotlight backdrop

- Full-window overlay at `Color.black.opacity(0.42)`.
- Cutout: `RoundedRectangle(cornerRadius: 10)` matching the anchor frame inflated by `spotlightPadding` (default 8 pt).
- Cutout uses `.blendMode(.destinationOut)` over the backdrop in a `compositingGroup`.
- Anchor inset gets a 2 pt `Color.psBlue` ring at 0.6 opacity for definition (Grammarly does this).

### Animation

- **Enter**: backdrop fades in 180 ms; coachmark slides 8 pt from the spotlight side + fades in 220 ms easeOut.
- **Step transition**: spotlight rect tweens `interpolatingSpring(stiffness: 240, damping: 26)`; coachmark cross-fades.
- **Exit**: both fade out 160 ms, no slide.

### Dismissal affordances

- "Skip tour" button (always available)
- Esc key
- Click on the backdrop outside the spotlight (configurable per-step; on by default for v1 to match Grammarly)

---

## 7. Engine API

### Public surface (call sites)

```swift
// Anchor a view so the tour engine can find it.
SomeButton().tourAnchor("activate-shield")

// Trigger a tour from anywhere.
TourCoordinator.shared.start("dashboard-intro")

// Auto-trigger by hooking onAppear to a view that owns a trigger.
ControlPanelView()
    .tourAutoStart(if: .firstDashboardMount, "dashboard-intro")
```

### What the coordinator owns

- The active `Tour` + step index
- Resolving anchor frames from the merged `[String: Anchor<CGRect>]` dictionary
- Persistence (UserDefaults flags)
- Posting `Notification.Name.tourActiveStep` for off-window listeners
- Handling `Esc`, `Skip tour`, `Got it`

### What the views own

- `.tourAnchor(id)` — registers a frame
- `.tourOverlay()` — renders backdrop + coachmark when this window's root has the active step
- `.tourAutoStart(if:, id:)` — triggers on view appear if completion is unset

The engine never reaches into business logic. View modifiers + a singleton coordinator + bundled JSON. ~600 lines of Swift total for the engine.

---

## 8. Phasing

### Sprint A — Engine (~2 days)

- `Tour`, `TourStep`, `TourTrigger` types
- `TourCatalog` JSON loader from `Resources/Tours.json`
- `TourCoordinator` (MainActor singleton, @Published activeStep, persistence)
- `TourAnchor` PreferenceKey + view modifier
- `TourOverlay` modifier with backdrop + spotlight + coachmark
- `TourCoachmarkView` (the popover itself)
- `TourBackdrop` (the destinationOut cutout)
- Notification bridge for cross-window steps
- Tests: catalog loading, completion persistence, step navigation

### Sprint B — Content for v1 (~1 day)

- Author `Tours.json` for `dashboard-intro` (6 steps)
- Add `.tourAnchor` modifiers to: header pill, Activate button, QuickStats row, SuggestionOverview, sidebar Activity Log row, floating chat button
- Wire `.tourAutoStart` to `ControlPanelView`
- Help menu entries: "Show tour ▸ Dashboard intro / Chat / Settings / Activity Log"
- Manual QA pass

### Sprint C — Other tours (~1 day)

- `chat-intro` (4 steps)
- `activity-log-intro` (3 steps)
- `settings-intro` (5 steps)

### Sprint D — Stretch (~1 day)

- Esc / click-outside dismissal polish
- Reduced-motion path (skip animations when `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == true`)
- VoiceOver: announce step title + body, route Tab/Enter through the coachmark buttons

**Total: ~5 dev-days for the v1 meta-tour layer.**

The v2 tutorial overlay (PR-04/05/06 in the PRD) reuses Sprint A's engine + builds out the dashboard-fetched JSON catalog + the cross-app overlay window. Estimated ~8 additional days on top of this engine.

---

## 9. Telemetry

Tour usage is signal — it tells us which steps users skip, where they bail. New analytics events:

```swift
case tourStarted(id: String, trigger: String)
case tourStepShown(id: String, stepIndex: Int)
case tourStepDismissed(id: String, stepIndex: Int, reason: String)  // "skip", "esc", "click_outside"
case tourCompleted(id: String, durationSec: Double)
```

Plus the existing AI-SPM telemetry stream gets a daily rollup so the dashboard can show "tour completion %" per tenant — a real-world version of WalkMe's signature "engagement" metric.

---

## 10. Open questions

1. **Interaction during a step.** Should "Activate Shield" be clickable while step 2 of the tour is up? My instinct: yes, with a small "✓ Activated" confirmation appearing inline that auto-advances the tour. WalkMe / Userpilot both do this. Adds engine complexity (`interactionAllowed: true` per step + a way to listen for "user did the action"). Worth it for v1?

2. **First-launch timing.** The 4-step onboarding sheet auto-presents before the dashboard renders. Do we let `dashboard-intro` immediately follow when onboarding dismisses, or wait until the user has had a few seconds to look around? My recommendation: 1.2 s delay after dashboard appears, then start.

3. **Multi-tour orchestration.** If a user opens chat right after dashboard intro, do both tours fire back-to-back? Probably annoying. Suggest: only one tour active at a time, others queue and skip if their trigger window passes.

4. **Theming for tutorial overlay.** When we extend to v2 (tutorial overlay anchored to ChatGPT/Claude/etc.), the coachmark needs to work over white *and* dark host apps. Spec the colours now or reskin later? Suggest: dark-mode variant of `Color.psSurface` baked into the engine from day one.

5. **Cross-window step (#6) UX.** Does the spotlight disappear because the chat window is off-screen, or does the dashboard temporarily show an arrow pointing off the bottom-right edge? Suggest: dashboard shows a "look bottom-right" arrow + a 1-line copy block; the chat icon itself doesn't get spotlighted.

6. **Dashboard-driven tour authoring.** Once tutorial overlays land (v2), should admins author Promptly's own meta-tours from the same dashboard? Yes, but later — for v1 the bundled JSON is fine and we avoid a 3-tier approval workflow on copy changes.

---

Awaiting answers + a green light before I move to Sprint A.
