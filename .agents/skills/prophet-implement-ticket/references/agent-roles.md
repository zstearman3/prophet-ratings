# Agent assignments and evidence

Use subagents for this ticket, not user-owned chats. Select models under budget.md. Give each agent a fresh context and exact task worktree, branch/base SHAs, ticket requirements/acceptance criteria, and relevant repository instructions. Pass artifact paths instead of full chat history. Only the implementer makes feature/bug-fix edits to application files; the coordinator may perform preflight Git integration and resolve mechanical merge conflicts under SKILL.md. The coordinator owns Notion, risk/escalation decisions, final gates, and publication. Agents return findings to the coordinator; they do not recursively dispatch agents, publish, or ask for redundant approvals.

Reviewers must be separate agents from each other, the implementer, and coordinator. Independence means deriving a judgment from primary requirements/code/evidence, not rubber-stamping a prior agent's conclusions. Reuse a reviewer for a focused follow-up to its own findings.

## Plan reviewer

Inputs: ticket and relevant discussions, proposed plan, initial risk assessment, relevant code/tests, repository constraints, and budget headroom when known.

Check acceptance coverage, unstated model/data assumptions, current-code compatibility, task/interface consistency, regressions, realistic verification, reversibility, and scope/cost. Inspect affected source rather than trusting plan assertions. Return material findings with evidence and recommended corrections; identify nits separately. Do not rewrite code or dispatch more agents. State whether material planning gaps remain and which areas could not be assessed.

## Implementer

Inputs: requirements, independently reviewed plan, review dispositions, risk/escalation rules, worktree/base, and verification commands.

Implement the whole ticket in this worktree. Use existing conventions, targeted behavior tests, and required documentation. Stop dependent work and return evidence if a discovery needs a new model assumption, threatens data integrity, or requires a consequential irreversible choice. Record ordinary reversible deviations without waiting for approval. Run targeted checks, inspect output, and report exact commands/results, changed files, plan deviations, and remaining concerns. Do not commit, push, open a PR, update Notion, or delegate. The coordinator arranges the final hook runs and independent gates serially.

## Code reviewer

Inputs: original requirements, reviewed plan, final diff including new/untracked files, base and current revision, risk assessment, and verification evidence.

Inspect correctness, regressions, model/data assumptions, Rails conventions, scope, tests that can pass despite a defect, and missing verification. Trace affected callers and boundary behavior where needed. Return actionable findings with file/line evidence, impact, and severity; distinguish material defects from optional improvements. Do not edit files or rerun full suites. State limitations and whether material findings remain. For follow-up, examine the fix and its affected paths against the original finding and requirements.

### Branch complexity and simplification

As part of the same code-review pass, assess the complete ticket diff against its intended PR base, including earlier commits and staged/unstaged/new files. Inspect affected callers and existing helpers for context. Look for abstractions that add indirection without a current need, overlapping responsibilities, duplicated business rules or orchestration, and branches/data flow that can be consolidated or made simpler. Check whether apparently similar paths have meaningful differences before proposing shared code. Review nearby unchanged code only as needed to understand or simplify the affected paths; keep unrelated cleanup out of scope.

For each actionable opportunity, give file/line evidence, the concrete maintenance cost, the smallest useful simplification, why the actual behavior/results remain equivalent, and the regression evidence needed to verify that claim. Preserve model assumptions, numerical behavior, persisted outputs/configuration hashes, error handling, and external side effects; passing existing tests alone is not proof of equivalence. Prefer a clear existing Rails/domain pattern when it reduces complexity. Fewer lines or classes alone do not establish an improvement.

Return an explicit complexity assessment: actionable findings, no material concerns, or not assessed with the reason/coverage gap. If required branch coverage cannot be assessed, leave the code-review gate incomplete rather than approve it. Classify meaningful maintainability/regression risks as material findings under the existing gate; distinguish small worthwhile simplifications from nonblocking style preferences. The coordinator should incorporate safe, branch-local simplifications with a concrete benefit within the existing repair allowance, or record why they are deferred/dismissed. Do not require a refactor merely to produce a finding, change results to obtain simpler code, or open an additional review/refactoring phase. Simplification edits require the same affected checks, final hook suites, and focused code-review/QA follow-up as other fixes.

## QA reviewer

Inputs: original ticket requirements, relevant repository/domain documentation, task worktree/final revision, and risk areas. First derive acceptance and regression checks independently; then inspect the plan, diff, and command evidence to assess coverage. Do not receive another reviewer's verdict as a presumed conclusion.

Validate observable behavior, missing/incomplete-data cases, numerical expectations, and operational prerequisites relevant to the ticket. Execute focused checks when useful, serially after other runs finish, using disposable/synthetic data and the documented Docker workflow. Distinguish checks actually executed from evidence inspected and manual checks still needed. Do not edit application files, import/backfill domain data, reset databases, or run an unnecessary second full suite.

Return an acceptance matrix: criterion/check, observed result and evidence, pass/fail/unverified. Stubbed numerical specs do not prove real solver behavior; include independently reasoned synthetic expectations when required. For documentation/skills, inspect reachable references and exercise realistic decision scenarios; do not invent UI tests. For a read-only Spike, validate agreed question coverage and reproducible supporting evidence. A missing required check is unverified, never a pass.

## Gate decisions

Review findings are recommendations; the coordinator must resolve each material finding with a verified fix or an evidence-based dismissal. An unresolved disagreement about a material defect does not pass a gate. Route actual human decisions through risk-and-escalation.md; otherwise investigate within the repair/budget limits and report an incomplete handoff if unresolved. Findings that change modeling, data integrity, scope, or reversibility trigger risk/plan reassessment. Code changes invalidate affected review/QA conclusions and final verification; update evidence before publication.
