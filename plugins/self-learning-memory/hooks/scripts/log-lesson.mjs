#!/usr/bin/env node
/**
 * log-lesson.mjs — PostToolUse / ErrorOccurred hook.
 * Reads hook JSON from stdin. If the tool call looks like a failure,
 * appends a compact record to ~/.copilot-lessons/lessons.jsonl.
 *
 * Defensive about field names: VS Code / Copilot CLI use a mix of
 * camelCase and snake_case depending on version. Verify actual payloads
 * in the "GitHub Copilot Chat Hooks" output channel if nothing logs.
 */
import { appendFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const DIR = process.env.COPILOT_LESSONS_DIR ?? join(homedir(), ".copilot-lessons");
const LOG = join(DIR, "lessons.jsonl");
const MAX_SNIPPET = 400;

// ---- read stdin ----
let raw = "";
for await (const chunk of process.stdin) raw += chunk;
let evt = {};
try { evt = JSON.parse(raw); } catch { process.exit(0); }

const pick = (...keys) => {
  for (const k of keys) if (evt[k] !== undefined) return evt[k];
  return undefined;
};

const eventName = pick("hookEventName", "hook_event_name") ?? "";
const toolName  = pick("toolName", "tool_name", "tool") ?? "unknown";
const toolInput = pick("toolInput", "tool_input", "input");
const toolOut   = pick("toolResult", "tool_result", "toolResponse", "tool_response", "output", "result", "error", "errorMessage", "error_message");

const outStr = typeof toolOut === "string" ? toolOut : JSON.stringify(toolOut ?? "");
const inStr  = typeof toolInput === "string" ? toolInput : JSON.stringify(toolInput ?? "");

// ---- failure heuristics ----
const FAIL_PATTERNS = [
  /exit code[:\s]+[1-9]/i,
  /exited with (code )?[1-9]/i,
  /command not found/i,
  /not recognized as/i,
  /unknown (option|flag|command|argument)/i,
  /unrecognized (option|flag|argument)/i,
  /invalid (option|flag|argument|choice)/i,
  /no such file or directory/i,
  /permission denied/i,
  /\bE(ACCES|NOENT|PERM)\b/,
  /Traceback \(most recent call last\)/,
  /^error[:\s]/im,
  /fatal[:\s]/i,
  /usage:/i, // tool printed usage => likely wrong invocation
  /is not a valid/i,
  /\b4\d\d\b.*(error|status)/i,
  /\b5\d\d\b.*(error|status)/i,
];

const isErrorEvent = /error/i.test(eventName);
const looksFailed = isErrorEvent || FAIL_PATTERNS.some((re) => re.test(outStr));
if (!looksFailed) process.exit(0);

// ---- redact obvious secrets before writing ----
const redact = (s) =>
  s
    .replace(/(ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]{20,}/g, "[REDACTED]")
    .replace(/(sk|rk|pk)-[A-Za-z0-9-_]{20,}/g, "[REDACTED]")
    .replace(/(Bearer\s+)[A-Za-z0-9._\-]{15,}/gi, "$1[REDACTED]")
    .replace(/((?:password|passwd|token|secret|api[_-]?key)["'\s:=]+)[^\s"'&]{6,}/gi, "$1[REDACTED]");

const record = {
  ts: new Date().toISOString(),
  event: eventName,
  cwd: pick("cwd") ?? "",
  tool: toolName,
  input: redact(inStr).slice(0, MAX_SNIPPET),
  error: redact(outStr).slice(0, MAX_SNIPPET),
};

try {
  mkdirSync(DIR, { recursive: true });
  appendFileSync(LOG, JSON.stringify(record) + "\n", "utf8");
} catch {
  // never break the agent because logging failed
}
process.exit(0);
