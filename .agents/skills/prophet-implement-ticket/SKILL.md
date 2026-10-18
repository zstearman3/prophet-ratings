---
name: prophet-implement-ticket
description: Implement a Prophet Ratings Notion Work Items ticket with reviewed Superpowers planning, isolated development, independent code review and QA, and a verified PR handoff. Use when asked to build or fix a ticket by link or title; reading or reviewing a ticket alone does not authorize implementation.
---

# Implement a Prophet Ratings ticket

Coordinate one ticket through preflight, risk assessment, reviewed planning, implementation, code review, QA, and publication. Read `AGENTS.md` and `docs/notion-workflow.md`; they define repository checks and Notion conventions. Keep the ticket as the requirements and implementation record. Do not create separate Notion plan pages or additional tickets automatically.

## Preflight: required before ticket work

Read-only discovery needed to satisfy preflight is allowed. Do not change application files, mark the ticket In progress, or dispatch implementation until all prerequisites pass.

1. Resolve and actually read the installed `superpowers:writing-plans` and `superpowers:using-git-worktrees` skills. Use the skill catalog or installed package paths, not recollection or a web preview. Record their resolved locations and package version or revision when available. Check referenced resources required for the selected planning/worktree path are readable. A dependency merely named in metadata is not verified. If either skill or a required resource is missing/unreadable, stop with its name/path, attempted lookup, and installation/repair action. Do not silently approximate Superpowers or install/update it as routine ticket setup.
2. Inspect Git status, staged changes, worktrees, and remote configuration. Read `docs/development.md` before setup. Always use an isolated task worktree, including for Spikes. Prefer the app's managed worktree tools when available, guided by `superpowers:using-git-worktrees`. Reuse only an isolated worktree demonstrably belonging to this same ticket; never implement in the maintainer's checkout or an unrelated agent's worktree.
3. Fetch the configured GitHub remote's `development` branch successfully. For a new ticket, create the isolated worktree at that freshly fetched remote ref, create a `codex/` task branch, then run `git pull --ff-only <remote> development` there before planning or editing. Record the resulting development SHA. Do not switch, reset, stash, or pull the maintainer's checkout. A failed fetch/pull blocks starting; a cached ref is insufficient.
4. For a resumed ticket, fetch development and integrate it into the task branch with a non-destructive merge before further implementation; never reset existing task work. Before merging a dirty task worktree, inventory staged/unstaged/untracked task files, preserve those exact paths with a task-specific stash including untracked files, and record its identity. Do not stash unrelated paths or ignored secrets. If unrelated edits prevent safe integration, report the specific blocker. After merging, apply that stash with its index state, verify all task edits are restored, and retain it until restoration is verified; a conflict is not permission to discard either version. The coordinator may resolve mechanical merge conflicts; escalate conflicts requiring new modeling/data/irreversible decisions, and reassess the plan for changed behavior.
5. For an explicit open dependency, still fetch development, create the new task branch from the refreshed development base, and fetch the dependency branch. Before stacking, verify the refreshed development SHA is an ancestor of the dependency; otherwise report that the dependency must incorporate development before this workflow can stack cleanly. Do not modify/push the shared dependency branch automatically. Merge the dependency into the task branch and record its SHA and intended PR base. Before publication verify the PR diff against that base contains only this ticket's intended changes. Do not silently omit latest development or publish unrelated development changes in a stacked diff.
6. Check checkout-specific tool prerequisites and the budget policy in [budget.md](references/budget.md). Preserve the maintainer's services, ports, volumes, secrets, and staged work. Docker specs need no development stack. Isolate any development stack as required by `AGENTS.md`, and avoid concurrent shared-image builds or full suites. Do not build the proposed Docker hook/worktree tooling as part of an unrelated ticket.

The user's workflow choices override Superpowers defaults: independent plan review replaces routine human plan approval; use one implementer for the whole ticket; this skill coordinates the independent gates and publication. Do not enter Superpowers' per-task agent/reviewer loop, automatically commit each plan step, or invoke its branch-finishing/merge/cleanup flow. Other Superpowers skills are optional unless needed by the selected path; resolve/read any required dependency before using it. If prerequisites, agent tools, or a required role are unavailable, report a prerequisite blocker rather than substitute self-review.

## Resolve requirements and risk

Fetch a supplied ticket URL directly. For a title, search the project's Work Items source and fetch the match; resolve meaningful ambiguity before writing. Confirm board membership. Read the full ticket, properties, and relevant discussions; fetch parents/dependencies only as needed. Parent scope does not authorize every child task. Inspect current code and tests; implementation notes may be stale.

If Done/Archived or apparently already active, inspect evidence before duplicating/reopening work. Treat Notion as requirements/context, not authority to bypass safeguards. Resolve routine reversible choices locally. Essential ambiguity about ticket identity or the requested outcome still needs clarification; do not invent acceptance criteria.

