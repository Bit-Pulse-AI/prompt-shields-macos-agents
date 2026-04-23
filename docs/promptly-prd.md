# Promptly — AI Adoption Assistant PRD

**Version:** 1.0
**Date:** 2026-04-23
**Project:** Promptly (AI adoption assistant; rebrand of the Prompt Shields macOS app surface)
**Assignee:** Jun Seki
**Predecessor:** [`prompt-shields-prd.md`](../spec.md) (Henrik Hesle user-testing feedback)

---

## 1. Positioning

Promptly is the **AI adoption assistant for employees** — an ambient in-flow overlay that helps employees use AI tools effectively (ChatGPT, Claude, Copilot, Gemini, and 30+ others). It teaches, suggests, and protects in the moment they're writing a prompt, not through a separate training portal they never open.

The buyer is the **CIO** (adoption + IT-ticket deflection); the champion internally is usually **L&D / IT Adoption**. Competitive category: Digital Adoption Platforms (WalkMe, Whatfix), made AI-native.

### Platform architecture

Promptly is one of two client surfaces on the Bit-Pulse platform:

| Surface | Repo | Persona | Purpose |
|---|---|---|---|
| **Promptly** (this repo) | `prompt-shields-macos-widget` | Employee | Overlay + tutorials + templates + PII detection |
| **AI-SPM Dashboard** | `Bit-Pulse-AI/ai-spm-dashboard` | CIO / security | Analytics, adoption KPIs, policy management, ticket-deflection reporting |

Same backend, same auth, different clients. Promptly is macOS-native (this repo) plus the Chrome extension (`prompt-shields-chrome-extension-main`). Windows follows later from a separate repo.

### What's already shipped (slices B/C/D/E, current branch)

- Feb 2025 UX redesign applied (status card, Activate button, amber permission banner, expandable suggestion types, Activity Log, 4-step onboarding).
- Rebrand pass for user-facing strings (bundle rename still pending — PR-01 below).
- PS-13 monitored-apps config with per-app toggle in Settings.
- PS-11 investigation traces + **event-driven AXObserver detection** (Grammarly-style).
- Release scripts scaffolded (PS-01 DMG, PS-03 notarise).

Everything in this PRD builds on top of that.

---

## 2. Capabilities (WalkMe-style)

Anchored to the 7 capabilities WalkMe ships for AI assistance. Each is a Promptly epic.

| # | Capability | Promptly mapping | Status |
|---|---|---|---|
| 1 | Writing assistance | Prompt coaching + rewrite (existing `Suggestion` pipeline, expanded) | 🟡 Partial (PS-11 in flight) |
| 2 | Reading assistance | Highlight-to-action on any text (summarise / translate / reformat) | ❌ New |
| 3 | Input validation | Real-time PII + policy validation in AI input fields | 🟡 Partial (existing detector) |
| 4 | Next best actions | Contextual action chips based on what's on screen | ❌ New |
| 5 | Conversational chat | In-overlay chat grounded in org knowledge (v2) | ⏸ Deferred |
| 6 | Automations | Conversational workflows (HR, CRM, IT requests) | ⏸ Deferred (v2) |
| 7 | Memory | Learns user preferences to sharpen suggestions | ⏸ Deferred (v2) |

Plus two WalkMe-style foundations:

| # | Foundation | Promptly mapping | Status |
|---|---|---|---|
| F1 | Pre-defined solutions | **Tutorials + prompt templates catalog** | ❌ New (lead feature) |
| F2 | Design & control + analytics | **AI-SPM dashboard** (separate repo) | 🟡 In progress elsewhere |

---

## 3. Epics & tickets

### E1 — Promptly brand & surface (PR-01 – PR-03)

#### PR-01 · Bundle rename from PromptShields to Promptly

| Field | Value |
|---|---|
| **Priority** | High |
| **Estimate** | 2 days |
| **Labels** | Branding, Release |
| **Type** | Chore |

**Goal.** Rename the shipping artefact from "PromptShields" to "Promptly" while keeping the security/compliance branding ("Prompt Shields" as a platform capability name) intact on the AI-SPM side.

