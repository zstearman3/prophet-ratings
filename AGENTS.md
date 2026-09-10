# AGENTS.md

## Project Overview

Prophet Ratings is a Ruby on Rails college basketball analytics platform. It generates adjusted team ratings, predictions, and matchup analysis using scraped game data, a Python-based least squares solver, and daily rating snapshots.

The long-term goal is to launch a conversational, GPT-powered college basketball analytics experience ahead of the next March Madness. The app should help users understand matchups, identify prediction confidence, explore adjusted team strengths, and eventually evaluate betting value.

This is a solo side project with limited monthly development time. Prefer pragmatic, incremental improvements over large rewrites.

---

## Agent Workflow

1. Inspect Git status and relevant files before editing. Preserve unrelated changes and staged work; a dirty checkout does not block independent work. Ask only if overlapping changes cannot be safely preserved.
2. Briefly explain the intended change, then make the smallest useful, PR-sized implementation. Do not perform broad refactors without explicit direction.
3. Carry implementation through verification. Make routine, reversible decisions using existing conventions; ask when an unresolved choice materially affects behavior, scope, cost, or data integrity. Honor authorization already given in the conversation.
4. Keep work within the requested task. Launch priorities provide context, not authorization to add features. Reviews and diagnosis do not authorize implementation unless requested.
5. Document changes to model assumptions explicitly. Never invent domain data or make prediction logic depend on unstored transient values.
6. Update relevant documentation when behavior, commands, or operational requirements change.
7. Review the final diff and Git status for unintended files, schema churn, debugging code, and unrelated changes. Leave the repo runnable.

### Required Verification

Before declaring a task that changes repository files complete, run both hook suites successfully against the final changes:

```bash
bundle exec overcommit --run
bundle exec overcommit --run pre_push
```

- These commands verify hooks without committing or pushing. Verification alone does not authorize a commit or push.
- Ensure newly added files are covered: the all-files pre-commit run covers tracked files. Check new files directly with the applicable checks or stage only the task's intended files, preserving unrelated staged work.
- Run targeted tests during development, then the required hook suites at completion. Avoid redundant full-suite runs when the same final changes have already passed. `bin/check` does not replace both hook suites; it omits some pre-commit hygiene checks.
- Fix failures caused by the task. Do not bypass hooks, disable checks, weaken assertions, or expand lint/security exclusions merely to pass.
- If verification is blocked or fails for an unrelated reason, report the exact command, failure, and remaining work. Describe the changes as implemented but verification incomplete; do not claim completion or expand into unrelated repairs.
- Read-only reviews and discussions do not require running hooks.

See `docs/development.md` for hook prerequisites, setup, and known verification limitations.

### Definition of Done and Handoff

A task that changes repository files is complete when:

- The intended behavior works locally and fits existing Rails conventions.
- Tests are added or updated for changed behavior, and relevant tests and both hook suites pass.
- Model/data assumptions and changes to behavior or commands are documented where needed.
- The final diff contains only intended changes, with no secrets or accidental environment-specific values.
- The implementation is small enough to understand after another side-project hiatus.

The final response should briefly state what changed, which checks ran and their results, and any remaining limitations or manual steps. Distinguish successful verification from checks that were skipped, blocked, or failed.

### Related Documentation

Do not read every document in `docs/` for every task. Use them selectively based on the work area:

- Read `docs/development.md` when working on local setup, Docker, Makefile commands, database setup, test commands, or developer workflow.
- Read `docs/ratings.md` before changing ratings calculations, adjusted stats, rating snapshots, ratings configuration, ranking logic, preseason blending, volatility, or the Rails/Python solver boundary.
- Read `docs/data-ingestion.md` before changing scraping, game imports, sync jobs, season bootstrap tasks, game finalization, team matching, deduplication, or any data pipeline behavior that affects `Game` or `TeamGame` records.

If a task spans multiple areas, read only the relevant docs plus the directly affected source files.

---

## Primary Goals

When working in this repo, optimize for:

