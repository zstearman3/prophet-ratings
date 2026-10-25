# Departure capture storage: implementation handoff with unresolved memory budget

Ticket: [Offseason performance 03](https://app.notion.com/p/40417d6b0c248146997af2db9f1dcc31).
Current branch: `codex/departure-capture-memory`.
Current worktree: `/Users/zachstearman/.codex/worktrees/departure-capture-memory/prophet-ratings`.
Development base: `405f557bea940492478e5e05989932c94da78db5`.
Resumed handoff HEAD: `cc7b7ddf790ee3e6fbacc1446994c62f2f0e2019`.

**AC2 remains failed.** The user has explicitly authorized a pushed branch and PR
with the unmet criterion disclosed. That exception does not mark the ticket
accepted or waive correctness, independent review/QA or final hook gates. The
coordinator owns publication and final gate records. No deployment, production
import, backfill or historical conversion was performed.

## Preserved implementation

- Six additive tables separate immutable content-addressed raw bodies,
  per-request observations, source normalizations/rows and annual datasets/rows.
- Acquisition checkpoints and successors retain references instead of copying
  base64 bodies. Exact bytes, digest, request/time and extraction provenance
  remain available through the existing private download flow.
- PostgreSQL JSON cursors fetch 250 rows; fixed SQL inserts preserve JSON numeric
  semantics. Annual CBBD derivation follows the existing rules one team at a time.
- Versioned readers preserve old HTML/JSON/base64 attempts and logical hashes.
  Publication keeps the logical dataset/report/team-input shape, replacing only
  raw evidence with references. No historical migration is shipped.
- Malformed source routing IDs remain explicit failures, and completion requires
  exact draft-pick membership. Existing regression coverage is preserved.
- The opt-in `departure_normalization` scenario retains the complete original
  legacy corpus and a separate five-response CBBD acquisition. Default scenarios,
  query caching, 250-row batches and container limits remain unchanged.

Read `docs/departures.md`, `docs/data-ingestion.md`, `docs/performance.md` and
`docs/development.md` for contracts and verification setup. Synchronous
review/publication memory optimization belongs to ticket 05.

## Resumed repairs

Two user-authorized memory repair cycles reduced duplicate metadata allocation:

- The offline legacy adapter removes each source tempfile after retaining its
  bytes/provenance, using the existing CaptureStore validation path unchanged.
- Annual settings are read after the lock reload. Nested metadata values use
  JSON's existing streaming generator, preserving canonical bytes and numeric,
  escaping, depth and nonfinite-value behavior.
- The offline benchmark clones the exact persisted manifest with a bound-ID
  PostgreSQL INSERT SELECT, deriving `plan = manifest - 'sources'`, then fetches
  a fresh lazy acquisition. One reload after the capture checkpoint discards save
  mutation snapshots before annual normalization.
- Benchmark results retain the scalar serialized job arguments. Scalar legacy
  stage counters identify clone, capture, dataset and checkpoint boundaries.

An additional explicitly authorized correctness repair propagates failed source
normalization status/failure into capture-only coverage evidence and returns rows
only from completed normalizations. Malformed/duplicate postseason rows cannot
masquerade as a successful empty response and suggest absent participation.
Acquisition remains incomplete, and no team/profile/rating/publication rows change.

## Final source-matched measurements

Both final runs used all 1,077 identical source-file hashes, verified against the
checkout at measurement time. Their recorded diff SHA256 is
`30d2c3d925a26e08bf77f905af3b327b1b65e825a1f8197f445eb72853ff7eef`.
Application and benchmark runtime source remained unchanged after freezing the
measurements. Reporting documentation and one spec-only telemetry fixture changed
afterward: the fixture initializes standard SQL counters for real SQL subscribers
and supplies synthetic memory scalars when native specs run outside Linux. The
real job, lock, source archive, stage and output assertions remain exercised.
These changes do not alter the measured workload.

| Whole-container worker peak | 1x bytes | 2x bytes | Growth bytes |
| --- | ---: | ---: | ---: |
| Legacy | 319,356,928 | 433,881,088 | 114,524,160 |
| CBBD | 231,456,768 | 231,694,336 | 237,568 |

Legacy 1x passes the 419,430,400-byte (400 MiB) ceiling. Legacy 2x is
413.781 MiB and exceeds it by 14,450,688 bytes. Legacy growth is 109.219 MiB,
exceeding the 52,428,800-byte (50 MiB) growth ceiling. CBBD passes both limits.
The complete 1x assertion command exited 0; 2x exited 1 with `pass: false` and
`errors: []`. Both legacy and CBBD jobs reached `performed` terminals with
`query_cache_enabled: true` and scalar `job_arguments: [1]`. Neither worker OOMed.

Legacy preserved exactly 8,030/16,060 school observations, 120,450/240,900 player
observations, 60 selections, and zero failures. Its exact original dataset digests
are `db165b07d5b1163364660c3e68a192925d51b6ef34e1cd2a4e9cfad23e0c4ea3`
and `4c1891622a9fe93b67a0dedae7d8b07b6d975e7bfe62a740875b22515954f08e`.
The separate CBBD path retained five responses, 365 teams, 60 picks and 10,950
player observations at each scale, with its digest checked against file replay.
PostgreSQL peaks were separately 1,586,356,224/2,770,911,232 bytes, with no OOM
in either final run and the unchanged 3 GiB cap. Application caps stayed 512 MiB
and 0.5 CPU. Existing local stacks were preserved; shared-host contention remains
uncontrolled.

At 2x, cumulative worker peaks were 179,240,960 bytes after cloning,
313,151,488 after captures, 404,918,272 after annual normalization and the same
after checkpointing. The acceptance peak was 433,881,088 after terminal
accounting/output. The last interval crossed 400 MiB; checkpoint counters do not
replace whole-container acceptance measurements. `DepartureNormalizationResult`
reads the full header to choose a provider and constructs source-ID query lists;
these are unproven allocation candidates, not an allocation profile or a fix.
No further repair was made after the authorized cycles.

Reproduction artifacts (ignored local files):

```bash
bin/benchmark-offseason --scale 2 --scenario departure_normalization --assert --output tmp/departure-ticket/resume-measured-normalization-2x.json
bin/benchmark-offseason --scale 1 --scenario departure_normalization --assert --output tmp/departure-ticket/resume-measured-normalization-1x.json
```

Final 2x owner `offseason-d27299acc1f11b95` ran 19:25:26–19:32:13 UTC;
1x owner `offseason-fcfc20afdc68ce9a` ran 19:32:36–19:36:54 UTC on 2026-10-25.
Matching logs are `resume-measured-{2x,1x}.log`, with per-owner commands,
fixture manifests, source hashes and telemetry alongside them. Owned Compose
projects/volumes and benchmark images were cleaned successfully.

Earlier evidence is retained separately and does not establish final acceptance:

- Original handoff legacy peaks were 404,721,664/536,870,912 bytes.
- First resumed 2x (`resume-normalization-2x.json`) completed with legacy peak
  500,490,240 bytes, before the second memory repair and correctness fix.
- `resume-final-normalization-2x.json` was intentionally interrupted during
  fixture construction to include the approved correctness fix before measuring;
  normal INT cleanup succeeded. It has no measured worker phases.
- `resume-verified-normalization-2x.json` failed fixture comparison when the
  isolated database was OOM-killed; no worker acceptance evidence was collected.
  Its owned resources were cleaned. The unchanged retry above completed all
  fixture stages and both measured phases. No limits or corpus were altered.

## Verification and remaining handoff

Focused final Docker command passed 66 examples, including capture-only failure
propagation, original routing/pick regressions, exact canonical JSON bytes,
source-file lifetime, exact clone semantics and serialized job arguments:

```bash
bin/test spec/services/departures/stored_dataset_spec.rb spec/lib/offseason_performance/departure_cbbd_content_spec.rb
```

Log: `tmp/departure-ticket/resume-correctness-green.log` (seed 12377).
Focused changed-source RuboCop and Reek checks passed; final test whitespace was
safely corrected by RuboCop afterward. The linked ticket's Implementation record
is the durable source for exact final broader-regression, required-hook,
independent review/QA and publication outcomes. Focused checks and benchmark
completion alone do not establish completion. The unmet legacy AC2 must remain
explicit in the PR and ticket; no passing acceptance or deployment is claimed here.