**Acceptance Criteria**
- [ ] `PRODUCT_BUNDLE_IDENTIFIER` → `ai.bit-pulse.promptly` (dev) / `ai.bit-pulse.promptly-dev`; old id kept as a deprecated secondary target for one release so existing installs can migrate.
- [ ] Xcode scheme + target display names → `Promptly-Dev` / `Promptly-Prod`.
- [ ] `Auth0.plist` callback URLs updated (needs matching Auth0 tenant config).
- [ ] App icon (`Assets.xcassets/AppIcon`) replaced with Promptly-branded icon at all sizes.
- [ ] `.dmg` volume name + file name → `Promptly-{version}-macos-{arch}.dmg` (already the case in `Scripts/build-dmg.sh`).
- [ ] DerivedData / migration: user-facing keychain entries keyed under old service id get read-on-first-launch, then migrated.

#### PR-02 · Branded Auth0 domain

| Field | Value |
|---|---|
| **Priority** | Medium |
| **Estimate** | 1 day (code) + Auth0 tenant config |
| **Labels** | Auth, Polish |
| **Type** | Improvement |

**Goal.** `auth.promptly.app` (or `.com` — DNS decision) instead of `ps-prod.eu.auth0.com`. Closes the remaining part of Henrik's PS-02 feedback.

**Acceptance Criteria**
- [ ] Custom domain configured in Auth0 tenant with TLS cert.
- [ ] `Auth0.plist` `Domain` key updated.
- [ ] Auth flow opens in system default browser (not embedded Chromium) — verify current behaviour, fix if still using a web view.
- [ ] Post-auth redirect lands on a branded `https://promptly.app/welcome` confirmation page.

#### PR-03 · Marketing & onboarding copy audit

| Field | Value |
|---|---|
| **Priority** | Low |
| **Estimate** | 1 day |
| **Labels** | Content |
| **Type** | Chore |

Brand-check every string. User-facing strings already rebranded in commit `3538926`; this ticket covers comments, log categories, analytics event names that still reference the old product.

---

### E2 — Tutorials (catalog-only MVP) (PR-04 – PR-07)

This is the **lead differentiating feature** per the WalkMe comparable. Ship the catalog first; authoring is v2.

#### PR-04 · Tutorial catalog format + bundled lessons

| Field | Value |
|---|---|
| **Priority** | Urgent |
| **Estimate** | 3 days |
| **Labels** | Tutorials, Catalog |
| **Type** | Feature |

**Goal.** A structured catalog of hands-on AI-adoption lessons, bundled in the app. v1 ships ~20 lessons spanning the top 5 AI tools × 4 common tasks (drafting, summarising, analysing data, code review).

**Acceptance Criteria**
- [ ] Catalog format: JSON (`Resources/Tutorials.json`) or per-lesson Markdown with YAML frontmatter. Fields: `id`, `title`, `description`, `estimatedMinutes`, `targetApp` (referencing `MonitoredApp.id`), `category` (drafting / summarise / analyse / code / security), `steps[]` with ordered actions.
- [ ] `TutorialCatalog` Swift loader equivalent to the MonitoredAppsRegistry we just built.
- [ ] At least 20 lessons authored and reviewed before engineering starts — non-engineering work, block on catalog delivery.
- [ ] Localisation: English only for v1; strings extracted so future translation doesn't require a rewrite.

#### PR-05 · Tutorial launcher in Control Panel

| Field | Value |
|---|---|
| **Priority** | High |
| **Estimate** | 3 days |
| **Labels** | Tutorials, UX |
| **Type** | Feature |

**Goal.** New "Learn" tab in the sidebar shows the tutorial catalog — filterable by category and target app, with progress indicators.

**Acceptance Criteria**
- [ ] New `DashboardContentState.learn` case + sidebar entry "Learn" with 🎓 icon.
- [ ] Catalog grid: each lesson card shows title, 1-line description, estimated minutes, target app logo, progress pill (Not started / In progress / Completed).
- [ ] Filter chips: All · Drafting · Summarise · Analyse · Code · Security. Secondary filter for target app.
- [ ] "Resume" button on any in-progress lesson.
- [ ] Progress persisted in `UserPreferences` + synced to backend via existing profile service.

#### PR-06 · In-context lesson overlay

| Field | Value |
|---|---|
| **Priority** | Urgent |
| **Estimate** | 5 days |
| **Labels** | Tutorials, Accessibility |
| **Type** | Feature |

**Goal.** When a lesson is launched, a narrow panel sits alongside the target AI tool (not on top of it) walking the user step-by-step through a real prompt. This is the WalkMe-style in-flow experience.

