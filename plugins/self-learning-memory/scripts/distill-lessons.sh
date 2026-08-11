#!/usr/bin/env bash
# distill-lessons.sh — the distillery. Run manually or on a schedule
# (cron / launchd / occasionally by hand):
#
#   ./distill-lessons.sh           # mechanical distill
#   ./distill-lessons.sh --llm     # + Copilot CLI polish
#
# Pipeline:
#   1. Read lessons.jsonl (raw failure records from log-lesson.sh).
#   2. Group by tool + error signature, count repeats.
#   3. Emit caveman candidate lines to distilled.md (repeat offenders first).
#   4. --llm: pipe candidates through `copilot` CLI to rewrite as true
#      lessons ("do X not Y") instead of raw failure descriptions.
#   5. Archive processed records to lessons.archive.jsonl, truncate live log.
#
# distilled.md is what inject-lessons.sh feeds into every new session.
# Periodically promote proven lines from distilled.md into user/repo
# memory (the durable store), then delete them from distilled.md.
set -uo pipefail

DIR="${COPILOT_LESSONS_DIR:-$HOME/.copilot-lessons}"
LOG="$DIR/lessons.jsonl"
ARCHIVE="$DIR/lessons.archive.jsonl"
OUT="$DIR/distilled.md"
MAX_LINES=60
USE_LLM=false
for arg in "$@"; do
  [[ "$arg" == "--llm" ]] && USE_LLM=true
done

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required." >&2
  exit 1
fi

mkdir -p "$DIR"
if [[ ! -f "$LOG" ]]; then
  echo "No lessons.jsonl yet. Nothing to distill."
  exit 0
fi

if [[ ! -s "$LOG" ]]; then
  echo "lessons.jsonl empty. Nothing to distill."
  exit 0
fi

# ---- 1. load + validate records ----
records_file="$(mktemp)"
trap 'rm -f "$records_file" "$sig_file" "$grouped_file"' EXIT
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "$line" | jq -c '.' >/dev/null 2>&1 && echo "$line" >> "$records_file"
done < "$LOG"

if [[ ! -s "$records_file" ]]; then
  echo "lessons.jsonl empty. Nothing to distill."
  exit 0
fi

record_count="$(wc -l < "$records_file" | tr -d '[:space:]')"

# ---- 2. group by tool + error signature ----
# Signature: first meaningful error line, digits/paths normalized so
# "exit code 127 in /foo" and "exit code 127 in /bar" group together.
signature() {
  local err="$1"
  local line
  line="$(echo "$err" | grep -Ei 'error|fail|not |invalid|unknown|denied|usage' | head -n1)"
  [[ -z "$line" ]] && line="$(echo "$err" | head -n1)"
  echo "$line" | sed -E 's#/[^[:space:]"'\''"]+#<path>#g; s/[0-9]+/<n>/g' | tr '[:upper:]' '[:lower:]' | cut -c1-120
}

sig_file="$(mktemp)"
while IFS= read -r rec; do
  tool="$(echo "$rec" | jq -r '.tool // "unknown"')"
  err="$(echo "$rec" | jq -r '.error // ""')"
  input="$(echo "$rec" | jq -r '.input // ""')"
  sig="$(signature "$err")"
  printf '%s\t%s\t%s\n' "$tool" "$sig" "$input" >> "$sig_file"
done < "$records_file"

# ---- 3. count groups, emit caveman candidates, repeat offenders first ----
grouped_file="$(mktemp)"
sort -t $'\t' -k1,2 "$sig_file" | awk -F'\t' '
  {
    key = $1 FS $2
    count[key]++
    tool[key] = $1
    sig[key] = $2
    sample[key] = $3
  }
  END {
    for (k in count) {
      print count[k] "\t" tool[k] "\t" sig[k] "\t" sample[k]
    }
  }
' | sort -t $'\t' -k1,1 -rn > "$grouped_file"

candidates_file="$(mktemp)"
while IFS=$'\t' read -r count tool sig sample; do
  cmd="$(echo "$sample" | tr -s '[:space:]' ' ' | cut -c1-100)"
  err="$(echo "$sig" | cut -c1-100)"
  times=""
  [[ "$count" -gt 1 ]] && times=" (x${count}!)"
  echo "${tool}: FAILED${times} \`${cmd}\` -> ${err}. Find right way, save fix." >> "$candidates_file"
done < "$grouped_file"

head -n "$MAX_LINES" "$candidates_file" > "${candidates_file}.trunc"
mv "${candidates_file}.trunc" "$candidates_file"

# ---- 4. optional LLM polish via Copilot CLI ----
if [[ "$USE_LLM" == true ]] && command -v copilot >/dev/null 2>&1; then
  prompt="Rewrite these raw tool-failure records as caveman-style lessons for coding agent. Caveman = terse, no articles, no filler. One lesson one line. Format: \`<tool>: <do this>. <not this, why>.\` If failure cause guessable (bad flag, missing arg, wrong cmd), state correct form. If cause unknown, keep as warning line. Merge duplicates. Max ${MAX_LINES} lines. Output ONLY lesson lines, no commentary.

$(cat "$candidates_file")"
  polished="$(copilot -p "$prompt" --allow-all-tools 2>/dev/null)" || polished=""
  if [[ -n "$polished" ]]; then
    echo "$polished" | grep -v '^[[:space:]]*$' | head -n "$MAX_LINES" > "$candidates_file"
  else
    echo "Copilot CLI polish failed, keeping mechanical distill." >&2
  fi
fi

# ---- merge with existing distilled.md (keep prior lines, dedupe) ----
prior_file="$(mktemp)"
if [[ -f "$OUT" ]]; then
  grep -v '^[[:space:]]*$' "$OUT" | grep -v '^#' > "$prior_file" || true
fi

merged_file="$(mktemp)"
cat "$candidates_file" "$prior_file" | awk '!seen[$0]++' | head -n "$MAX_LINES" > "$merged_file"

{
  echo "# distilled lessons (caveman). newest/most-frequent first."
  echo "# promote proven lines -> user/repo memory, then delete here."
  cat "$merged_file"
} > "$OUT"

merged_count="$(wc -l < "$merged_file" | tr -d '[:space:]')"

# ---- 5. archive + truncate live log ----
cat "$records_file" >> "$ARCHIVE"
: > "$LOG"

rm -f "$sig_file" "$grouped_file" "$candidates_file" "$prior_file" "$merged_file"

echo "Distilled ${record_count} records -> ${merged_count} lesson lines in ${OUT}"
