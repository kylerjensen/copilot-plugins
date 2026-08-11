#!/usr/bin/env bash
# PostToolUse hook: after a terminal tool runs `git push`, checks for an open PR
# on the current branch and reminds the agent to run the post-push-pr-maintenance
# skill. VS Code ignores hook matchers, so this script filters by inspecting
# tool_input from stdin. Policy lives in skills/post-push-pr-maintenance/SKILL.md.
set -euo pipefail

# jq is required for both payload parsing and output construction; exit cleanly if missing.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"continue": true}\n'
  exit 0
fi

input="$(cat)"

command_str="$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")"

# Only act on terminal commands that actually invoke `git push`.
if [[ -z "$command_str" ]] || ! echo "$command_str" | grep -Eq '(^|[[:space:]])git[[:space:]]+push([[:space:]]|$)'; then
  printf '{"continue": true}\n'
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  printf '{"continue": true}\n'
  exit 0
fi

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
if [[ -z "$branch" ]]; then
  printf '{"continue": true}\n'
  exit 0
fi

# Fetch both number and state so we only fire on genuinely open PRs.
pr_json="$(gh pr view "$branch" --json number,state 2>/dev/null || echo "")"
pr_state="$(echo "$pr_json" | jq -r '.state // ""' 2>/dev/null || echo "")"
pr_number="$(echo "$pr_json" | jq -r '.number // ""' 2>/dev/null || echo "")"

if [[ -n "$pr_number" && "$pr_state" == "OPEN" ]]; then
  message="git push detected on branch '$branch' with open PR #$pr_number. Run the post-push-pr-maintenance skill now."
  jq -n --arg msg "$message" '{"continue": true, "systemMessage": $msg, "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $msg}}'
else
  printf '{"continue": true}\n'
fi
