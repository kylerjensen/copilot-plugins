---
name: post-push-pr-maintenance
description: "Use immediately after a `git push` to a branch with an open pull request. Updates the PR description to stay accurate with the current diff (respecting the repo's PR template if one exists), and reports on unresolved review threads — auto-resolving threads from automated reviewers (e.g. GitHub Copilot Code Review, Claude, CodeRabbit) with a reply explaining how they were addressed, and separately listing unresolved human-reviewer threads with links and a recommendation, without touching them. Trigger this whenever a push to an open-PR branch just happened, even if the user did not explicitly ask for a PR update."
---

# Post-Push PR Maintenance

Run this after any `git push` to a branch that has an open pull request. It has two independent jobs: keep the PR description accurate, and surface/resolve review feedback. Do both; they are not mutually exclusive.

## 0. Preconditions

1. Confirm there is an open PR for the current branch (e.g. `gh pr view --json number,url,body`). If none exists, stop — nothing to do.
2. Fetch the PR's current body and its review threads (e.g. `gh pr view --json body` and `gh api` / `gh pr view --comments` for threads, or equivalent MCP/tool calls if available).

## 1. Update the PR description

The description is a living document the user may hand-edit between pushes. Treat it as such:

- **Preserve existing prose.** Do not regenerate the description from scratch. Keep any manually written explanation, rationale, or context the user added.
- **Reconcile with the current diff.** Read the full diff since the PR was opened (or since the last update you made, if you can tell). For each section of the description:
  - Add a concise bullet for genuinely new changes not yet reflected.
  - Remove or correct bullets that describe something no longer true (an approach that was abandoned, a bug that no longer exists, a file that was reverted).
  - Fix any bullet that is now factually wrong given the current code, even if the user wrote it.
- **Only describe the final state, not the branch's history.** Compare the base branch against the current tip, not commit-by-commit. If an earlier commit on this branch introduced something (a bug, an approach, a file) that a later commit on the same branch fixed, superseded, or removed, that thing must not appear in the description at all, not as a "fixed" bullet, not as a caveat, nothing. The description should read as if the final diff was written in one shot. This applies retroactively: if a past update to the description added a bullet for something that has since been reverted or replaced within this branch, delete that bullet now.
- **Respect the repository's PR template if one exists.** Look for (in order): `.github/PULL_REQUEST_TEMPLATE.md`, `.github/PULL_REQUEST_TEMPLATE/*.md`, or a root-level `PULL_REQUEST_TEMPLATE.md`. If found:
  - Keep every section the template defines, in its original order. Do not remove, rename, or reorder sections.
  - Fill placeholder/empty sections with real content when you have it; leave genuinely inapplicable sections with a short placeholder like "N/A" rather than deleting them.
  - Preserve template instructional text (italicized notes, HTML comments) unless the template itself says to remove it after reading.
- **No template? Use a generic default structure:**

  ```markdown
  ## Summary

  <what changed and why, 2-4 sentences or bullets>

  ## Notable Changes

  <bullet list of the non-obvious or higher-risk changes>

  ## Testing

  <how this was verified: tests added/run, manual verification>

  ## Caveats

  <known limitations, follow-ups, or things reviewers should pay extra attention to; "N/A" if none>
  ```

- **Be concise.** One or two sentences per bullet. Don't restate what's already obvious from the diff or commit messages, and don't add filler transitions.
- **Writing style:**
  - Prose sentences use present tense (e.g. "This PR adds support for X").
  - Bulleted lists use present-tense verb-first prose per item, e.g.:
    - Adds a foo to the bar, making baz
    - Removes the unnecessary widget
    - Eliminates the broken foobar
- Apply the update by editing the PR body (e.g. `gh pr edit --body-file` or the equivalent tool).

## 2. Handle review threads

Fetch all unresolved review threads on the PR and classify each by author.

### Automated reviewer threads (auto-resolve)

Authors to treat as automated: GitHub Copilot Code Review, and any other bot/AI reviewer account (Claude, CodeRabbit, Sourcery, etc. — recognize by a bot-style login or an explicit "AI"/"bot" marker in the author field).

For each unresolved automated thread:

1. Decide the outcome: **Fixed**, **Rejected**, or **Deferred**.
   - Only resolve if you can state a specific, concrete reason. If you genuinely cannot determine what the comment is asking or whether it was addressed, leave it unresolved rather than guessing.
2. Post a brief reply (1-3 sentences) on the thread:
   - Fixed: describe what changed (e.g., "Done. Extracted magic number into `MAX_RETRY_COUNT`.").
   - Rejected: explain why (e.g., "Declined. This was intentional because X.").
   - Deferred: note the deferral and a follow-up reference if one exists (e.g., "Leaving this as-is for now. This is valid feedback, but it's not critical and can be addressed in a follow-up PR if necessary.").
3. Resolve the thread after replying. Never resolve without leaving a reply first.
4. If the same automated comment repeats near-identically across many locations, still reply/resolve each occurrence, but keep replies after the first brief ("Same as above — see [file:line]").

### Human reviewer threads (never touch)

Do not reply to or resolve any thread authored by a human reviewer, no matter how confident you are in the fix. Instead, at the end of the run, report on them in chat:

- A direct link to each unresolved human thread.
- What the comment is asking for.
- How you addressed it in this push (if you did), or your recommendation for how to address it (if you didn't yet).

## 3. Final report

After completing 1 and 2, summarize in chat:

- Whether the description was updated (and a one-line note on what changed, if anything).
- How many automated threads were resolved, with a one-line reason each.
- The list of unresolved human threads with links and recommendations (may be empty).

Keep the summary brief — a few bullets, not a full report.