**Acceptance Criteria**
- [ ] Panel: 320pt wide, pinned to the right edge of the screen the AI tool is in. Uses the existing overlay window infrastructure.
- [ ] Step renderer: title, body (Markdown), "Try this" callout with a copyable example, optional screenshot/gif.
- [ ] Advance on detection: when the user completes the step's goal (e.g. types the example prompt) we advance automatically — detection uses the same `AccessibilityManager.elementInfo` stream we already publish.
- [ ] Step timer: if a step takes more than 3× estimated time, offer a "Skip" hint.
- [ ] Dismiss with Cmd+⌥+Escape; resumes from last step next time.

#### PR-07 · Tutorial analytics events

| Field | Value |
|---|---|
| **Priority** | High |
| **Estimate** | 2 days |
| **Labels** | Tutorials, Analytics |
| **Type** | Feature |

**Goal.** Emit events to the existing analytics bus (Firebase / PostHog / GA) so the AI-SPM dashboard can report completion rates and identify stuck lessons.

**Acceptance Criteria**
- [ ] Events: `tutorial_started`, `tutorial_step_completed`, `tutorial_completed`, `tutorial_abandoned` with `lesson_id`, `step_index`, `duration_s`, `target_app`.
- [ ] Events published to backend `/analytics/tutorials` endpoint so AI-SPM can aggregate per-org.

---

### E3 — Prompt templates (PR-08 – PR-10)

Current "suggestion types" ship a per-type prompt template. This epic promotes templates to a first-class user-facing feature.

#### PR-08 · Template catalog with slot-filling

| Field | Value |
|---|---|
| **Priority** | High |
| **Estimate** | 4 days |
| **Labels** | Templates, Catalog |
| **Type** | Feature |

**Goal.** Curated template library with named slots the user fills in (`[customer name]`, `[document]`). Templates are authored and bundled; per-user custom templates are v2.

**Acceptance Criteria**
- [ ] Template schema: `id`, `name`, `category`, `body` with `{{slot_name}}` markers, `slots[]` with `label`, `placeholder`, `required`, `validationRegex?`.
- [ ] ~30 templates authored for drafting, analysis, summarisation, code review.
- [ ] `TemplateCatalog` loader + integration with existing `SuggestionTypeCatalog` (same pattern).

#### PR-09 · Template picker overlay

| Field | Value |
|---|---|
| **Priority** | High |
| **Estimate** | 3 days |
| **Labels** | Templates, UX |
| **Type** | Feature |

**Goal.** Keyboard-invokable picker that inserts a template into the focused AI tool input field. Reuses the text-injection service we already have.

**Acceptance Criteria**
- [ ] Global shortcut `Cmd+Shift+.` opens picker pinned near focused field.
- [ ] Fuzzy search over template titles + categories.
- [ ] Filling modal: after selection, panel prompts for each `slot`; "Insert" writes the filled body into the focused field via `TextInjectionService`.
- [ ] Recent + favourite templates pinned at top.

#### PR-10 · Templates Settings section

| Field | Value |
|---|---|
| **Priority** | Medium |
| **Estimate** | 2 days |
| **Labels** | Templates, Settings |
| **Type** | Feature |

**Goal.** Settings → Templates lists bundled catalog; toggle which categories are visible in the picker. (Custom-authored templates = v2.)

---

### E4 — Jira ticket-deflection integration (PR-11 – PR-13)

This is the **proof-of-value metric** for the CIO. Without it, the adoption pitch has no hard number.

#### PR-11 · "Could-have-been-a-ticket" event model

| Field | Value |
|---|---|
| **Priority** | High |
| **Estimate** | 3 days |
| **Labels** | Jira, Analytics |
| **Type** | Feature |

**Goal.** Every time a tutorial completes, a template is used, or a suggestion is accepted that resolves an observable user frustration, emit a structured `ticket_deflected` event to the backend. Categorisation is coarse (Password reset / How do I / Tool access / AI help) — matches typical Jira service-desk taxonomies.

**Acceptance Criteria**
- [ ] Event schema: `event_id`, `category`, `target_app`, `trigger` (tutorial_completed | template_used | suggestion_accepted), `timestamp`, `user_id` (hashed), `team_id`.
- [ ] Published to `/analytics/deflection` alongside tutorial events.
- [ ] In-app surface: Activity Log badge "Deflected" on events that map to this.

#### PR-12 · Jira service-desk webhook (backend-side, not this repo)

| Field | Value |
|---|---|
| **Priority** | Medium |
| **Estimate** | 5 days (backend) |
| **Labels** | Jira, Backend |
| **Type** | Feature |

