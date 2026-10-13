# Saved recruiting evidence

This adapter accepts reviewed saved UTF-8 JSON for **247 men's basketball Recruit
Composite, all conferences**. Transfer/Overall are unsupported. The explicit acquisition task can fetch public source pages. Preparation and
preview never fetch network data, create teams/aliases, write offseason profiles,
or run ratings.
Profile persistence and scoring are separate work. Rank is audit evidence, never
an invented score. Raw class points survive future scoring-curve changes.

Recruit year Y targets the stored ending-year Season.year Y+1 (2026 recruits
enter season 2027). Historical years use the same workflow. Prepare does not need
a database season; preview requires an explicit existing target season.

## Create the original file from 247 pages

Try bounded HTTP acquisition first (requires explicit category and both years):

```bash
bin/compose exec web bin/rails recruiting:acquire \
  SOURCE_YEAR=2026 YEAR=2027 CATEGORY=recruit_composite \
  OUTPUT_DIR=/rails/tmp/recruiting MAX_PAGES=20
```

`Recruiting::Acquisition` requests the annual page and follows its advertised
Load More links with a one-second pause, 30-second request timeout, no redirects,
and a configurable 1–100 page bound. `Recruiting::HtmlPage` reads the actual 247
ranking markup. No browser automation or challenge bypass is involved. The first
page must identify the correct year, Recruit Basketball Composite, canonical URL
and ALL conferences. Subsequent responses may be the observed row fragments;
their URLs must follow that first page's pagination chain. Wrong host/year/category/
conference URLs, cycles, missing structure and wrong-year team URLs fail.

The JSON output reports status, acquired rows, evidence directory and any pending
next URL. A page limit produces explicitly partial coverage with a pending URL;
no advertised next page does not independently establish annual completeness.
Access, network and parse failures exit nonzero, retaining available page/response
bytes in a `failed-*` directory. Failed evidence cannot be prepared or previewed
as a successful dataset. Inspect the report and use saved HTML when access fails.

### Saved-HTML fallback

Open the annual Recruit Composite ALL page in a browser and save its HTML source
to a local file. The initial source normally contains only the first 50 rows.
Copy the actual Load More URL (decode `&amp;` to `&`), open it, and save that response
as another HTML file. Repeat for desired pages. A rendered page saved after Load
More may contain more rows; inspect coverage and avoid saving those rows again in
another entry. Save HTML, not a screenshot or browser-generated plain text.

Create a small manifest listing saved files in pagination order. Paths must be
accessible in the container. For example, use checkout-local ignored `tmp/`:

```json
{
  "observed_at": "2026-10-11T00:00:00Z",
  "retrieved_at": "2026-10-11T00:01:00Z",
  "captured_at": "2026-10-11T00:02:00Z",
  "pages": [
    {
      "path": "/rails/tmp/247-page1.html",
      "url": "https://247sports.com/Season/2026-Basketball/CompositeTeamRankings/"
    }
  ]
}
```

Use actual observation/acquisition/capture times, not the example dates. Each page
may override these three timestamps when pages were captured at different times.
Append entries using their exact advertised URL, including query parameters;
skipped/out-of-order pages are rejected. One saved page is valid partial evidence.

```bash
bin/compose exec web bin/rails recruiting:acquire \
  SOURCE_YEAR=2026 YEAR=2027 CATEGORY=recruit_composite \
  PAGES_PATH=/rails/tmp/pages.json OUTPUT_DIR=/rails/tmp/recruiting
```

Both paths create `original.json` and the normalized evidence bundle directly:
use the reported directory with `recruiting:preview`. No hand transcription of
team rows is required. Success is unreviewed acquisition, not operator approval.

The bundle snapshot is `raw_html_bundle`: a JSON container of exact page bytes
encoded as base64 with per-page SHA-256, URLs and timestamps. Decode `html_base64`
with `Base64.strict_decode64` to recover original HTML bytes. The bundle hash is a
hash of that container, while each page hash is a hash of its raw bytes. Exact DOM
team link text is retained in `raw_team_label`; surrounding layout whitespace is
stripped in `team_label` for exact canonical/alias lookup. Displayed numeric strings
are preserved without recalculating points. Source update text is retained per
page, with `source_as_of` left null because its displayed timezone has not been
independently verified. Capture time is never substituted for source availability.
No profiles, teams, aliases, ratings or snapshots are written.

## Prepare an annual extract

For an existing reviewed JSON transcription, the original prepare path remains
available. HTTP access has varied between 403 and 200; unattended acquisition
is not a delivery requirement. Visible pages have
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
- `snapshot_kind`: `raw_html`, `raw_html_bundle` or `factual_transcription`; `snapshot_location`:
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

`bin/test spec/services/recruiting spec/tasks/recruiting_spec.rb` covers the source
parser, stubbed HTTP failures/pagination, saved-file acquisition, JSON preparation
and identity preview. JSON fixtures are synthetic; reduced HTML fixtures retain
observed 247 markup and factual rows from a public 2026 page capture. These are
parser examples, not approved annual evidence. Automated tests make no network
calls or domain imports and perform no ratings or solver changes.