1. Correctness of ratings, predictions, and data imports
2. Clear, maintainable Rails architecture
3. Fast iteration toward launch readiness
4. Traceable model outputs grounded in stored data
5. Avoiding over-engineering

Do not introduce speculative abstractions unless they directly simplify near-term development.

---

## Tech Stack

- Ruby on Rails
- PostgreSQL
- GoodJob for background jobs
- Python least squares solver invoked from Rails
- React via `react-rails`
- TailwindCSS
- Docker
- AWS ECS Fargate
- RDS PostgreSQL
- Terraform-managed infrastructure

---

## Domain Concepts

### Core Models

Important domain concepts include:

- `Game`
- `Team`
- `TeamGame`
- `TeamSeason`
- Rating snapshots
- Prediction snapshots
- Rating configuration / config hash
- Game predictions
- Adjusted efficiencies
- Adjusted Five Factors

Before changing prediction or ratings behavior, inspect the relevant models, services, and existing tests.

### Ratings

The ratings engine computes adjusted team stats using least squares. It includes:

- Adjusted offensive efficiency
- Adjusted defensive efficiency
- Adjusted pace
- Adjusted Five Factors
- Home court adjustment
- Season average anchoring
- Configuration-hashed snapshots

Ratings should be reproducible for a given configuration hash.

### Predictions

Predictions should be based on existing rating snapshots and model output. Do not invent stats or rely on unsupported assumptions.

Prediction logic may include:

- Expected offensive efficiency
- Expected defensive efficiency
- Expected pace
- Score projection
- Win probability
- Team-specific variance
- Prediction confidence
- Residual/evaluation diagnostics

---

## AI / GPT Product Direction

The future GPT interface should answer questions like:

- "Who is most likely to pull an upset today?"
- "Why does Team A match up well against Team B?"
- "Which games have the highest prediction confidence?"
- "Which team is vulnerable despite a strong record?"
- "What does the model think Vegas is mispricing?"

See GPT Integration Guidelines for grounding requirements.

---

## Development Principles

### Prefer Rails-native patterns

Use conventional Rails structure where possible:

- Models for persistence and simple domain behavior
- Services for orchestration and calculations
- Jobs for async/background workflows
- Query objects only when they reduce complexity
- Helpers/presenters for view formatting when useful

Avoid creating unnecessary framework layers.

### Keep services small and purposeful

Service objects should have a clear responsibility and a simple public interface, usually:

```ruby
SomeService.new(args).call
```

or

```ruby
SomeNamespace::SomeService.call(args)
```

Follow existing project conventions before introducing new ones.

### Favor explicitness over magic

This project involves statistical modeling and prediction logic. Prefer readable, explicit calculations over clever abstractions.

A future version of the project may need to explain model behavior to users, so code clarity matters.

---

## Testing Expectations

When changing behavior, add or update tests.

Prioritize tests around:

- Data import correctness
- Rating calculations
- Prediction calculations
- Snapshot creation
- Configuration hash behavior
- Edge cases involving missing ratings or incomplete game data

For model/math changes, include tests with simple inputs where expected outputs are easy to reason about.

Do not rely only on snapshot-style tests for calculation logic.

---

## Data Integrity Rules

Be careful when modifying:

- Rating snapshot schemas
- Prediction snapshot schemas
- Config hash generation
- Import scripts
- Historical game data
- Team identity / naming logic

Daily snapshots are important because they allow validation of model changes over time. Avoid destructive data migrations unless clearly necessary.

If changing config behavior, ensure old snapshots remain understandable.

---

## Python Solver Guidelines

The Python least squares solver is part of the core ratings pipeline.

When modifying it:

- Keep the Rails/Python boundary simple
- Validate inputs before calling Python when practical
- Preserve reproducibility
- Avoid introducing hidden state
- Return structured results that Rails can persist clearly
- Add logging/progress feedback for long-running calculations where useful

Do not rewrite the solver unless there is a clear correctness or performance reason.

