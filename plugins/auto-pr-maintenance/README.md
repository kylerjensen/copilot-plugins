# auto-pr-maintenance

Automatically keeps your PR description accurate and review threads resolved after every `git push`.

A `PostToolUse` hook watches for `git push` commands. When it detects a push on a branch with an open PR, it injects a system message prompting the agent to run the `post-push-pr-maintenance` skill. The skill then reconciles the PR description with the current diff and handles automated reviewer threads.

## Install

```bash
copilot plugin marketplace add kylerjensen/copilot-plugins
copilot plugin install auto-pr-maintenance@kylerjensen
```

Requirements: `gh` (authenticated), `jq`, `git`.

## What it does

**PR description update:** Preserves manually written prose, reconciles bullets with the current diff (adds missing changes, removes stale ones, fixes factually wrong statements), and respects the repo's PR template structure if one exists.

**Review thread handling:** Auto-resolves threads from bots/AI reviewers (GitHub Copilot Code Review, Claude, CodeRabbit, etc.) with a short reply explaining the outcome. Never touches human reviewer threads; instead surfaces them in chat with links and recommendations.

## How to verify

After install, the hook script lives at:

```
~/.copilot/installed-plugins/kylerjensen/auto-pr-maintenance/hooks/scripts/post-push-pr-maintenance.sh
```

Pipe a synthetic `PostToolUse` payload pointing to a branch with an open PR:

```bash
echo '{"tool_input": {"command": "git push origin my-branch"}}' \
  | bash ~/.copilot/installed-plugins/kylerjensen/auto-pr-maintenance/hooks/scripts/post-push-pr-maintenance.sh
```

Expected output when an open PR exists: a JSON object with `systemMessage` and `hookSpecificOutput.additionalContext` containing the PR number and skill name. With no open PR or a merged PR, output is `{"continue": true}`.
