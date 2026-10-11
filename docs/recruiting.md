# Saved recruiting evidence

This adapter accepts reviewed saved UTF-8 JSON for **247 men's basketball Recruit
Composite, all conferences**. Transfer/Overall are unsupported. It never fetches
network data, creates teams/aliases, writes offseason profiles, or runs ratings.
Profile persistence and scoring are separate work. Rank is audit evidence, never
an invented score. Raw class points survive future scoring-curve changes.

Recruit year Y targets the stored ending-year Season.year Y+1 (2026 recruits
enter season 2027). Historical years use the same workflow. Prepare does not need
a database season; preview requires an explicit existing target season.

## Prepare an annual extract

An operator acquires and reviews the source pages outside this adapter. Direct
fetch has returned 403; unattended scraping is not required. Visible pages have
50 rows: review every desired page and describe actual coverage. Do not claim a
complete annual dataset from the first page. Omitted teams remain unknown.

Use `spec/fixtures/recruiting/partial.json` as a **synthetic contract example**, not
publishable evidence. Required metadata:

- `provider: "247sports"`, `category: "recruit_composite"`, `conference_scope: "all"`,
  integer `source_year`, integer `target_season`, `source_status: "ok"`.
- `source_url`: `https://247sports.com/Season/Y-Basketball/CompositeTeamRankings/`.
- `source_as_of`: source-published ISO8601 timestamp with timezone or null.
  Null requires nonempty `source_as_of_reason`. Never substitute capture time.
- `observed_at`, `retrieved_at`, `captured_at`: explicit ISO8601 timestamps with
  timezone, describing source observation, acquisition and saved-file capture.
- `snapshot_kind`: `raw_html` or `factual_transcription`; `snapshot_location`:
  original evidence location/reference; `extraction_version: "247-recruit-json-v1"`;
  `coverage_note`: pages/rows actually reviewed and any omitted scope.
- `rows`: array, possibly empty. Each row requires exact `team_label`,
  `provider_team_id`, `team_url`. Optional displayed `rank`, `class_points`,
  `average_rating`, `commit_count` are null/absent when not supplied. Preserve decimal
  points/rating as decimal strings for precision. Rank is a positive integer;
  commits are a nonnegative integer; other numeric fields must be finite and
  nonnegative. Preserve zero explicitly. Do not invent missing values.

A failed acquisition must not produce `ok` with empty rows. Use a non-ok
`source_status` (e.g. `access_failure`, `network_failure`, `parse_failure`); prepare
rejects it distinctly from valid empty coverage. Unrecognized/malformed JSON and
missing/unreadable files also fail. The adapter cannot independently authenticate
an operator's transcription, review identity, timestamps or source availability.

```bash
bin/compose exec web bin/rails recruiting:prepare \
  EXTRACT_PATH=/path/2026-recruit.json SNAPSHOT_PATH=/path/saved-source \
  OUTPUT_DIR=/path/recruiting-evidence
```

Paths must be accessible in the container; use a bind-mounted checkout-local
ignored directory such as `tmp/`. Keep durable reviewed evidence elsewhere with
backups. Do not commit annual evidence or secrets as part of this command.

Prepare prints a content-addressed bundle directory. It retains exact `original.json`
and `snapshot` bytes, plus `dataset.json` normalized rows, metadata, original labels,
provider identities, exclusions and both SHA-256 hashes. The dataset revision binds
both files; changing either creates a separate bundle. Reruns reuse identical
bundles, verify integrity and never overwrite an existing revision. The hash of a
factual transcription is **not** a hash of raw HTML. Capture time never proves
historical pregame availability. Invalid rows are retained with exclusions so a
partial acquisition is auditable; they cannot become eligible through matching.

## Preview identities and coverage

```bash
bin/compose exec web bin/rails recruiting:preview \
  YEAR=2027 DATASET_DIR=/path/recruiting-evidence/<dataset-revision>
```

Preview verifies bundle integrity and emits deterministic JSON for unchanged files
and database identities. Exact canonical `Team.school` and exact `TeamAlias.value`
with source `247sports` are combined; only one distinct stored team resolves.
No nickname, fuzzy matching, first-match choice or automatic creation occurs.
Unmatched/ambiguous rows list candidate IDs and review actions. Explicitly reviewed
source aliases can be added in the normal admin/console workflow and then reused;
this task never modifies them. A canonical/alias conflict requires deliberate
identity correction before rerunning.

All rows sharing a label, provider identity or canonical team ID are excluded,
even if their points agree. Resolve the extract/aliases deliberately rather than
silently merging conflicting evidence. Missing points, explicit zero and invalid
points have separate row-number lists. Coverage reports actual extracted/eligible
counts and omitted stored team IDs; stored teams are **not** proof of annual
participation. Coverage is conservatively `partial` (or `empty`), never inferred
complete. No omitted team receives zero. Nullable inputs remain unknown even if
identity resolves. Inspect every exclusion and the source coverage note.

## Pin an operator review

After reviewing the preview and evidence, save a separate approval JSON:

```json
{
  "dataset_revision": "<from-preview>",
  "mapping_revision": "<from-preview>",
  "approved_by": "<operator identity>",
  "approved_at": "2026-10-10T20:00:00Z"
}
```

```bash
bin/compose exec web bin/rails recruiting:preview YEAR=2027 \
  DATASET_DIR=/path/recruiting-evidence/<dataset-revision> \
  REVIEW_PATH=/path/approval.json MAPPING_DIR=/path/reviewed-mappings
```

This saves an immutable mapping report with approval identity/time, separately from
the immutable dataset. Approval pins the exact current preview, including exclusions;
it does not approve omitted/invalid evidence or make it complete. Database alias/
team/coverage changes alter the mapping revision and reject stale approval. Keep
old mapping reports and obtain a fresh review. Identical approvals reuse files;
conflicting approvals cannot overwrite one revision. Identity for a future profile
input is provider/source_year/category/canonical_team_id plus the reviewed revision;
there is no profile importer in this task. A preview without an approval remains
`unreviewed`. The approval records operator assertions, not external authentication.

## Verification

`bin/test spec/services/recruiting/dataset_spec.rb spec/tasks/recruiting_spec.rb`
uses synthetic rows shaped to the approved source contract; no real annual data,
network calls, imports, ratings, snapshots or solver changes are involved.