Current specs stub the numerical solver. When changing the solver or the Rails/Python boundary, add or update and run a small deterministic check using the real solver with synthetic inputs and independently reasoned expected outputs. Exercise the boundary when it changes. Use Docker's Python/NumPy environment; do not import domain data or run a ratings backfill for verification. Passing hook suites alone does not establish numerical correctness.

---

## Background Jobs

The app uses GoodJob, backed by PostgreSQL.

When adding jobs:

- Make jobs idempotent when practical
- Log meaningful progress
- Handle partial failure cleanly
- Avoid duplicate imports or duplicate snapshot creation
- Keep long-running workflows observable

Prefer small orchestration jobs that call well-tested services.

---

## UI Guidelines

The current UI is intentionally lightweight.

Prioritize:

- Useful admin/debugging screens
- Clear tables
- Basic filters
- Model validation views
- Team pages
- Schedule pages
- Prediction dashboards

Do not over-invest in visual polish before the data and prediction flows are trustworthy.

TailwindCSS is available. Keep UI components simple and readable.

---

## Launch Priorities

The project should stay focused on launching a usable product ahead of the next March Madness.

Near-term priorities likely include:

1. Validate ratings and prediction accuracy
2. Improve model evaluation dashboards
3. Integrate Vegas odds
4. Add betting/value analysis service
5. Build GPT-ready query aggregation endpoints
6. Build the conversational UI
7. Add March Madness-specific tools
8. Add blog/content funnel if time allows

When choosing between two implementation options, prefer the one that gets a reliable version in front of users sooner.

---

## Coding Style

General preferences:

- Keep methods short when reasonable
- Use descriptive names
- Avoid clever metaprogramming
- Prefer plain Ruby objects for business logic
- Keep calculations easy to audit
- Do not hide important model assumptions
- Add comments only where they clarify non-obvious domain/math logic

This is a hobby project, but treat the model logic seriously.

Tiny gremlins in prediction code become giant gremlins in March.

---

## Commands

Use the repository's local workflow commands:

- `bin/test [RSpec arguments]`: Docker specs with a fresh disposable database and automatic cleanup.
- `bin/check`: native RuboCop, Reek, Brakeman and specs; Docker provides the disposable test database.
- `bin/dev`: foreground Docker development with automatic teardown on Ctrl-C.
- `bin/dev --detach` and `bin/stop`: explicit background development and cleanup when a task needs the app running.
- `bin/compose`: local Compose commands with the correct development overrides.

Tests do not need the development stack running. On a memory-constrained laptop,
avoid concurrent full suites or unnecessary development services. Do not run data
imports, ratings backfills, production restores, database resets or global Docker
prunes as routine setup or verification. Keep development data and cached images
when stopping services. See `docs/development.md` for first-time setup and details.

If a command fails because dependencies or environment variables are missing, report that clearly instead of guessing.

---

## Environment / Secrets

Never commit secrets.

Do not hardcode:

- API keys
- Database URLs
- AWS credentials
- OpenAI keys
- Odds provider credentials
- Production hostnames unless already configured safely

Use Rails credentials, environment variables, or existing project conventions.

---

## Infrastructure Guidelines

Infrastructure is managed separately with Terraform and AWS ECS Fargate.

Do not modify deployment infrastructure unless explicitly asked.

When working on deployment-related changes:

- Prefer small, reviewable Terraform changes
- Keep cost low
- Avoid managed services that significantly increase monthly spend
- Preserve the current goal of staying roughly under $500/year where possible

---

## GPT Integration Guidelines

GPT should not be treated as the source of truth.

The app should provide GPT with structured data from:

- Rating snapshots
- Prediction snapshots
- Team profiles
- Adjusted Five Factors
- Evaluation diagnostics
- Game context
- Odds data, when available

GPT responses should explain the model, not replace it.

When building GPT features, prefer endpoints/services that assemble grounded context first, then pass that context to the model.

All GPT-facing insights must be traceable to stored data. If the data does not support a claim or matchup narrative, say so clearly. Never treat betting recommendations as certainty.
