# PS-11 — ChatGPT detection not firing

**Status:** Open. Investigation notes + diagnostic scaffolding landed in this commit; actual fix requires reproduction with the new traces.

## What Henrik saw

Typed dummy PII into chat.openai.com (Chrome) and into the ChatGPT macOS app. Nothing was detected. No notification. No Activity Log entry.

## How the pipeline is supposed to work

The app polls every 500 ms via `AccessibilityManagerImpl.timerTick()` → `processAccessibility()`. One poll cycle:

1. `getRobustFocusedElement()` queries the frontmost app's `AXFocusedUIElement`.
2. For browsers, the pipeline looks for either:
   - the focused element directly, if it reports `isEditable`/`isTextInputElement`,
   - otherwise `findEditableElementInWebContent()` walks the `AXWebArea` tree looking for an editable descendant (max depth 25).
3. `TextFieldDetector.getAXElementOrSelectionInfo` pulls the text value out of the resolved element.
4. `updateElementInfo(info)` publishes the result on `@Published elementInfo`, which the overlay / suggestion pipeline consumes.

Relevant code: [`AccessibilityManager.swift:393`](../../PromptShields.MacOS.Widget/Managers/Accessibility/AccessibilityManager.swift), [`AXUIElementSafeWrapper.swift:305`](../../PromptShields.MacOS.Widget/Managers/Accessibility/AXUIElementSafeWrapper.swift), [`TextFieldDetector.swift`](../../PromptShields.MacOS.Widget/Managers/Accessibility/TextFieldDetector.swift).

## Candidate causes (ranked)

### 1. ChatGPT web uses a contenteditable div that doesn't expose `AXValue`

ChatGPT's composer is a `<div contenteditable>` inside a React tree. Chromium exposes this with role `AXTextArea` *only if* the `role="textbox"` ARIA attribute is set — otherwise it shows up as `AXGroup` with `AXEditable=true` and no `AXValue`. Our `isEditable()` does check `AXEditable`, so the element should be recognised, but `TextFieldDetector` reads text via `kAXValueAttribute` which returns empty for a `role=textbox` contenteditable. The text content lives in descendant `AXStaticText` children or in the AX tree's selection range.

**What to check first** — after enabling the trace (below), look for `event=text_field_info bundle=com.google.Chrome role=AXTextArea|AXGroup editable=true len=0`. If `len=0` while you have typed into the prompt, the text extractor isn't reaching the children.

**Fix direction** — in `TextExtractor`, if `kAXValueAttribute` is empty on an editable web element, concatenate text from `AXStaticText` descendants and/or use `AXSelectedTextRangeAttribute` + `AXStringForRangeAttribute` to pull the content.

### 2. `AXFocusedUIElement` returns the outer React container, not the composer

If Chrome reports focus on a wrapper element that isn't editable itself, our code's `if isEditable(focused) || isTextInputElement(focused)` branch is skipped, and `findEditableElementInWebContent(focusedElement)` searches the subtree. If the editable composer is a *sibling* in the AX tree rather than a descendant of what Chrome thinks is focused, we'll never find it.

**What to check first** — `event=text_field_info ... role=AXGroup editable=false`. We'd then fall through to `findEditableElementInWebContent` which may or may not find it.

**Fix direction** — when the focused element isn't editable and the subtree search returns nil, fall back to searching up to the `AXWebArea` and scanning its full subtree (which `getRobustFocusedElement` already does via `getFocusedElementInWebContent`, but only if the focused element itself is web content — tighten the branch so we always find the web area).

### 3. ChatGPT macOS app is Electron — has its own AX quirks

The native app (bundleId `com.openai.chat`) is an Electron wrapper. Electron's AX tree is closer to Chrome than to native AppKit. Same risks as #1 and #2 apply.

**What to check** — trace should show `bundle=com.openai.chat` and a role. Probably `AXTextArea` or `AXGroup`.

### 4. Text extraction works but no downstream analysis fires

Possible but less likely given the code. `updateElementInfo` only filters on `isSelf`, invalid frame, and (now) user-disabled apps. If text reaches it, the overlay should appear.

**What to check** — trace shows `event=text_field_info ... len>0` (good) but no overlay appears. That points to the consumer of `elementInfo`, not the producer.

## Reproduction steps (for Henrik or QA)

### Enable the detection trace

```bash
defaults write ai.bit-pulse.PromptShields-MacOS-Widget-Dev \
    ai.bit-pulse.promptshields.detectionTrace -bool YES
```

(Replace bundle id with `-Prod` for release builds.)

### Stream logs

```bash
log stream --predicate 'subsystem CONTAINS "PromptShields" AND category == "Detection"' \
    --level debug --style compact
```

You'll see one line per poll cycle:

```
event=text_field_info bundle=com.google.Chrome role=AXTextArea editable=true len=42
event=no_focused_element bundle=com.openai.chat
event=gated bundle=ai.bit-pulse.PromptShields-MacOS-Widget note=isSelf
event=detection_error note=invalid_handle
```

### Test matrix

1. Focus chat.openai.com composer in Chrome → expect `len>0` once you start typing.
2. Focus the composer in the ChatGPT macOS app → expect `len>0`.
3. Focus Claude.ai composer in Chrome → expect `len>0`.
4. Focus a plain TextEdit document → expect `len>0` and `bundle=com.apple.TextEdit`.

If #4 works and #1 doesn't, the bug is in the web-content branch.
If #4 doesn't work either, something is wrong before the browser-specific paths.

## What this ticket did NOT fix

- The detection bug itself — blocked on reproduction. The trace scaffolding is the prerequisite to fixing it.
- The send-event semantics (PRD asks for detection on Enter/Send button). Current implementation detects-on-focus-with-text; the "send" moment is not a distinct event. Plumbing a real send hook would need `AXNotification` observers (`kAXTitleChangedNotification`, key-event monitoring) — separate work.

## Next steps

1. Run the trace against Henrik's reproduction steps on a real Mac.
2. Classify which candidate cause (#1 / #2 / #3) matches what the trace shows.
3. Implement the corresponding fix in `TextExtractor` or `findEditableElementInWebContent`.
4. Add an E2E test per the PRD AC: "type a known PII pattern into a mock text field and assert a detection event fires."
