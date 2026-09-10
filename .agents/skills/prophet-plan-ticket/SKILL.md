---
name: prophet-plan-ticket
description: Refine a Prophet Ratings idea or bug into a Notion Work Items ticket through code-informed clarification. Use when the user wants to plan, scope, or create a ticket; do not implement application changes as part of planning.
---

# Plan a Prophet Ratings ticket

Turn the user's idea into a small, implementable ticket through an iterative conversation. Act as a senior Rails architect familiar with this hobby project's limited monthly development time.

Read the repository's `AGENTS.md` and `docs/notion-workflow.md` before proceeding. The latter supplies the board location, properties, and publishing conventions. Use the connected Notion tools; this skill does not require the generic Notion skill's separate plan pages or task hierarchy.

## Investigate before asking

Understand the desired outcome, then inspect relevant application code, tests, and selectively routed domain documentation. Search Work Items for existing or overlapping tickets and fetch likely matches. Reuse facts already provided by the user or established by code; do not ask the user to explain discoverable implementation details.

Distinguish observed behavior, user requirements, and proposed implementation. Cite repository-relative paths and class/method names for findings. A historical ticket or roadmap is not evidence that behavior still exists or is still missing.

## Refine together

Ask a small batch of the highest-impact unresolved questions, usually one to three. Explain the concrete code finding or tradeoff behind each question and offer a pragmatic recommendation when useful. Wait for answers, inspect further as needed, and refine the proposal. Do not turn this into a fixed questionnaire or silently answer product decisions for the user.

Select questions that affect this idea, such as:

- Missing or stale snapshots, incomplete games, configuration versions, and reproducibility for ratings/predictions.
- Eastern schedule dates, duplicate imports, retries, idempotency, and partial failure for ingestion/jobs.
- Empty/error states, filters, access requirements, and what stored data supports a displayed claim for UI/GPT work.
- Historical compatibility, explicit backfills, and operational cost when a change actually requires them.

For example, if a proposed prediction screen uses `GamePredictionBuilder`, inspect its current missing-snapshot behavior before asking how games without predictions should appear. Do not treat that example as a permanent description of the implementation.

Prefer one independently useful change. If the idea is too large, propose a first slice and explicit non-goals; obtain agreement on scope before creating multiple tickets. If essential feasibility is unknown, propose a Spike with a concrete investigation outcome instead of inventing implementation certainty.

Do not create a Notion draft while questions remain unanswered. Keep the working draft in the conversation. Material questions change acceptance criteria, scope, data assumptions, or required operations. Optional metadata can use the documented defaults. Stop asking when the outcome is clear; do not manufacture questions solely to extend the process.

## Write the ticket

Use the existing board's concise Description convention, enriched with enough detail for another agent to work without this conversation:

- Description: problem, desired outcome, and agreed scope/non-goals.
- Acceptance criteria: observable, testable outcomes, including relevant edge cases.
- Implementation notes: observed code paths, likely smallest approach, decisions and rationale; label suggestions as suggestions.
- Verification: targeted scenarios/checks, the repository hook gate, and any real-solver or manual verification required.
- Dependencies or operational steps only when relevant.

For bugs, include Steps to Reproduce, actual versus expected behavior, and available evidence. Label unverified reports; do not invent reproduction steps. For a Spike, specify questions to answer and the deliverable, without promising an application implementation.

Once material questions are answered, summarize the agreed scope and properties and create the requested ticket. Do not add a second permission gate if the user already requested creation and scope is settled. If the user asked only to explore or draft, keep it in the conversation until creation is requested.

Search again for duplicates immediately before creating. If an existing ticket covers the request, show the match and resolve whether to update it rather than silently creating a duplicate or editing unrelated work. Follow `docs/notion-workflow.md` for schema refresh, creation, and read-back verification. Return the ticket link and a short summary. Do not begin implementation unless requested.
