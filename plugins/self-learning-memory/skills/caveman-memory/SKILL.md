---
name: caveman-memory
description: Memory protocol for writing, updating, and pruning agent memory in terse caveman style. Load when saving a lesson after trial-and-error, recording a user correction, deciding between user/repo/session memory scope, maintaining the 200-line user-memory index, or doing memory hygiene (deduping, compressing, deleting stale lines).
---

# MEMORY PROTOCOL — CAVEMAN MODE

You have memory tool. Use it. Write ALL memory in caveman: short lines. No filler. Drop articles ("the", "a"). No prose. One lesson = one line. Tokens precious.

Example good: `gh api: use --paginate not --all. --all not exist.`
Example bad: "I learned that when using the gh api command, the correct flag for pagination is..."

## WHEN TO WRITE MEMORY

- Trial-and-error found non-obvious cmd, flag, fix, workaround → SAVE LESSON before finish task. Not optional.
- Tool call failed, then you found right way → save right way + why old way failed.
- Had to read `--help` or search web for syntax → save syntax.
- User corrected you → save correction.
- Do NOT save: obvious stuff, one-off values, secrets, things already in memory.

## DISTILLING lessons.jsonl (BACKLOG REVIEW)

`log-lesson.sh` (the self-learning-memory plugin's PostToolUse/ErrorOccurred hook) deterministically appends every failed tool call to `~/.copilot-lessons/lessons.jsonl`, even when you don't reflect on it yourself. When the backlog grows past a threshold, the hook reminds you via `additionalContext` — that's your cue to distill it:

- Read the file, group repeated failures by tool + error shape.
- Most entries are noise (transient errors, one-offs, or the log's own known false-positive pattern where it captures an echoed command as if it were error output). Only write a memory line for a lesson that's real, non-obvious, and likely to recur.
- Write survivors into user/repo memory per the scope rules above, in caveman format.
- Truncate `lessons.jsonl` (or the entries you've reviewed) once done — don't leave it to grow unbounded.
- This is mechanical, low-stakes work that doesn't need your main context or a strong model. Delegate it to a subagent (the built-in `task` agent) rather than doing it inline, so the review itself doesn't consume this conversation's tokens.

## SCOPE RULES

**Repo memory** = facts about THIS project:
- build/test/deploy cmds, correct flags for this repo
- codebase patterns, conventions, gotchas
- API quirks of services this repo talks to
- env/setup traps of this workspace

**User memory** = facts true EVERYWHERE:
- global CLI lessons (git, gh, docker, npm, az...)
- personal prefs, machine env facts
- cross-project patterns

Ask self: "true in other repo too?" Yes → user. No → repo.

## USER MEMORY STRUCTURE (200-LINE BUDGET)

Only first 200 lines auto-load. Keep them dense:

- Lines 1–15: INDEX. ToC of sections + other memory files. Format: `[section] line ~N — topic`.
- Lines 16–~190: HOT lessons. Most-used, most-recent. Grouped by tool.
- Line ~195: marker `--- COLD BELOW. READ FULL FILE IF INDEX HINTS RELEVANT ---`
- Below 200: COLD archive. Rare lessons. Still searchable — read full memory file on demand when index or task hints match.

Maintain index when you write. Index stale = memory useless.

## HYGIENE

- Before add: check if lesson exists. Exists → UPDATE line, no duplicate.
- Lesson proved wrong → fix or delete line. Never keep stale.
- Section > ~30 lines → compress: merge similar, demote rare to COLD.
- Prefix each lesson with tool/topic: `docker:`, `gh:`, `this-repo build:`.

## FORMAT OF LESSON LINE

`<tool>: <do this>. <not this — why>.`

Optional date tag if likely to rot: `(2026-08)`.
