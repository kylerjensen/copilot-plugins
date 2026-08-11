#!/usr/bin/env node
/**
 * distill-lessons.mjs — the distillery. Run manually or on a schedule
 * (cron / Task Scheduler / occasionally by hand):
 *
 *   node ~/.copilot-lessons/scripts/distill-lessons.mjs           # mechanical distill
 *   node ~/.copilot-lessons/scripts/distill-lessons.mjs --llm     # + Copilot CLI polish
 *
 * Pipeline:
 *   1. Read lessons.jsonl (raw failure records from log-lesson.mjs).
 *   2. Group by tool + error signature, count repeats.
 *   3. Emit caveman candidate lines to distilled.md (repeat offenders first).
 *   4. --llm: pipe candidates through `copilot` CLI to rewrite as true
 *      lessons ("do X not Y") instead of raw failure descriptions.
 *   5. Archive processed records to lessons.archive.jsonl, truncate live log.
 *
 * distilled.md is what inject-lessons.mjs feeds into every new session.
 * Periodically promote proven lines from distilled.md into user/repo
 * memory (the durable store), then delete them from distilled.md.
 */
import {
  readFileSync, writeFileSync, appendFileSync, existsSync, mkdirSync,
} from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";

const DIR = process.env.COPILOT_LESSONS_DIR ?? join(homedir(), ".copilot-lessons");
const LOG = join(DIR, "lessons.jsonl");
const ARCHIVE = join(DIR, "lessons.archive.jsonl");
const OUT = join(DIR, "distilled.md");
const MAX_LINES = 60;           // hard cap on distilled lessons kept hot
const USE_LLM = process.argv.includes("--llm");

mkdirSync(DIR, { recursive: true });
if (!existsSync(LOG)) {
  console.log("No lessons.jsonl yet. Nothing to distill.");
  process.exit(0);
}

// ---- 1. load records ----
const records = readFileSync(LOG, "utf8")
  .split("\n")
  .filter(Boolean)
  .map((l) => { try { return JSON.parse(l); } catch { return null; } })
  .filter(Boolean);

if (records.length === 0) {
  console.log("lessons.jsonl empty. Nothing to distill.");
  process.exit(0);
}

// ---- 2. group by tool + error signature ----
// Signature: first meaningful error line, digits/paths normalized so
// "exit code 127 in /foo" and "exit code 127 in /bar" group together.
const signature = (err) => {
  const line =
    err.split("\n").find((l) => /error|fail|not |invalid|unknown|denied|usage/i.test(l)) ??
    err.split("\n")[0] ?? "";
  return line
    .replace(/\/[^\s"']+/g, "<path>")
    .replace(/\d+/g, "<n>")
    .toLowerCase()
    .slice(0, 120);
};

const groups = new Map();
for (const r of records) {
  const key = `${r.tool}::${signature(r.error ?? "")}`;
  const g = groups.get(key) ?? { tool: r.tool, sig: signature(r.error ?? ""), count: 0, sample: r };
  g.count++;
  g.sample = r; // keep latest sample
  groups.set(key, g);
}

// ---- 3. emit caveman candidates, repeat offenders first ----
const sorted = [...groups.values()].sort((a, b) => b.count - a.count);
const candidates = sorted.map((g) => {
  const cmd = (g.sample.input ?? "").replace(/\s+/g, " ").slice(0, 100);
  const err = g.sig.slice(0, 100);
  const times = g.count > 1 ? ` (x${g.count}!)` : "";
  return `${g.tool}: FAILED${times} \`${cmd}\` -> ${err}. Find right way, save fix.`;
});

let output = candidates.slice(0, MAX_LINES);

// ---- 4. optional LLM polish via Copilot CLI ----
if (USE_LLM) {
  const prompt =
    "Rewrite these raw tool-failure records as caveman-style lessons for coding agent. " +
    "Caveman = terse, no articles, no filler. One lesson one line. " +
    "Format: `<tool>: <do this>. <not this — why>.` " +
    "If failure cause guessable (bad flag, missing arg, wrong cmd), state correct form. " +
    "If cause unknown, keep as warning line. Merge duplicates. Max " + MAX_LINES + " lines. " +
    "Output ONLY lesson lines, no commentary.\n\n" +
    output.join("\n");
  try {
    const polished = execFileSync("copilot", ["-p", prompt, "--allow-all-tools"], {
      encoding: "utf8", timeout: 120_000,
    }).trim();
    if (polished) output = polished.split("\n").filter(Boolean).slice(0, MAX_LINES);
  } catch (e) {
    console.error("Copilot CLI polish failed, keeping mechanical distill:", e.message);
  }
}

// ---- merge with existing distilled.md (keep prior lines, dedupe) ----
let prior = [];
if (existsSync(OUT)) {
  prior = readFileSync(OUT, "utf8").split("\n").filter((l) => l && !l.startsWith("#"));
}
const merged = [...new Set([...output, ...prior])].slice(0, MAX_LINES);

writeFileSync(
  OUT,
  "# distilled lessons (caveman). newest/most-frequent first.\n" +
  "# promote proven lines -> user/repo memory, then delete here.\n" +
  merged.join("\n") + "\n",
  "utf8",
);

// ---- 5. archive + truncate live log ----
appendFileSync(ARCHIVE, records.map((r) => JSON.stringify(r)).join("\n") + "\n", "utf8");
writeFileSync(LOG, "", "utf8");

console.log(`Distilled ${records.length} records -> ${merged.length} lesson lines in ${OUT}`);
