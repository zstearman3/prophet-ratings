# One-ticket economics

Target one ticket, including all agent work and final gates, within one Plus five-hour usage allowance. This is a consumption target, not five elapsed hours or a fixed token count. Pro availability does not relax the default. User-specified tighter limits take precedence. Skill instructions and coarse account snapshots are a soft policy, not a guaranteed subscription spending cap.

## Checkpoints and reserve

- At start and phase boundaries, read the usage tool when available and record window duration, remaining percentage, and reset time. Select a 300-minute window by its duration rather than assuming primary/secondary order. Respect other applicable windows too. Avoid repeated polling.
- Reserve at least 20 percentage points of the full five-hour allowance as a safety margin. Plan against the remaining headroom above that floor, including reviews, QA, hooks, repairs, and publication. User-provided per-ticket consumption ceilings further limit that headroom. Begin an expensive phase only when the remaining work plausibly fits; the reserve is not a promise about the cost of the next call.
- Account usage includes other chats and may update late. Treat observed consumption conservatively; do not claim exact attribution to this ticket. A reset does not replenish this ticket's allowance or authorize another window. Before crossing a reset with unfinished work, hand off rather than silently start a second allowance. Do not wait out limits, purchase credits, switch billing, or create an automation to continue without instruction.
- If no five-hour window/tool is exposed (including Pro), state that numerical tracking is unavailable. Use the process limits below, modest contexts, and a feasibility assessment; do not translate weekly percentages or API token prices into a fictional Plus allowance or claim the target was measured.

## Bound the work

The default is one coordinator, one plan reviewer, one implementer for the whole ticket, one code reviewer, and one QA agent. Branch complexity/simplification assessment belongs to that same code-review pass and repair allowance, with no extra agent or automatic cleanup phase. Use sequential handoffs and fresh contexts for independent gates. Never fork the entire chat into every role. Give each role only the ticket requirements, necessary instructions, relevant plan/evidence paths, and its assignment.

Default models: `gpt-6-luna` with medium reasoning for routine implementation; `gpt-6.1-sol` with medium reasoning for independent plan/code review and QA. For sensitive math/data work or demonstrated implementation failure, the coordinator may use `gpt-6.1-sol` for implementation and record why it fits the budget. Explicit user model preferences win. Check runtime availability; if a default is unavailable, choose an available suitable model within the same cost intent and record the substitution. If no suitable affordable role is available, report the blocker rather than silently upgrade to the most expensive model or omit independence.

Allow at most two repair cycles total across plan review, code review, and QA: each cycle groups material findings, updates the affected plan/code, runs necessary verification, and obtains focused follow-up evidence for the invalidated gates. Reuse the relevant agents; do not respawn all roles or restart completed phases. Record the count in the implementation record. Required checks after fixes remain mandatory. New substantive findings after the second cycle require an incomplete handoff; minor suggestions do not trigger cycles.

Do not delegate each small task, run parallel full suites, generate implementation-sized plans, repeatedly fetch unchanged documents, or chase unrelated improvements. Capture long logs locally and provide concise commands/results. Plan review must assess feasibility before implementation. If the full ticket appears too large, present a proposed smaller deliverable or split for agreement; do not silently drop acceptance criteria or create extra tickets.

## Stop with a resumable result

When headroom, repair cycles, or feasibility no longer support completion, stop starting new phases. Safely finish/clean up any already-running command; do not terminate a data operation unsafely. Preserve worktree, plan, findings, commands/results, completed/pending gates, and the next concrete action. Keep the ticket out of Testing/Done and do not publish a PR presented as ready. Budget pressure never permits weaker assertions, skipped required hooks/reviews/QA, or unresolved material defects.
