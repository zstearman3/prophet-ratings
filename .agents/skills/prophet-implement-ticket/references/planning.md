# Superpowers planning for Prophet

Read the installed `superpowers:writing-plans`, verified during preflight. Upstream source: [obra/superpowers](https://github.com/obra/superpowers/tree/main/skills/writing-plans). The link identifies the dependency; an online copy does not satisfy the installed-skill prerequisite. Record the actual installed revision when available, and do not update it mid-ticket.

Apply its concrete, testable task decomposition to the ticket's existing requirements. The ticket is the product specification; this phase supplies an implementation plan, not a second product discovery process. Do not invent model defaults, domain examples presented as real data, or acceptance criteria to fill gaps. Revalidate the ticket's code starting points against the current worktree; they are observations, not a prescribed file-edit list. Preserve agreed product behavior, architectural direction, consequential constraints, and their rationale. Distinguish those commitments from labeled suggestions; new evidence that requires changing an agreed commitment needs resolution with the user before dependent implementation.

Use this compact structure, scaled to the task:

1. Goal, scope/non-goals, ticket link, worktree/branch, and development/dependency SHAs.
2. Current behavior and relevant code/test evidence; constraints and stored-data/model assumptions.
3. Risk score, mitigations, escalation decisions, budget feasibility including final gates, and the early-evidence checkpoint below when an acceptance criterion could invalidate the approach.
4. Ordered independently testable tasks: exact files, relevant interfaces, required behavior, concrete test assertions/fixtures, commands and expected outcomes, and documentation changes. State behavior/interfaces precisely without duplicating whole function bodies. Derive numerical expectations independently and explain their assumptions.
5. Acceptance-criterion-to-task/check mapping, regression cases, and review focus. Cover plausible missing/incomplete-data cases when relevant. Plan real-solver verification when required by AGENTS.md; stubbed specs alone do not establish numerical correctness.

## Early evidence for the highest-risk requirement

Identify the acceptance criterion most likely to invalidate the proposed approach. When feasibility is unproven, make the first implementation task the smallest end-to-end slice that exercises that criterion. Specify the uncertainty, representative input, observable pass/fail condition, command or check, and which dependent work waits for the result. A reviewed plan is not feasibility evidence.

Measure that slice before broad implementation or dependent UI/publication integration. Record the observed result and source revision. Expand dependent work only after the observed result meets the planned feasibility condition; on failure, diagnose, revise and rerun the affected check within the slice. For a ticket requiring memory growth evidence, exercise its required scales and unchanged workload/caps at this checkpoint, rather than relying on a small fixture or a passing single scale. Early evidence does not replace final verification after relevant executable changes.

Reuse applicable recorded evidence when its code and assumptions still match. For a routine change with no material feasibility uncertainty, the first targeted correctness check is sufficient; do not invent a spike, benchmark or extra approval gate. Benchmark use remains opt-in under AGENTS.md.

Use targeted failing/passing tests for behavior changes. Documentation-only work needs meaningful document/skill validation rather than artificial application tests. Repository verification rules override upstream examples: use the project's actual commands, cover new files, and reserve both required hook suites for final changes or necessary reruns after fixes.

Self-check coverage, interface consistency, scope, and proportion before independent review. Distinguish expected output in the plan from observed test evidence. Preserve the plan and decisions in the ticket's Implementation record. A local copy under ignored `tmp/` supports handoffs when useful; it does not become another authoritative spec.

## Explicit integration overrides

These are the user's Prophet workflow choices, not upstream defaults:

- The coordinator writes the plan, then an independent agent reviews it. No routine human approval or execution-method question is required. Escalate only material unresolved decisions under risk-and-escalation.md, plus essential missing task information.
- Use one implementer for the whole ticket, followed by independent code review and QA. Do not follow upstream instructions to dispatch an implementer/reviewer per task or automatically invoke additional execution skills.
- Do not commit per plan step, create separate Notion pages, or publish/merge/clean up via a generic branch-finishing skill. This workflow owns publication and preserves the worktree for review/resume.
- Reuse repository setup/verification instructions. Do not import upstream dependency-installation commands, main-branch defaults, unconditional baseline full-suite runs, or service cleanup that could affect the maintainer.

If an installed revision's required resources are incompatible with these choices, report the specific incompatibility before implementation; do not claim integration while substituting remembered instructions.
