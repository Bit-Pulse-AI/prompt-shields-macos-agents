#!/usr/bin/env bash
# atlas-encoder-tests.sh — compiles the pure atlas-telemetry layer with a
# standalone assert harness and runs it. This is the CLI test path for
# AtlasPromptEventEncoder because the Xcode project's XCTest target is not
# runnable headless (no Test action in any scheme; stale TEST_HOST).
# The harness compile also enforces that the encoder stays Foundation-only.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)/atlas-encoder-tests"
swiftc -o "$OUT" \
  PromptShields.MacOS.Widget/Managers/Policy/PolicyTypes.swift \
  PromptShields.MacOS.Widget/Managers/Telemetry/TelemetryTypes.swift \
  PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventTypes.swift \
  PromptShields.MacOS.Widget/Managers/Telemetry/AtlasPromptEventEncoder.swift \
  Scripts/atlas-encoder-tests/main.swift
"$OUT"
