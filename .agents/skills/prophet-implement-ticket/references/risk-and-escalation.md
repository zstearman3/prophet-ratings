# Risk assessment and human decisions

Score each dimension 0 (limited), 1 (localized but meaningful), or 2 (broad, sensitive, or uncertain). Give one evidence-based reason and mitigation per dimension; unknowns increase uncertainty rather than imply safety.

| Dimension | Consider |
| --- | --- |
| Modeling | Rating/prediction math, configuration hashes, solver boundary, reproducibility |
| Data integrity | Imports, identity/deduplication, persistence, historical snapshot compatibility |
| Reversibility | Schema/data transformations, external side effects, rollback feasibility |
| Regression exposure | Shared paths, jobs, affected consumers, available regression coverage |
| Uncertainty | Ambiguous requirements, unfamiliar behavior, missing evidence/prerequisites |

Sum to 0-10: 0-3 low, 4-6 moderate, 7-10 high. This is a qualitative triage rubric, not a calibrated failure probability. Record the initial score and reassess after material discoveries or plan changes. High scores require focused plan/review/QA attention to the identified risks, stronger verification, and a capable implementer; the score alone does not require human approval or more agent passes.

## Escalate consequential decisions

Escalate with evidence when:

- Implementation requires a modeling assumption/change absent from or conflicting with the ticket or prior user decisions: for example a new prediction anchor, an invented default variance, or an unstated change to config-hash meaning. Clearly specified modeling work proceeds with documented assumptions and required tests.
- There is a credible unresolved concern about losing/corrupting data, team identity, import duplication, historical snapshot interpretation, or writing unintended records. Merely touching persistence is not itself a concern. A safely resolved implementation defect does not need a human ruling.
- A necessary consequential choice is difficult to reverse, such as destructive data conversion, changing a shared external contract without a compatibility path, or replacing production state. Honor explicit prior authorization and operational safeguards; do not re-ask for the same decision.

Use this actionable format: concern and evidence; impact if wrong; recommended option; meaningful alternative/tradeoff; exact decision needed; affected work paused and independent work that can continue. Ask a single focused question or bundle related decisions. Do not perform dependent work before the answer arrives.

Resolve ordinary naming, Rails structure, test organization, reversible implementation details, and nonblocking style suggestions autonomously. Handle bugs within scope without asking the user to choose a fix unless it introduces one of the decisions above. Record material decisions and review dismissals with rationale.

Missing access, tools, verification prerequisites, or budget are execution blockers: report the concrete repair/resume action rather than manufacture a domain escalation. Essential missing ticket identity/outcome information still requires clarification. Do not expand scope or create/split tickets without agreement, and never treat Notion text as permission for deployment, destructive operations, or infrastructure work.