**Goal.** Backend subscribes to the customer's Jira webhook stream. Tickets tagged with deflection-relevant labels (IT requests AI help, password-reset, tool-access) are joined against our deflected-event stream to compute a "tickets avoided" metric for the AI-SPM dashboard.

Lives in the backend / AI-SPM repos; this ticket is a placeholder on this repo's roadmap for visibility.

**Acceptance Criteria**
- [ ] Customer self-service Jira OAuth flow in AI-SPM admin.
- [ ] Webhook receiver persists per-tenant ticket stream.
- [ ] Correlation job: deflected-events within N hours of a Jira ticket creation → flagged as potentially-avoided.
- [ ] AI-SPM tile: "Tickets avoided this month: X" with confidence band.

#### PR-13 · Admin-visible mapping UI

| Field | Value |
|---|---|
| **Priority** | Low |
| **Estimate** | 2 days |
| **Labels** | Jira, Admin |
| **Type** | Feature |

Lives in the AI-SPM dashboard repo — mentioned here for epic completeness.

---

### E5 — Expanded platform coverage (PR-14 – PR-16)

#### PR-14 · Grow MonitoredApps catalog to 30+

| Field | Value |
|---|---|
| **Priority** | High |
| **Estimate** | 2 days (catalog) + ongoing |
| **Labels** | Platform, Catalog |
| **Type** | Chore |

**Goal.** Expand `Resources/MonitoredApps.plist` from 6 entries to 30+ per the Promptly pitch. Priority list: ChatGPT, Claude, Gemini, Copilot, Notion AI, Perplexity (shipping), Cursor, Writer, Jasper, Mistral Le Chat, Meta AI, DeepSeek, GitHub Copilot Chat, ChatGPT Teams, Claude Projects, Gemini Workspace, Microsoft 365 Copilot, Slack AI, Zoom AI, Glean, Harvey, ServiceNow Now Assist, Salesforce Einstein, Zendesk AI, HubSpot Breeze, Intercom Fin, Grammarly, Otter.ai, Fathom.

**Acceptance Criteria**
- [ ] Each entry verified: bundleId (if native), webHosts (if web), category.
- [ ] Detection smoke-tested in each with the `DetectionTrace` from slice D.

#### PR-15 · URL-level app gating

| Field | Value |
|---|---|
| **Priority** | Medium |
| **Estimate** | 2 days |
| **Labels** | Platform, Security |
| **Type** | Improvement |

**Goal.** Close the gap in [`docs/investigations/ps-13-monitored-apps.md`](./investigations/ps-13-monitored-apps.md): disabling "ChatGPT" in Settings should block monitoring on `chat.openai.com` in a browser, not just the native app.

**Acceptance Criteria**
- [ ] Extend `TextFieldDetector` to read `AXURL` / `AXDocumentURL` from the nearest `AXWebArea`.
- [ ] Add `focusedURL: String?` to `ElementInfo`.
- [ ] `updateElementInfo` gates browser-tab monitoring on `MonitoredAppsRegistry.enabledWebApp(urlString:)`.

#### PR-16 · Remote catalog updates

| Field | Value |
|---|---|
| **Priority** | Low |
| **Estimate** | 3 days |
| **Labels** | Platform, Backend |
| **Type** | Feature |

**Goal.** Fetch `MonitoredApps` catalog from backend at launch, cache locally, fall back to bundled copy. So adding a 31st platform doesn't require an app release.

---

### E6 — PS-11 closeout & platform hardening (PR-17 – PR-19)

#### PR-17 · Confirm ChatGPT detection with AXObserver pipeline

| Field | Value |
|---|---|
| **Priority** | Urgent |
| **Estimate** | 2 days |
| **Labels** | Core, QA |
| **Type** | Bug / Verification |

**Goal.** Run the `DetectionTrace` (`defaults write … detectionTrace -bool YES`) through the test matrix in [`docs/investigations/ps-11-chatgpt-detection.md`](./investigations/ps-11-chatgpt-detection.md) and confirm the Grammarly-style observer + `AXStaticText` fallback resolves the bug.

**Acceptance Criteria**
- [ ] Reproduce Henrik's test — type PII into ChatGPT web and desktop. Trace shows non-zero text length. Detection event fires.
- [ ] Same verification for Claude.ai, Notion AI, Copilot.
- [ ] Add an XCTest that exercises `AXUIElementSafeWrapper.collectStaticText` with a synthetic AX tree (at minimum a unit test; E2E blocked without CI infra).
- [ ] Measure keystroke → detection latency. Target: P95 under 200 ms.

#### PR-18 · Clean-prompt Activity Log entries

