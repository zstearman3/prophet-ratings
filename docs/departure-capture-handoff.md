# Departure capture storage: incomplete implementation handoff

Ticket: [Offseason performance 03](https://app.notion.com/p/40417d6b0c248146997af2db9f1dcc31).
Branch: `codex/departure-capture-storage`.
Development base: `405f557bea940492478e5e05989932c94da78db5` (dependencies #242 and #243 merged).

The user explicitly requested committing and pushing this incomplete work for a
fresh agent, without opening a PR. This supersedes the implementation skill's
normal publication gate for this handoff only. The ticket remains In progress.
This is not a completed implementation: AC2 fails. Do not infer acceptance from
a successful commit, push, ordinary tests or hooks. No deployment, production
import, backfill or historical conversion was performed.

## Implemented behavior

- Six additive tables separate immutable content-addressed raw bodies,
  per-request observations, source normalizations/rows and annual datasets/rows.
- New acquisition checkpoints and successors retain references instead of
  copying base64 bodies. Exact bytes, digest, request/time and extraction
  provenance remain available through the existing private download flow.
- PostgreSQL JSON cursors fetch 250 rows; fixed SQL inserts preserve JSON numeric
  semantics. Annual CBBD derivation reuses the existing rules one team at a time.
- Versioned readers preserve old HTML/JSON/base64 attempts and logical hashes.
  Publication retains the existing logical dataset/report/team-input shape and
  replaces only raw evidence with references. No historical migration is shipped.
- Source routing IDs are validated before partitioning; malformed IDs produce
  explicit failures instead of disappearing. Completion compares exact draft
  picks, not just selection count. These were independently reproduced defects
  and are now covered by committed regressions.
- An opt-in `departure_normalization` benchmark measures the exact original
  legacy corpus and a separate representative five-response CBBD acquisition.
  The default scenario list, original corpus and container limits are unchanged.

Read `docs/departures.md`, `docs/data-ingestion.md`, `docs/performance.md` and
`docs/development.md` for the implementation contracts and verification setup.
Synchronous review/publication memory optimization belongs to ticket 05.

## Final measured blocker

These measurements describe the application code in this handoff; this document
was added afterward. Both workers completed with correct replay digests, full
counts and query caching enabled. The 2x legacy run was not OOM-killed.

| Whole-container worker peak | 1x bytes | 2x bytes | Growth bytes |
| --- | --- | --- | --- |
| Legacy | 404,721,664 | 536,870,912 | 132,149,248 |
| CBBD | 238,092,288 | 234,270,720 | -3,821,568 |

Legacy fails both requirements: 2x peak must be at most 419,430,400 bytes
(400 MiB), and growth at most 52,428,800 bytes (50 MiB). The observed legacy
growth was 126.027 MiB. CBBD passes but does not replace the legacy growth proof.
Web peak was at most 168,054,784 bytes. PostgreSQL peaks were separately
1,596,895,232 and 2,766,458,880 bytes at its unchanged 3 GiB cap.

The full legacy workload processed 8,030/16,060 school observations and
120,450/240,900 player observations, preserving the original fixture digest at
each scale. Separate CBBD work processed five responses, 365 teams, 60 picks
and 10,950 player observations at each scale. Application limits remained
512 MiB and 0.5 CPU, with row batches fixed at 250.

## Remaining diagnosis and candidate repair

Confirmed code allocations, whose precise contribution to the peak is unproven:

1. `script/performance/departure_sources.rb`: `LegacyDepartureSources` retains
   every raw tempfile in an outer directory until the source phase ends, although
   bodies already exist in PostgreSQL. Consider a narrow exact-byte observation
   entry point in `CaptureStore` and retaining one source at a time. Keep every
   body, observation and source fact; do not reduce the fixture.
2. `app/services/departures/annual_row_writer.rb`: `@settings = record.header`
   occurs before `with_lock` reloads the record, retaining the old metadata tree
   while later reads can deserialize another. Obtain settings after locking.
3. `app/services/departures/dataset_stream.rb`: header values, including the full
   sources array, use `JSON.generate`. Stream these values while preserving
   canonical ordering, numeric semantics and exact logical hashes.

Temporary-file page cache is a plausible contributor, not a proven allocation
profile. Manifest copying in `LegacyDepartureNormalizationJob.attempt` may also
contribute. No candidate above has been implemented or proven to meet the limit.

Minor evidence issue: the scenario result omits `job_arguments` despite the
performance documentation's claim. `DepartureNormalizationDriver.call` returns
a merged hash while its caller keeps the original result. Source and tests prove
scalar IDs, but the artifact does not record their values. Preserve this
distinction when fixing the result or documentation.

## Verification and resumption

Before this handoff, the final targeted Docker command passed 329 examples:

```bash
bin/test spec/services/departures spec/requests/admin/departure_batches_spec.rb spec/requests/admin/departure_team_review_spec.rb spec/services/ingestion/cbbd/client_spec.rb spec/lib/offseason_performance
```

Affected RuboCop passed 45 files; Reek and Brakeman reported zero warnings.
Independent QA reran its three original regression probes successfully and
verified all 1,076 source hashes against both benchmark artifacts. Independent
code review cleared the correctness repairs. Overall QA failed AC2. Final hook
results for this publication are recorded in the ticket and handoff chat;
targeted checks alone do not replace either required hook suite.

The first full pre-push run for publication found one stale request-spec
assertion in `guided_departure_batches_spec.rb`: it read `production` directly
from the new dataset reference. The assertion now uses `RetainedEvidence` to
read the logical facts and still requires `team_points == 102`. This changes
only the test reader; application behavior and measured executable files remain
unchanged. The initial full run had 2,736 examples, one failure and 13 pending;
see the ticket for subsequent verification results.

The previous run used two shared repair rounds (plan corrections, then code/QA
correctness repairs) and stopped under the skill's limit. A fresh agent should
first re-read the ticket, current instructions and Git state, preserve this work,
and integrate current development non-destructively if following the resume
workflow. Focus on the measured memory failure; do not restart the whole design.

Add meaningful regression coverage for any changes, obtain focused independent
review/QA, freeze executable files, and run these measurements sequentially:

```bash
bin/benchmark-offseason --scale 1 --scenario departure_normalization --assert --output tmp/departure-ticket/normalization-1x.json
bin/benchmark-offseason --scale 2 --scenario departure_normalization --assert --output tmp/departure-ticket/normalization-2x.json
BUNDLE_WITHOUT=charts bundle exec overcommit --run
BUNDLE_WITHOUT=charts bundle exec overcommit --run pre_push
```

Require both absolute peaks and corresponding growth to pass with performed
terminals, complete original counts, exact replay digests and source-matched
artifacts. Do not force GC, disable query caching, increase caps or substitute a
smaller workload. Preserve admin authorization, provenance and all legacy hashes.

Detailed original logs, benchmark JSON, review reports and scratch plans remain
in ignored `tmp/departure-ticket/` in the original worktree; they are not included
in this commit. The Notion Implementation record and this document preserve the
essential remote handoff. Original worktree:
`/Users/zachstearman/.codex-workspaces/worktrees/ios-8c61e669-2a2e-4aa9-9042-42130bcd7993/prophet-ratings`.
