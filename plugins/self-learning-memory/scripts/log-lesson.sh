#!/usr/bin/env bash
# log-lesson.sh — PostToolUse / ErrorOccurred hook.
# Reads hook JSON from stdin. If the tool call looks like a failure,
# appends a compact record to ~/.copilot-lessons/lessons.jsonl.
#
# Also auto-triggers the distillery in the background once lessons.jsonl
# has grown large or stale — checked here (not in inject-lessons.sh /
# SessionStart) because this is the only point where the log's size can
# have just changed, and it's rare enough (failures only) not to add
# meaningful overhead. Never blocks: distill-lessons.sh runs detached and
# this hook still exits immediately after appending its own record.
#
# Defensive about field names: VS Code / Copilot CLI use a mix of
# camelCase and snake_case depending on version. Verify actual payloads
# in the "GitHub Copilot Chat Hooks" output channel if nothing logs.
set -uo pipefail

DIR="${COPILOT_LESSONS_DIR:-$HOME/.copilot-lessons}"
LOG="$DIR/lessons.jsonl"
MAX_SNIPPET=400

# Auto-distill thresholds: fire when either is exceeded.
AUTO_DISTILL_MIN_LINES="${SELF_LEARNING_MEMORY_AUTO_DISTILL_MIN_LINES:-25}"
AUTO_DISTILL_MAX_AGE_DAYS="${SELF_LEARNING_MEMORY_AUTO_DISTILL_MAX_AGE_DAYS:-7}"
# Don't re-launch more than once per cooldown, even if the backlog persists
# (e.g. --llm unavailable) — avoids spawning a background process every call.
AUTO_DISTILL_COOLDOWN_SEC=3600

maybe_auto_distill() {
  local auto_marker="$DIR/.last-auto-distill"
  [[ -s "$LOG" ]] || return 0

  local now cooldown_until
  now="$(date -u +%s)"
  if [[ -f "$auto_marker" ]]; then
    cooldown_until=$(( $(cat "$auto_marker" 2>/dev/null || echo 0) + AUTO_DISTILL_COOLDOWN_SEC ))
    [[ "$now" -lt "$cooldown_until" ]] && return 0
  fi

  local line_count oldest_ts oldest_epoch age_days should_run=false
  line_count="$(grep -c '' "$LOG" 2>/dev/null || echo 0)"
  if [[ "$line_count" -ge "$AUTO_DISTILL_MIN_LINES" ]]; then
    should_run=true
  else
    oldest_ts="$(head -n1 "$LOG" | jq -r '.ts // empty' 2>/dev/null)"
    if [[ -n "$oldest_ts" ]]; then
      # BSD date (macOS) and GNU date parse ISO-8601 UTC differently; try both.
      oldest_epoch="$(date -u -d "$oldest_ts" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%S" "${oldest_ts%%.*}" +%s 2>/dev/null || echo 0)"
      if [[ "$oldest_epoch" -gt 0 ]]; then
        age_days=$(( (now - oldest_epoch) / 86400 ))
        [[ "$age_days" -ge "$AUTO_DISTILL_MAX_AGE_DAYS" ]] && should_run=true
      fi
    fi
  fi

  [[ "$should_run" == true ]] || return 0

  local script_dir distill_script
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  distill_script="$script_dir/distill-lessons.sh"
  [[ -x "$distill_script" ]] || return 0

  echo "$now" > "$auto_marker"
  nohup "$distill_script" >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

# jq is required for payload parsing and safe JSON construction; skip silently if missing.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

raw="$(cat)"
[[ -z "$raw" ]] && exit 0

evt="$(echo "$raw" | jq -c '.' 2>/dev/null)" || exit 0
[[ -z "$evt" || "$evt" == "null" ]] && exit 0

pick() {
  local key
  for key in "$@"; do
    local val
    val="$(echo "$evt" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null)"
    if [[ -n "$val" ]]; then
      echo "$val"
      return 0
    fi
  done
  echo ""
}

pick_raw() {
  local key
  for key in "$@"; do
    local val
    val="$(echo "$evt" | jq --arg k "$key" '.[$k] // empty' 2>/dev/null)"
    if [[ -n "$val" && "$val" != "null" ]]; then
      echo "$val"
      return 0
    fi
  done
  echo ""
}

event_name="$(pick hookEventName hook_event_name)"
tool_name="$(pick toolName tool_name tool)"
[[ -z "$tool_name" ]] && tool_name="unknown"

tool_input_raw="$(pick_raw toolInput tool_input input)"
tool_out_raw="$(pick_raw toolResult tool_result toolResponse tool_response output result error errorMessage error_message)"

# Coerce non-string JSON values (objects/arrays) to their string form, matching JSON.stringify semantics.
in_str="$(echo "$tool_input_raw" | jq -r 'if type == "string" then . else tojson end' 2>/dev/null || echo "")"
out_str="$(echo "$tool_out_raw" | jq -r 'if type == "string" then . else tojson end' 2>/dev/null || echo "")"

# ---- failure heuristics ----
FAIL_PATTERN='exit code[:[:space:]]+[1-9]|exited with (code )?[1-9]|command not found|not recognized as|unknown (option|flag|command|argument)|unrecognized (option|flag|argument)|invalid (option|flag|argument|choice)|no such file or directory|permission denied|E(ACCES|NOENT|PERM)|Traceback \(most recent call last\)|^error[:[:space:]]|fatal[:[:space:]]|usage:|is not a valid|[[:digit:]]{3}.*(error|status)'

looks_failed=false
if [[ "$event_name" =~ [Ee]rror ]]; then
  looks_failed=true
elif echo "$out_str" | grep -Eiq "$FAIL_PATTERN"; then
  looks_failed=true
fi

[[ "$looks_failed" != true ]] && exit 0

# ---- redact obvious secrets before writing ----
redact() {
  sed -E \
    -e 's/(ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]{20,}/[REDACTED]/g' \
    -e 's/(sk|rk|pk)-[A-Za-z0-9_-]{20,}/[REDACTED]/g' \
    -e 's/(Bearer[[:space:]]+)[A-Za-z0-9._-]{15,}/\1[REDACTED]/gi' \
    -e 's/((password|passwd|token|secret|api[_-]?key)["'\''[:space:]:=]+)[^[:space:]"'\''&]{6,}/\1[REDACTED]/gi'
}

cwd="$(pick cwd)"
input_redacted="$(echo "$in_str" | redact | cut -c1-"$MAX_SNIPPET")"
error_redacted="$(echo "$out_str" | redact | cut -c1-"$MAX_SNIPPET")"
ts="$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"

mkdir -p "$DIR"
jq -nc \
  --arg ts "$ts" \
  --arg event "$event_name" \
  --arg cwd "$cwd" \
  --arg tool "$tool_name" \
  --arg input "$input_redacted" \
  --arg error "$error_redacted" \
  '{ts: $ts, event: $event, cwd: $cwd, tool: $tool, input: $input, error: $error}' >> "$LOG" 2>/dev/null

maybe_auto_distill

exit 0
