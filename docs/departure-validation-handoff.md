# Departure validation: unfinished handoff

Ticket: https://app.notion.com/p/40417d6b0c24818097c9ebb63dca2315

Branch: `codex/departure-validation-publish`
Base: `3e8163134c6861241f0430ae77198bbe00d36fa2`

This checkpoint is **unfinished** and is being committed/pushed at the user's
explicit request so another agent can continue. It is not a ready PR or a release.
The ticket remains In progress. The current handoff turn changes documentation
only; it does not start another implementation or performance round.

## Required outcome

Prepare and validate departures in bounded background work, persist facts and
reviewable proposals, record explicit approval of unchanged evidence, then publish
one revision and all profile pointers atomically. Review/status HTTP reads use
persisted projections and never replay annual sources.

Rows can be validated and staged incrementally. Uniqueness, complete pick coverage,
unknown versus verified-zero policy, team sums/common denominators, exact approval,
freshness and canonical hashes need shared checks. Use constraints, small indices,
aggregates, ordered streaming and a final batch seal. Atomicity requires a database
transaction, not the complete annual dataset in Ruby memory. No job-per-row design,
new generic framework, parser rewrite or ban on every bounded collection is required.
Keep existing formulas, immutable history, correction lineage, evidence downloads,
admin authorization and the automatic approval reason.

The ticket's 1x/2x performance limits remain unchanged: separate 512 MiB web/worker
caps, each peak <=400 MiB including children; cold GET <=3s, serial/status/queue
p95 <=1s, concurrency-3 GET p95 <=2s, first/last-ten median drift <=20 MiB, and
corresponding worker peak growth <=50 MiB when unrelated retained evidence doubles.
Use the original ticket-01 corpus, normal query caching and no forced GC.

## Implemented checkpoint

- Validation/proposal/approval records and prepare/publish HeavyJobs with scalar IDs.
- Actual retained-source authentication, row persistence and bounded metadata scans.
- Persisted review, manual decisions, source recovery/history and legacy proof.
- Locked dependency generation, exact immutable approval, idempotent atomic publication.
- PostgreSQL triggers for rejection/invalidation of timestamp-preserving SQL changes.
- Standard `structure.sql` schema/load tooling so fresh databases retain the triggers.
- Request-local label formatting that reduces representative allocation counts.

Current code still has simplification opportunities, not proven acceptance failures:
`JsonRows#read` holds/quotes one complete raw body; legacy HTML parsers hold a DOM;
`ProductionProjection` retains relevant team tables; `Preview` creates the report;
`TeamCoverage#stints` repeatedly builds temporary arrays; `PreparedPayload#metadata`
loads all team inputs; `BatchPage` loads complete report/choices and team objects.
Some full JSONB construction occurs in PostgreSQL. The benchmark payload oracle
loads a complete old snapshot in its separate driver. Do not present these as
atomicity requirements or as newly measured memory defects. Simplify only where it
removes a concrete maintenance/allocation cost while preserving results; do not
turn this ticket into an unrequested architecture rewrite.

## Existing verification

All evidence below predates the two portable handoff files; executable source is
unchanged. See [portable 1x evidence](evidence/departure-validation-1x.json).
The raw result/log and longer investigation notes remain in ignored
`tmp/departure-validation/` in the original task worktree, not in a fresh clone.

| Check | Observed result |
| --- | --- |
| Independent code and complexity review | Complete original 99-path diff; no material source findings remain |
| Independent guided/lifecycle/request QA | 22 examples, 0 failures, seed 18928 |
| Independent progress/setup QA | 25 examples, 0 failures, seed 40490 |
| `bundle exec overcommit --run` | Passed on original 99-path source |
| `bundle exec overcommit --run pre_push` | Reek, Brakeman and full RSpec passed on original source |
| SQL schema load and down/up parity | SHA256 `c1223e6d6e967a5e8664085acf684a8abb9666b1a7385fd20042573c98c46b85` |
| Final retained 1x scenario | Exit 0, all 9 phases passed, complete coverage, errors empty |
| 1x validation/publication whole-worker peaks | 225824768 / 227160064 bytes (215.363 / 216.637 MiB) |
| Maximum 1x web peak | 195309568 bytes (186.262 MiB) |
| 1x draft concurrent drift and p95 | 2998272 bytes (2.859 MiB), 0.160449s |
| Confirmation/revalidation p95 | 0.037009 / 0.047913s |
| Actual first publication | New revision, 365 profile pointers, exact original payload/hash oracle passed |
| Owned benchmark teardown/images | Both commands exited 0; no active benchmark remains |

