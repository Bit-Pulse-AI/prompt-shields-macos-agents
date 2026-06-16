# PS-13 — Monitored Apps config

**Status:** Shipped (baseline). URL-level gating and per-app custom selectors are deferred.

## What landed

- Bundled allowlist at [`Resources/MonitoredApps.plist`](../../PromptShields.MacOS.Widget/Resources/MonitoredApps.plist) listing ChatGPT, Claude, Notion AI, Microsoft Copilot, Google Gemini, and Perplexity. Each entry carries `bundleIds` (native app matches) and `webHosts` (browser-tab host matches).
- [`MonitoredAppsRegistry`](../../PromptShields.MacOS.Widget/Managers/Accessibility/MonitoredAppsRegistry.swift) reads the plist at launch, exposes query helpers, and persists per-user disable state in `UserDefaults` under `ai.bit-pulse.promptshields.disabledMonitoredApps`.
- Settings → Monitored Apps section renders the list with per-app toggles (opt-out default).
- `AccessibilityManagerImpl.updateElementInfo` short-circuits when the frontmost app's bundleId matches a user-disabled record.

## What's deferred (and why)

### URL-level gating

Today, disabling "ChatGPT" only blocks the native Electron app (`com.openai.chat`). If the user is on chat.openai.com in Chrome, monitoring still happens because we never see the URL — `ElementInfo` carries `applicationBundleId` and text only, not the focused web URL.

**To close the gap:**

1. Extend `TextFieldDetector` to read `AXURL` / `AXDocumentURL` from the focused element's nearest `AXWebArea` ancestor.
2. Add `focusedURL: String?` to `ElementInfo`.
3. In `updateElementInfo`, additionally short-circuit if `MonitoredAppsRegistry.shared.enabledWebApp(urlString:)` returns nil for browser apps (i.e. "only monitor known AI URLs, not every browser tab").

This is a ~1-day change. It also aligns the code with the permission-trust copy we ship to users: *"We never read … any app not on your approved AI tool list."*

### App-specific AX selectors

The PRD AC mentions "app-specific accessibility selectors" — implying that each app might need different role/attribute paths to locate its composer. Today the code uses one uniform algorithm for all browsers and all native apps. If PS-11 uncovers that (say) Claude needs a different child-walk than ChatGPT, those per-app overrides would live in `MonitoredApps.plist` as a new `detection` dict per entry, and the detector would branch on it.

Out of scope until PS-11 reproduction tells us whether we actually need it.

### Adding new apps without a code release

The plist is bundled in the `.app`, so shipping a new entry currently does require a rebuild. The "edit config without a release" story from the PRD AC is best implemented by having the backend ship a JSON catalogue the client fetches at launch and caches. Not a blocker for MVP — plist edits + app release is fine for now.
