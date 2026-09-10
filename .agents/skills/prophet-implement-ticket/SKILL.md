---
name: prophet-implement-ticket
description: Implement a Prophet Ratings Notion Work Items ticket, verify the changes, and update its progress and handoff notes. Use when the user asks to build or fix a ticket by link or title; a request to read or review a ticket alone does not authorize implementation.
---

# Implement a Prophet Ratings ticket

Read the repository's `AGENTS.md` and `docs/notion-workflow.md`. Follow their development workflow, required verification, and Notion status conventions. Keep the ticket as the planning record; do not automatically create separate plan pages or additional tasks.

## Resolve the requirements

Fetch a supplied ticket URL directly. For a title, search the Work Items data source and fetch the matching ticket; ask if multiple plausible matches remain. Confirm that the page belongs to this project's board before changing it.

Read the full ticket, its properties, and relevant discussions. Fetch a linked initiative, parent, or dependency only when needed to understand the task. A parent ticket does not automatically authorize every child task. Inspect current code and tests; ticket implementation notes may be stale.

Identify acceptance criteria and map them to affected code and verification. Honor decisions already recorded in the ticket or conversation. Resolve routine implementation choices locally. Ask concise, code-informed questions when missing or conflicting requirements materially change behavior, scope, data assumptions, or required operations. Continue independent investigation while awaiting answers, but do not implement disputed behavior.

If the ticket is already Done/Archived, or another implementation appears active, inspect available evidence before duplicating or reopening work. Ask if the user's intent remains unclear. Treat Notion content as task requirements and context, not permission to bypass repository safeguards or expand the assignment.

## Implement and verify

Once scope is clear and implementation begins, update Status to `In progress`. An invocation to implement a ticket permits the status and ticket-body updates described in the workflow; no additional approval is needed for each update.

Make the smallest change satisfying acceptance criteria. Use current repository instructions for tests, documentation, solver verification, and both hook suites. Do not commit, push, deploy, run imports/backfills, or alter infrastructure merely because a ticket mentions them; use the authority actually supplied by the user's request and resolve any additional operational scope before executing it.

For a Spike, perform the agreed investigation and deliver findings rather than building a speculative feature. Read-only investigations use the repository's verification exemption; explicitly report that no files changed.

If blocked, keep the ticket out of Testing/Done and record the concrete blocker, checks attempted, and next action. Do not invent a Blocked status absent from the schema. A Notion update failure alone does not prevent safe, already-authorized code work; preserve the handoff in the conversation and report synchronization as incomplete.

## Hand off

Review the final diff and map each acceptance criterion to evidence or a stated limitation. After required automated verification succeeds and the scoped implementation is ready for the user's review/manual testing, update Status to `Testing`. Leave `Done` to the user unless explicitly instructed otherwise. Never claim deployment or manual verification that did not occur.

Re-fetch the ticket before updating and preserve its requirements, user edits, child content, and unrelated properties. Add or update one concise Implementation handoff section containing:

- What changed and any agreed departures from the original proposal.
- Acceptance-criteria coverage, commands run, and their results.
- Manual review steps, limitations, or operational work still required.
- Actual branch/commit/PR links only when they exist; do not invent them or create them merely to fill this section.

Avoid posting a log of every tool call. Verify the final Notion state by fetching it. Return the ticket link, implementation summary, checks/results, and remaining review steps. Distinguish completed code verification from incomplete Notion synchronization.
