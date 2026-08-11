#!/usr/bin/env bash
# inject-lessons.sh — SessionStart hook.
# Emits distilled lessons as additional context for the agent.
# Reads ~/.copilot-lessons/distilled.md (produced by distill-lessons.sh).
# Caps injection size so it never floods the context window.
set -uo pipefail

DIR="${COPILOT_LESSONS_DIR:-$HOME/.copilot-lessons}"
DISTILLED="$DIR/distilled.md"
MAX_CHARS=4000

# consume stdin so the pipe doesn't block
cat >/dev/null 2>&1 || true

[[ -f "$DISTILLED" ]] || exit 0

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

lessons="$(grep -v '^[[:space:]]*$' "$DISTILLED" | grep -v '^#' || true)"
[[ -z "$lessons" ]] && exit 0

line_count="$(echo "$lessons" | wc -l | tr -d '[:space:]')"

if [[ "${#lessons}" -gt "$MAX_CHARS" ]]; then
  lessons="$(echo "$lessons" | cut -c1-"$MAX_CHARS")"
  lessons="$lessons
[TRUNCATED. Full file: $DISTILLED]"
fi

context="PAST FAILURE LESSONS (caveman format, auto-distilled from prior sessions). Apply before retrying known-bad invocations:

$lessons"

system_message="Loaded $line_count distilled lesson lines."

# Claude-compatible format VS Code parses; systemMessage as fallback surface.
jq -nc \
  --arg context "$context" \
  --arg msg "$system_message" \
  '{continue: true, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $context}, systemMessage: $msg}'

exit 0