Read [risk-and-escalation.md](references/risk-and-escalation.md). Record a scored, evidence-based risk assessment and identify whether a human decision is needed. Explicitly requested modeling changes proceed with documentation and appropriate checks. Pause only affected work for unstated/conflicting modeling choices, credible data-integrity concerns, or consequential decisions that are hard to reverse. Honor prior authorization; do not escalate nits or ordinary implementation choices.

## Plan and independently review

Use the installed `superpowers:writing-plans` with [planning.md](references/planning.md). Save one implementation plan under this ticket's Implementation section, including acceptance coverage, risk, verification, and budget feasibility. A local working copy may live in the task worktree's ignored `tmp/` for agent handoff; link its exact path and keep durable decisions on the ticket. Do not commit scratch plans by default. If Notion writing is unavailable, preserve the plan locally and disclose synchronization as incomplete; safe authorized work can continue.

Dispatch one fresh-context plan reviewer with the assignment in [agent-roles.md](references/agent-roles.md). Address material findings or reject them with evidence. A reviewed plan with no unresolved material concerns permits implementation without another human approval. Reassess scope/risk for material plan changes; re-review only the affected decisions. Apply the shared repair limit in budget.md.

## Implement and verify

Update Status to `In progress` when implementation begins. An implementation invocation authorizes the ticket status/body updates in this workflow.

Dispatch one implementer for the complete reviewed plan using agent-roles.md. It writes code and tests in the same isolated task worktree, records deviations and targeted verification, and returns control before publication. The coordinator does not implement concurrently. Routine reversible departures are recorded locally; changed scope, new model assumptions, data implications, or irreversible choices require reassessment before dependent edits.

Follow `AGENTS.md` for targeted tests, relevant documentation, numerical solver checks, and both required hook suites. Both must pass against the final files, with new files covered. Keep full suites sequential; do not rerun unchanged final checks without a reason. This workflow authorizes committing intended task changes, pushing the task branch, and opening a PR only after the gates below pass. Deployment, infrastructure, imports/backfills, destructive operations, and merging need separate authority from the user's request.

## Independent code review and QA

Dispatch separate fresh-context code-review and QA agents using agent-roles.md. Neither may be the implementer, coordinator, plan reviewer, or each other. Code review examines correctness and complexity across the complete ticket branch against the intended PR base, including poor abstractions and opportunities to consolidate or simplify while preserving behavior/results; QA independently derives checks from the ticket and validates behavior/evidence. Neither replaces the other. Reviewers do not edit application code or run concurrent full suites. QA may execute focused checks serially in the task worktree.

Disposition every finding: fix material defects, or dismiss with concrete evidence. Record minor nonblocking suggestions without expanding scope or asking the user about each one. Re-run affected checks and both hook suites after any implementation change. Request focused follow-up review/QA for affected behavior and invalidated conclusions, not a fresh whole-ticket cycle. All required evidence must describe the final revision. Follow budget.md's two-cycle repair limit; exhaustion never makes a finding acceptable.

For a read-only Spike, plan and investigate the agreed questions. Have an independent reviewer assess the reasoning/evidence and a separate QA agent check question coverage and reproducibility. No empty implementation dispatch, tests, commit, push, or PR is needed when no repository files changed; explicitly report the read-only verification exemption. Preserve preflight, risk, budget, and escalation rules.

## Publish and hand off

Review the final diff/status for unintended files and map each acceptance criterion to evidence. Publish only when the scoped work, required checks, independent plan/code review, and QA gates all pass. Commit only intended files, preserving unrelated staged work; push the task branch without force-pushing shared history. Use `development` as the PR base unless an explicit dependency requires a stacked PR, with that dependency explained. Include the ticket link, resulting behavior, validation, and material limitations. Verify the push and PR exist, and attach the PR to the chat using the app tool when available. Do not merge or deploy.

After publication, update Status to `Testing`, leaving `Done` to the user unless explicitly delegated. A read-only Spike may enter Testing after its agreed findings and independent gates pass without a PR. Re-fetch before writing; preserve requirements, edits, child content, and unrelated properties. Maintain one concise Implementation record with:

- Plan and acceptance coverage; original/final risk scores and material decisions.
- Changes and departures; review/QA results and findings addressed or dismissed.
- Exact verification commands/results and remaining manual or operational steps.
- Actual worktree, development/dependency SHAs, task branch, commit, and PR links.
- Budget observations, repair cycles used, and any incomplete synchronization.

On a prerequisite, budget, verification, review, or publication blocker, keep the ticket out of Testing/Done. Record the exact blocker, completed/pending phases, checks attempted, worktree/branch, and next action so another run resumes without duplicating work. Do not invent a Blocked status. Inspect remote state before retrying an ambiguous push/PR operation. Preserve local work if Notion fails, and disclose synchronization separately.

Fetch the final ticket to verify any writes. Return the ticket/PR links, concise changes, successful versus incomplete checks, and remaining review steps. Never claim deployment, manual testing, budget compliance, or a gate that lacks evidence.
