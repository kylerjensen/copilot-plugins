#!/usr/bin/env bash
# log-lesson.sh — PostToolUse / ErrorOccurred hook.
# Reads hook JSON from stdin. If the tool call looks like a failure,
# appends a compact record to ~/.copilot-lessons/lessons.jsonl.
#
# Defensive about field names: VS Code / Copilot CLI use a mix of
# camelCase and snake_case depending on version. Verify actual payloads
# in the "GitHub Copilot Chat Hooks" output channel if nothing logs.
set -uo pipefail

DIR="${COPILOT_LESSONS_DIR:-$HOME/.copilot-lessons}"
LOG="$DIR/lessons.jsonl"
MAX_SNIPPET=400

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

exit 0