The old 26.846 MiB draft-concurrent drift failed on an earlier source revision;
it is superseded for 1x by the passing result above. Earlier worker memory/growth,
web revalidation OOM and standalone CLI errors are preserved in local historical
notes; they are not automatic failures of this checkpoint. The early worker-only
2x feasibility run is **not** final integrated 2x evidence.

The portable JSON records a cryptographic manifest fingerprint for all 1133 measured files,
plus hashes for changed files and raw artifacts. Its source manifest excludes only
these two subsequently added documentation/evidence files. Compare content rather
than treating a new commit SHA alone as a runtime change. Documentation-only
handoff additions do not establish or invalidate runtime performance by themselves.
If source changes or required trace evidence is unavailable, identify that gap and
run only the relevant required measurements; never invent a final pair pass.

## Remaining work for a newly authorized agent

1. Read the current ticket and this checkpoint; inspect Git status and freshly fetch
   development. Follow the resumed-worktree integration rules without resetting or
   losing task work. Reuse this branch or branch from its verified remote tip;
   do not restart from development and reimplement the ticket.
2. Assess the implementation against the clarified requirements. Keep changes
   narrow and justified. Unchanged current checks are reusable; affected code
   changes require appropriate tests, both hooks and focused review/QA again.
3. Complete the final relevant 2x scenario and explicitly compare corresponding
   whole-container worker peaks against the applicable final 1x source. Verify
   source equivalence, all window completeness/limits and <=50 MiB growth. The
   current 1x pass alone does not close this gate. If development integration or
   runtime edits change the measured code, obtain final-source evidence as needed.
4. Obtain independent final QA of the acceptance matrix and performance evidence.
   Raw trace evidence is local-only; the portable JSON is a curated summary, not
   the entire sampler trace. State missing evidence rather than silently passing it.
5. Only after the remaining gates pass, open a ready PR against development and
   update the ticket to Testing. Do not merge, deploy, activate seasons, import or
   backfill domain data, or modify Terraform under this ticket.

Required commands use native Ruby and `psql` for hooks, Docker for disposable specs:

```sh
PATH=/opt/homebrew/opt/libpq/bin:$PATH BUNDLE_WITHOUT=charts bundle exec overcommit --run
PATH=/opt/homebrew/opt/libpq/bin:$PATH BUNDLE_WITHOUT=charts bundle exec overcommit --run pre_push
bin/benchmark-offseason --scale 2 --scenario departure_validation --assert --output tmp/departure-validation/final-2x.json
```

The Homebrew prefix is the original host's setup; follow `docs/development.md` on
another host instead of copying secrets or assuming that path. Keep full suites
and benchmark scales sequential. Do not run unrelated scenarios, imports, restores,
backfills or global Docker cleanup. The standard SQL dump has an empty EOF line;
required whitespace hooks pass. Do not weaken hooks or alter canonical dumps merely
to silence an optional `git diff --check` warning.

## Workflow record

Four planning revisions and nine supported repair rounds preceded this checkpoint.
Original risk was 7/10; final performance acceptance remains incomplete. The
implementer inherited the selected runtime model (identifier not exposed); separate
plan/code/QA reviewers used `gpt-6.1-sol` with medium reasoning. These review roles
were independent. A new agent should inspect their evidence and request focused
follow-up for changes, rather than automatically repeat every completed phase.

The last account snapshot exposed only a shared weekly window (19% used), not a
300-minute window. Numerical five-hour tracking and exact task attribution were
unavailable. No budget-compliance claim is made. The current user separately
requested a remote unfinished checkpoint; that authorizes this commit/push, not a
ready PR, completed ticket, merge or deployment.