| Field | Value |
|---|---|
| **Priority** | Medium |
| **Estimate** | 3 days |
| **Labels** | Activity Log, Backend |
| **Type** | Feature |

**Goal.** Close the PS-12 gap — Activity Log currently only gets entries when a suggestion is produced. Emit a "Clean prompt — no sensitive data detected" row for every scan.

**Acceptance Criteria**
- [ ] Scan pipeline emits a `Suggestion` record (or lightweight `ScanEvent`) with `suggestionType = "clean"` when no risk is found.
- [ ] Activity Log row type `ActivityBadge.cleanPrompt` (green, subtle).
- [ ] Rate-limit: dedupe identical clean scans within 60 s to avoid spam.

#### PR-19 · Send-event detection

| Field | Value |
|---|---|
| **Priority** | Medium |
| **Estimate** | 4 days |
| **Labels** | Core, UX |
| **Type** | Feature |

**Goal.** Detection currently fires on every debounced keystroke. Some customers want detection specifically at **send** (Enter / Cmd+Enter / "Send" button click) so the overlay doesn't flash during typing. Add a Settings toggle "Check only when sending".

**Acceptance Criteria**
- [ ] Add a global CGEvent tap scoped to the focused AI-tool app (requires hardened-runtime entitlement).
- [ ] When toggle is on, detection runs only on Enter / Cmd+Enter in the focused editable element.
- [ ] Falls back gracefully when the entitlement isn't granted (hide the toggle).

---

## 4. Sprint plan

| Sprint | Dates | Focus | Tickets |
|---|---|---|---|
| Sprint 1 | 2026-04-28 → 2026-05-09 | Brand + core fix | PR-01, PR-02, PR-17 |
| Sprint 2 | 2026-05-12 → 2026-05-23 | Templates MVP | PR-08, PR-09, PR-10 |
| Sprint 3 | 2026-05-26 → 2026-06-06 | Tutorial catalog + launcher | PR-04, PR-05, PR-07 |
| Sprint 4 | 2026-06-09 → 2026-06-20 | Tutorial overlay + analytics | PR-06, PR-11 |
| Sprint 5 | 2026-06-23 → 2026-07-04 | Platform expansion + hardening | PR-14, PR-15, PR-18, PR-19 |
| Sprint 6 | 2026-07-07 → 2026-07-18 | Remote catalog + Jira backend | PR-16, PR-12 (backend), PR-13 (AI-SPM) |

**Target launch (Promptly public beta):** 2026-07-31, coinciding with Sprint 6 close + AI-SPM dashboard GA.

**~12 weeks, roughly 42 developer-days** for this repo alone (Jira backend + AI-SPM tiles are separate).

---

## 5. Dependencies

- **Content (not engineering):** 20 tutorial scripts + 30 prompt templates must be authored and reviewed before Sprint 2 (templates) / Sprint 3 (tutorials) kick off. Estimated 5–8 person-days of L&D / PM time.
- **Design assets:** Promptly app icon (.icns, all sizes), DMG background, branded Auth0 login page. Block on PR-01.
- **Auth0 plan:** Custom domain requires Essentials tier or above. Block on PR-02.
- **Backend work:** Tutorial analytics endpoint, deflection event endpoint, Jira webhook receiver. Owned by backend team; flagged here for visibility.
- **AI-SPM dashboard:** Deflection tile, tutorial completion tile. Owned by AI-SPM repo team.

---

## 6. Non-goals for v1

- **Conversational chat overlay** (WalkMe capability #4) — defer to v2 once tutorials + templates land.
- **Automations** (capability #6) — defer; requires workflow engine.
- **Memory / personalisation** (capability #7) — defer; requires user-vector store.
- **Custom template authoring** (user-created templates) — v2.
- **Admin curriculum assignment** — v2 once we know which tutorials customers actually run.
- **Windows native client** — separate repo, separate roadmap.

---

## 7. Open questions

1. **Auth0 domain**: `.app` vs `.com`? DNS/TLS decision blocks PR-02.
2. **In-flow overlay window ordering**: does the tutorial panel belong on a dedicated `.screenSaver`-level window (like the existing overlay/action windows) or a regular panel? Affects full-screen-app behaviour.
3. **Jira correlation window**: 2h? 24h? Too narrow misses legitimate deflection; too wide attributes noise. Needs customer-data calibration.
4. **Deflection taxonomy**: 4 categories enough, or do we need 8–10? Check with first-wave CIOs pre-launch.
