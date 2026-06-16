#!/usr/bin/env bash
# detection-test.sh — one-shot runner for the PS-11 trace test matrix.
#
# What it does:
#   1. Enables DetectionTrace via `defaults write`.
#   2. Opens each app in the test matrix (ChatGPT web, Claude, Notion,
#      TextEdit) so you can focus the composer and start typing.
#   3. Streams `log stream` with a PromptShields detection predicate until
#      you Ctrl+C.
#
# Prereqs:
#   - Run the Dev scheme from Xcode first (builds Promptly-Dev with the
#     ai.bit-pulse.PromptShields-MacOS-Widget-Dev bundle id).
#   - Grant Accessibility permission to that Dev build.
#   - Log in and turn on Promptly from the Control Panel.
#
# Usage:
#   ./Scripts/detection-test.sh
#
# Reference: docs/investigations/ps-11-chatgpt-detection.md

set -euo pipefail

BUNDLE_ID_DEV="ai.bit-pulse.PromptShields-MacOS-Widget-Dev"
BUNDLE_ID_PROD="ai.bit-pulse.PromptShields-MacOS-Widget"
TRACE_KEY="ai.bit-pulse.promptshields.detectionTrace"

echo "==> Enabling DetectionTrace for both Dev and Prod bundle ids"
defaults write "$BUNDLE_ID_DEV" "$TRACE_KEY" -bool YES
defaults write "$BUNDLE_ID_PROD" "$TRACE_KEY" -bool YES

echo "==> Opening test targets (switch between them to drive the matrix):"
# ChatGPT web
open "https://chat.openai.com"
sleep 0.5
# Claude.ai
open "https://claude.ai"
sleep 0.5
# Notion
open "https://www.notion.so"
sleep 0.5
# TextEdit as the native-AppKit control case
open -a TextEdit
sleep 0.5

cat <<'USAGE'

==> Streaming Detection log. In another window / tab:

  1. Focus the ChatGPT composer and type 10+ characters.
     Expected line: event=text_field_info bundle=com.google.Chrome role=AXTextArea editable=true len>0
  2. Repeat for Claude, Notion, and TextEdit.
  3. Disable the detectionTrace when finished:
        defaults delete ai.bit-pulse.PromptShields-MacOS-Widget-Dev ai.bit-pulse.promptshields.detectionTrace

Ctrl+C to stop streaming.

USAGE

exec log stream \
    --predicate 'subsystem CONTAINS "PromptShields" AND category == "Detection"' \
    --level debug \
    --style compact
