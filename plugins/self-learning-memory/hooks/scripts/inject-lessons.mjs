#!/usr/bin/env node
/**
 * inject-lessons.mjs — SessionStart hook.
 * Emits distilled lessons as additional context for the agent.
 * Reads ~/.copilot-lessons/distilled.md (produced by distill-lessons.mjs).
 * Caps injection size so it never floods the context window.
 */
import { readFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const DIR = process.env.COPILOT_LESSONS_DIR ?? join(homedir(), ".copilot-lessons");
const DISTILLED = join(DIR, "distilled.md");
const MAX_CHARS = 4000; // ~1k tokens ceiling

// consume stdin so the pipe doesn't block
try { for await (const _ of process.stdin) { /* drain */ } } catch { /* ignore */ }

if (!existsSync(DISTILLED)) process.exit(0);

let lessons = "";
try {
  lessons = readFileSync(DISTILLED, "utf8")
    .split("\n")
    .filter((l) => l.trim() && !l.startsWith("#"))
    .join("\n");
} catch { process.exit(0); }
if (!lessons) process.exit(0);

if (lessons.length > MAX_CHARS) {
  lessons = lessons.slice(0, MAX_CHARS) + "\n[TRUNCATED. Full file: " + DISTILLED + "]";
}

const context =
  "PAST FAILURE LESSONS (caveman format, auto-distilled from prior sessions). " +
  "Apply before retrying known-bad invocations:\n\n" + lessons;

// Claude-compatible format VS Code parses; systemMessage as fallback surface.
process.stdout.write(JSON.stringify({
  continue: true,
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: context,
  },
  systemMessage: "Loaded " + lessons.split("\n").length + " distilled lesson lines.",
}));
process.exit(0);
