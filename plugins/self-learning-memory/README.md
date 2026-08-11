# self-learning-memory

Two complementary layers:

1. **Agent-driven memory** (the `caveman-memory` skill) — Copilot writes its own lessons to the built-in memory tool (user + repo scopes). Handles the "I figured it out, remember it" case.
2. **Hook-driven lessons backlog** (deterministic) — every failed tool call is logged to `lessons.jsonl` even when the agent forgets to reflect. Once the backlog grows large or stale, the hook reminds the agent to distill it — read the raw failures, pick out the real recurring lessons, and write those into memory itself (typically via a delegated `task` subagent, so the review doesn't cost main-conversation tokens).

## Install

```bash
copilot plugin marketplace add kylerjensen/copilot-plugins
copilot plugin install self-learning-memory@kylerjensen
```

Verify the components loaded:

```bash
copilot plugin list
```

Or, in an interactive session, `/skills list` should show `caveman-memory`.

## What ships in the plugin

```text
plugins/self-learning-memory/
├── plugin.json                      # manifest, points "hooks" at hooks.json
├── hooks.json                       # hooks: PostToolUse, ErrorOccurred
├── skills/caveman-memory/SKILL.md   # memory protocol, hygiene rules, backlog distilling
└── scripts/
    └── log-lesson.sh                # PostToolUse / ErrorOccurred → lessons.jsonl + backlog reminder
```

Hook commands self-locate the plugin's installed directory at runtime (checking both `~/.copilot/installed-plugins/` and `~/.vscode/agent-plugins/` install layouts) rather than relying on a `${PLUGIN_ROOT}`-style token — VS Code does not expand that token for Copilot-format plugin hooks ([microsoft/vscode#307478](https://github.com/microsoft/vscode/issues/307478)). Data lives outside the plugin, under `~/.copilot-lessons/` (override with `COPILOT_LESSONS_DIR`), so lessons survive plugin reinstalls and updates.

Scripts are bash, invoked directly (executable bit set), and require `jq` on `PATH`.

**Verify hooks:** trigger a failing tool call, then check `~/.copilot-lessons/lessons.jsonl`. Hooks are preview — payload field names shift between versions; `log-lesson.sh` reads both camelCase and snake_case, but if nothing logs, inspect the actual payload in the hooks output/log and adjust the `pick()` keys.

## Distilling the backlog

`log-lesson.sh` checks the backlog right after logging a failure — the only point where `lessons.jsonl`'s size could have just changed — and nudges the agent via `additionalContext` once it has 25+ lines or its oldest record is 7+ days old (override with `SELF_LEARNING_MEMORY_DISTILL_REMINDER_MIN_LINES` / `SELF_LEARNING_MEMORY_DISTILL_REMINDER_MAX_AGE_DAYS`). A `.last-distill-reminder` marker enforces a 1-hour cooldown so it nags at most once per hour even if the backlog isn't cleared right away.

There's no separate distillery script or LLM shell-out: the reminder asks the agent to do the actual review itself, following the "DISTILLING lessons.jsonl" section of the `caveman-memory` skill — group real recurring failures, skip the noise, write survivors straight into user/repo memory, then truncate the reviewed entries. The skill suggests delegating this to a `task` subagent, since it's mechanical work that doesn't need the main conversation's context.

## The 200-line problem

User memory auto-loads only its first 200 lines, so the skill enforces a tiered layout instead of a scrolling log:

- **Lines 1–15: index/ToC** — sections + pointers to other memory files
- **Hot zone (~175 lines):** frequent, recent, cross-project lessons
- **Cold zone (below 200):** rare lessons — not auto-loaded, but the agent is instructed to read the full file when the index hints something relevant

This works because memory is a real file the agent can read past line 200 on demand — the cap only limits what's _automatic_. The index makes those cold lines discoverable instead of invisible.

## Lifecycle of a lesson

```text
tool call fails ──► log-lesson.sh ──► lessons.jsonl
                                         │  backlog crosses threshold
                                         ▼
                          hook reminds agent (additionalContext)
                                         │  agent distills (often via task subagent)
                                         ▼
                              user/repo memory (durable, caveman, indexed)
```
