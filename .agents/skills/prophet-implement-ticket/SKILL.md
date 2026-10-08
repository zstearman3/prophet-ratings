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

Before starting a story, fetch the GitHub remote and create a new task branch from the latest remote `development` branch. Preserve unrelated local and staged changes; use an isolated worktree when needed. Do not reuse an unrelated working branch. If the story depends on changes in another open branch or PR, create a new branch from that dependency instead and record the dependency and intended PR base in the handoff.

For agent worktrees, read `docs/development.md` and follow the "Agent worktrees and Docker preference" section of `AGENTS.md` before setup or verification. The maintainer uses the main checkout; preserve its running services and data. Prefer Docker specs, isolate any worktree development stack, and check checkout-specific prerequisites for the currently native hook suites. Do not assume the recommended Docker hook/worktree setup tooling exists or implement that follow-up as part of an unrelated story.

Once scope is clear and implementation begins, update Status to `In progress`. An invocation to implement a ticket permits the status and ticket-body updates described in the workflow; no additional approval is needed for each update.

Make the smallest change satisfying acceptance criteria. Use current repository instructions for tests, documentation, solver verification, and both hook suites. This workflow authorizes committing the intended task changes, pushing the task branch to GitHub, and opening a PR after verification and independent review. Deployment, imports/backfills, and infrastructure changes still require authority from the user's request; a ticket mentioning them does not supply it.

## Independent review and pull request

After implementation and required verification, launch a separate code-review agent using the sol model tier (`gpt-6.1-sol`) with a fresh context. Give it the ticket requirements, repository instructions, branch/base information, and access to the final diff. Request a read-only review for correctness, regressions, missing verification, and unmet acceptance criteria; do not have the reviewer edit files or run concurrent full suites.

Assess each finding and either incorporate it or dismiss it with a concrete rationale. Resolve material issues before publishing. If review changes the implementation, run relevant checks and both required hook suites against the final changes. Request a focused follow-up review when fixes leave material uncertainty. If the review agent is unavailable, report the review as blocked rather than silently omitting it.

Once the implementation is satisfactory to the implementing agent, independent feedback is addressed, and required checks pass, commit only the task's intended files, push the branch to GitHub, and open a PR. Use `development` as the base unless the changes need to stack against an open dependency branch/PR; explain any stacked dependency. Preserve unrelated staged work and avoid force-pushing shared branches.

Keep the PR description simple: explain the problem and resulting change, summarize validation, and raise concrete concerns, limitations, or decisions that need human review. Include the Notion ticket link. Verify the push and PR exist before recording their links. Do not merge or deploy as part of this workflow. If publication fails, report the exact blocker and preserve the verified local work; inspect remote state before retrying an ambiguous push or PR creation.

For a Spike, perform the agreed investigation and deliver findings rather than building a speculative feature. Read-only investigations use the repository's verification exemption; explicitly report that no files changed. Have the independent agent review the findings and evidence; no empty commit, push, or PR is required for a read-only handoff.

If blocked, keep the ticket out of Testing/Done and record the concrete blocker, checks attempted, and next action. Do not invent a Blocked status absent from the schema. A Notion update failure alone does not prevent safe, already-authorized code work; preserve the handoff in the conversation and report synchronization as incomplete.

## Hand off

Review the final diff and map each acceptance criterion to evidence or a stated limitation. After required automated verification, independent review, and PR publication succeed and the scoped implementation is ready for the user's review/manual testing, update Status to `Testing`. For a read-only Spike, update to `Testing` after the agreed findings are delivered and independently reviewed, without requiring publication. Leave `Done` to the user unless explicitly instructed otherwise. Never claim deployment or manual verification that did not occur.

Re-fetch the ticket before updating and preserve its requirements, user edits, child content, and unrelated properties. Add or update one concise Implementation handoff section containing:

- What changed and any agreed departures from the original proposal.
- Acceptance-criteria coverage, commands run, and their results.
- Manual review steps, limitations, or operational work still required.
- Independent review findings addressed or dismissed, with rationale for material dismissals.
- Actual branch/commit/PR links and any stacked dependency; do not invent links.

Avoid posting a log of every tool call. Verify the final Notion state by fetching it. Return the ticket link, implementation summary, checks/results, and remaining review steps. Distinguish completed code verification from incomplete Notion synchronization.
