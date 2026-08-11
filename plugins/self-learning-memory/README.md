# self-learning-memory

Two complementary layers:

1. **Agent-driven memory** (the `caveman-memory` skill) — Copilot writes its own lessons to the built-in memory tool (user + repo scopes). Handles the "I figured it out, remember it" case.
2. **Hook-driven lessons pipeline** (deterministic) — every failed tool call is logged to `lessons.jsonl` even when the agent forgets to reflect. A distillery condenses failures into caveman lessons that get injected at session start.

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
├── plugin.json
├── skills/caveman-memory/SKILL.md   # memory protocol + hygiene rules
└── hooks/
    ├── hooks.json                   # PostToolUse, ErrorOccurred, SessionStart
    └── scripts/
        ├── log-lesson.sh            # PostToolUse / ErrorOccurred → lessons.jsonl
        ├── inject-lessons.sh        # SessionStart → injects distilled.md
        └── distill-lessons.sh       # manual/cron → condenses failures
```

Hook commands resolve scripts via `${CLAUDE_PLUGIN_ROOT}`, the plugin's installation directory. Both Copilot CLI and the VS Code Copilot extension substitute this variable; `${COPILOT_PLUGIN_ROOT}` is CLI-only and expands to an empty string under VS Code. Data still lives outside the plugin, under `~/.copilot-lessons/` (override with `COPILOT_LESSONS_DIR`), so lessons survive plugin reinstalls and updates.

Scripts are bash, invoked directly (executable bit set), and require `jq` on `PATH`.

**Verify hooks:** trigger a failing tool call, then check `~/.copilot-lessons/lessons.jsonl`. Hooks are preview — payload field names shift between versions; `log-lesson.sh` reads both camelCase and snake_case, but if nothing logs, inspect the actual payload in the hooks output/log and adjust the `pick()` keys.

## Run the distillery

```bash
~/.copilot/installed-plugins/kylerjensen/self-learning-memory/hooks/scripts/distill-lessons.sh        # mechanical
~/.copilot/installed-plugins/kylerjensen/self-learning-memory/hooks/scripts/distill-lessons.sh --llm  # + Copilot CLI rewrite
```

Weekly cron/Task Scheduler is plenty. Output goes to `~/.copilot-lessons/distilled.md`, which `inject-lessons.mjs` feeds into each new session (capped ~4k chars).

## The 200-line problem

User memory auto-loads only its first 200 lines, so the skill enforces a tiered layout instead of a scrolling log:

- **Lines 1–15: index/ToC** — sections + pointers to other memory files
- **Hot zone (~175 lines):** frequent, recent, cross-project lessons
- **Cold zone (below 200):** rare lessons — not auto-loaded, but the agent is instructed to read the full file when the index hints something relevant

This works because memory is a real file the agent can read past line 200 on demand — the cap only limits what's _automatic_. The index makes those cold lines discoverable instead of invisible. The distilled.md → memory promotion path (noted in the distillery header) keeps the durable store curated rather than append-only.

## Lifecycle of a lesson

```text
tool call fails ──► log-lesson.mjs ──► lessons.jsonl
                                          │  distill (cron/manual)
                                          ▼
                                    distilled.md ──► injected at SessionStart
                                          │  agent proves lesson useful
                                          ▼
                              user/repo memory (durable, caveman, indexed)
```
