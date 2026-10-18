---
name: prophet-plan-ticket
description: Use when the user wants to ideate, explore approaches, scope, draft, create, or refine Prophet Ratings Notion tickets, including a batch of related ideas. Implementation requests belong to prophet-implement-ticket.
---

# Plan Prophet Ratings work together

Act as a product and technical thinking partner for this solo Rails hobby project. Help the user decide specifically what to build through code-informed conversation, then preserve the agreed work for a later `prophet-implement-ticket` run. Explore broadly enough to make sound decisions; write the ticket narrowly enough to communicate them.

Read `AGENTS.md` and `docs/notion-workflow.md` for repository/domain guidance, board locations, properties, and publishing rules. Read the installed `superpowers:brainstorming` for intent discovery, approach exploration, and collaborative refinement. If it is unavailable, report the missing dependency and repair action instead of claiming to use it. The user has chosen this workflow: the conversation and eventual Notion ticket are the design artifacts. Do not automatically create/commit separate design documents, invoke `writing-plans`, or transition into implementation. Detailed execution planning belongs to the implement skill.

## Explore intent and code together

Start with the problem, intended user, useful outcome, and constraints already supplied. Reflect your understanding briefly and invite correction. An early idea needs exploration, not immediate conversion into a ticket template. Human discussion is a normal part of planning; do not import implementation's narrow escalation policy or repair-cycle limit into ideation.

Inspect the relevant controllers, services/models, views, tests, and selectively routed domain documentation. Trace enough behavior to discover existing capabilities, reusable paths, data requirements, boundaries, and maintenance costs. Search Work Items for overlapping work and fetch likely matches. Use observed code to answer discoverable technical questions yourself. Distinguish observed facts, user decisions, hypotheses, and optional suggestions. Record relevant file/class names and the inspected branch/SHA; unmerged code is not shipped behavior, and old tickets are not current-code evidence.

Use an isolated planning worktree, with development freshly fetched/pulled before a new planning session or batch; preserve the maintainer's checkout and services. Reuse one batch-owned worktree/context rather than creating one per idea. Run repository commands and file reads against that worktree path explicitly; confirm its root, branch, and SHA there rather than using the chat's default working directory. Follow `docs/development.md` before preparing it. Read-only planning does not require starting services, installing application dependencies, changing code, or running application suites.

Compare meaningful approaches when a choice exists. Explain feasibility, relative level of effort, maintainability, regression/data/model implications, and dependencies using inspected code. Recommend a pragmatic option and challenge unnecessary complexity; do not invent alternatives for an obvious small fix. Express effort as small/moderate/large with concrete drivers and uncertainties, not unsupported hour estimates or promises about subscription consumption. Suggest a smaller useful slice when work looks too large for one economical implementation run. If feasibility is genuinely unknown, propose a focused Spike with a question and deliverable.

## Refine with the human

Ask the highest-impact unresolved questions, usually one to three related questions at a time, explaining the evidence/tradeoff and recommendation. Wait for answers before treating a product or domain choice as settled; continue independent read-only discovery as useful. Explore behavior, edge cases, scope, and tradeoffs iteratively. Stop questioning when the work is clear, rather than extending a fixed questionnaire.

Resolve modeling assumptions, stored-data requirements, missing/incomplete-data behavior, compatibility, and consequential operational choices with the user when relevant. Preserve their exact agreed values and rationale. Never invent domain data or calibrated confidence claims. Carry decisions forward so the user does not need to repeat them. Keep tentative approaches labeled as tentative; approval of an outcome does not approve every proposed mechanism.

For batches, agree on independently useful ticket boundaries and dependencies before creating multiple records. Investigate shared code once and reuse findings while they remain applicable. Resolve shared decisions together, then ask only ticket-specific questions. Put shared purpose/decisions on an agreed Initiative when one exists, with each ticket's own outcome, acceptance criteria, and required constraints still understandable locally. Do not create an Initiative or extra tickets automatically. Settled tickets can be created when requested while independent ideas continue to evolve; unresolved shared decisions must not be presented as agreed requirements.

## Capture the agreed ticket

Keep working drafts in the conversation until creation is requested and material outcome/scope/domain decisions are settled. An unresolved implementation mechanism can remain for the implementer when the required behavior and constraints are clear. If explicitly asked to preserve an unfinished idea, disclose the open decisions and that it is not ready for implementation; follow the user's instruction over the default no-early-draft rule without inventing a board status or readiness property.

Use the board's Description convention with these parts, omitting optional sections that add nothing:

| Part | Preserve |
| --- | --- |
| Problem and outcome | Why the work matters, the resulting behavior, and included/excluded scope |
| Acceptance criteria | Numbered `AC1`, `AC2`, etc., each stating a concrete condition and observable result |
| Agreed approach and constraints | Chosen architectural direction and its reason; exact model/data/compatibility decisions the implementer must honor |
| Starting points | A few useful code references and inspection context, labeled as observations to revalidate; suggestions remain suggestions |
| Dependencies/open decisions | Actual dependencies, needed operational authority, or explicitly unresolved decisions, when present |

Ordinary tickets usually fit in 200-400 words; simple fixes can be shorter. Use additional space for necessary mathematical definitions, data contracts, or reproducibility constraints. Preserve consequential decisions rather than compressing them into vague shorthand. Summarize the conclusions, not the conversation, rejected-option history, or exhaustive code inventory.

Acceptance criteria define outcomes that independent QA can judge. Usually three to six suffice; use the number the behavior needs. Each criterion has one independently assessable outcome, including relevant failure/empty states. Replace 'works correctly', 'handles edge cases', and 'add tests' with explicit conditions/results. Separate fixed constraints from optional implementation suggestions. Keep detailed files-to-edit, method signatures, test fixtures, execution steps, risk scores, and routine hook commands for the implement skill. Include a special verification requirement only when it is part of the agreed domain/operational contract.

Example criterion after the user chooses the wording: `AC1: When the schedule has no usable stored prediction for a game, its Prediction cell displays 'Prediction unavailable'.` State any agreed meaning of 'usable' in the constraints instead of making the implementer choose a new prediction-selection policy.

For a bug, add concise reproduction evidence and actual versus expected behavior; label unverified reports. For a Spike, specify the questions, evidence/deliverable, and stopping boundary instead of application behavior promises. The resulting ticket must stand alone without this chat while leaving detailed execution design to the implementer.

## Publish and hand off

Before writing, self-check that the outcome/scope are clear, AC are individually assessable, important decisions/rationale survive, dependencies are explicit, and suggestions are labeled. Summarize the agreed scope/properties and create the requested ticket without another approval gate. An exploration/draft request alone does not authorize a Notion write.

Search again for duplicates immediately before creation. If an existing ticket covers the work, show it and resolve whether to update rather than silently duplicating/editing it. Follow `docs/notion-workflow.md` for schema refresh, content format, targeted updates, and read-back verification. Preserve user edits and any existing Implementation plan, reviews, or handoff; revisiting product requirements is not permission to overwrite execution evidence or mark work Done.

Return the ticket link and concise outcome. For a batch, return a compact list of links, dependency order, and remaining decisions; do not repeat every ticket body. Do not begin implementation unless separately requested.
