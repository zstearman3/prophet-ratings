# Annual drafted-player departure inputs

New acquisitions use CBBD exclusively. Draft year Y requires prior college season
ending Y and target Season.year Y+1. This workflow acquires and reviews annual
inputs; it never creates player/team identities, runs ratings, activates a season,
or imports/backfills game data. A general local player/stat store is future work.

## Saved admin workflow

From **Offseason setup → Review departure batches**, select a target season with
prepared team memberships. The browser derives the years: target season ending
2026 uses the 2025 NBA draft and college season ending 2025. Select **Fetch draft
and college stats** to create a saved batch and queue its first bounded capture in
one action. Viewing or refreshing a page never creates a batch or fetches data.
Request/retry limits are under **Advanced settings**; no coverage assertions are
required before seeing the sources.

Set `CBBD_API_KEY` in the worker's runtime environment (locally in ignored
`.env.docker` when needed). Never put the key in preparation, job arguments, source
files or logs. Run the existing GoodJob worker and refresh the batch page to check
its queued/running/failed status. Web-only startup leaves the capture queued.

A successful raw capture displays **Confirm draft results and college teams**.
Review the drafted players and their matched college teams, then check the single
confirmation and select **Publish departure inputs**. Pick numbers are displayed
as source data, not entered or separately certified. There are no completed-season
attestations, no-postseason checkboxes, accounting categories or evidence forms.
Production and lost-points shares are calculated automatically from CBBD.

Players without a match to a team with a prior-season `TeamSeason` are shown as
**Skipped**. This includes international/lower-division players and teams outside
the tracked prior season. Skipped players do not make other teams' estimates
unknown. **Stats unavailable** means a matched college player's production is
incomplete; only that team's estimate remains unknown. Use **Correct a college
team mapping** if a mapping is wrong, then refresh the review.

Viewing the page does not save decisions, publish inputs or call CBBD. The final
confirmation creates a new immutable attempt from the same retained bytes,
freezes the prior-season membership/mapping scope and calculated decisions, and
publishes through the existing input-import transaction. A stale review is
rejected if evidence, relevant membership, mappings or publication state changed.
Published results stay frozen. No ratings job runs automatically.

Use **Fetch sources again** only when updated responses are needed. Source
downloads, previous attempts and the HTTP ledger remain under **Source details
and attempt history**. Failed or malformed sources remain blocking and are never
treated as zero. Existing manually prepared strict-v1/v2 file/API workflows and
historical HTML review retain their original contracts; the simplified browser
flow uses extraction `cbbd-draft-season-totals-v4`.

The five generated logical requests are:

- `/draft/picks?year=Y`
- `/stats/player/season?season=Y&seasonType=regular`
- `/stats/player/season?season=Y&seasonType=postseason`
- `/stats/team/season?season=Y&seasonType=regular`
- `/stats/team/season?season=Y&seasonType=postseason`

No athlete/team/conference filter can hide another prior-season stint. Final
regular/postseason scopes exclude preseason/exhibitions. Provider query semantics
were inspected against CBBD upstream revision `6533aca`; authenticated annual
coverage has not been verified by the synthetic test suite.

One finite request budget (1–100, default 15) covers all endpoints and retries.
Retries per source are 0–5 (default 2); retry delays are bounded at 30 seconds.
The shared CBBD transport uses a 30-second request timeout. Missing credentials,
authentication/quota/HTTP/transport errors, malformed JSON/envelopes and incomplete
coverage remain explicit. There is no NBA or school HTML fallback.

Attempts retain every response before proceeding, including failed retries, plus
request filters, timestamps, status, rate-limit headers, redaction status and
content hashes. The source rows reference the selected terminal response; an
initial failed retry does not invalidate a later successful selected response.
The response ledger and selected sources are both replay-validated. Response bodies
have any echoed credential redacted before retention; hashes cover those retained
bytes, and `sanitized` records that fact. Provider publication time remains unknown
unless supported explicitly; capture time does not prove pregame availability.

Queued/running/completed/incomplete/failed states are separate from approval.
An atomic job claim prevents duplicate delivery from starting a second request
budget. A running duplicate is a no-op. After confirming the worker was
interrupted, use **Close interrupted attempt and retry** to retain a failed
predecessor and queue a new bounded successor. Do not use that control for a
worker still acquiring. A closed attempt cannot overwrite its immutable evidence.
Failures/earlier attempts are never relabelled or erased.

## Review identities, scope and missingness

Every returned draft selection remains visible with its source name, affiliation,
pick/round and provider IDs. The browser's single confirmation approves this
returned player list and college matching. The application trusts the captured
CBBD snapshot for this estimate; it does not claim an independently certified
final draft or completed season. An empty draft response is not publishable.

V4 matches exact CBBD athlete IDs to captured prior-season player/team rows and
existing `TeamExternalIdentity(provider: cbbd, external_id: teamId)` mappings.
When the draft athlete ID is null, a unique normalized full-name match within the
same CBBD college may propose an existing captured athlete ID. The UI identifies
that match method and retains the original draft row/nullable ID. Ambiguous names
or contradictory nonnull IDs are not silently replaced. No new players, teams,
aliases or provider identities are created here.

Only matches to teams with a prior-season `TeamSeason` affect the model. That
scope is frozen with the reviewed input; scoring does not consult transient
membership state. Rows outside it use the automatic scoped `outside_prior_season`
decision and appear as **Skipped**, without a global unknown penalty.

The loss remains sum of drafted players' reported points / independent team
season points. Full-roster differences are informational warnings, with neither
reported value adjusted. Null/missing points for a matched player or a missing
team denominator remain unknown; known subtotals are never extrapolated. The sum
of included drafted points cannot exceed the common team denominator.

Regular and postseason totals are combined automatically. When both postseason
requests succeed and neither contains a team's production, v4 treats that team as
having no additional postseason production. This is an explicit provider-data
assumption, not an operator certification. A failed request never establishes
absence. Under v4, a player absent from successful postseason responses contributes
no additional postseason points, even when the team played postseason games.
Their observed regular-season points remain included against the full regular-plus-
postseason team total. No synthetic player row is created. Explicit null points
or missing regular-season player rows remain unknown. Zero-point players with
observed participation remain eligible.

Invalid/fractional/negative points or games, duplicate keys, wrong years,
conflicting labels, nonfinite minutes and inconsistent denominators remain hard
failures. Team game-clock minutes are audit-only, not player-minute denominators.
Integral numeric values normalize to integers; original JSON remains retained.

Earlier extraction v1 retains strict roster reconciliation. Extraction v2 retains
its informational reconciliation warnings plus explicit reviewed scope/absence
requirements. Extraction v3 retains its original requirement for a player row in every observed
team scope. Saved evidence and frozen scoring results remain unchanged.
Legacy/manual reviews keep their explicit categories, reasons and gap approvals;
the current browser review does not ask operators to fill those fields.

Review fingerprints retain the normalized dataset revision and exact approved
choices. Background validation authenticates all retained source bytes and facts,
then seals its certificate and team proposals against the dependency generation.
Publication checks that certificate under the shared generation lock, streams the
canonical payload and evidence hash, and verifies the actual persisted payload
before committing all profile pointers. It does not replay the raw source parser.
Failures preserve current inputs; identical publication retries return the same
revision. Corrections create a new draft for fresh results/team confirmation
without replacing earlier evidence. A failed manual proposal keeps bounded captured
selection rows available for editing and fresh validation.

## Retention and compatibility

Private PostgreSQL attempts retain JSON response bytes and their ledger. Include
these attempts and immutable published revisions in private backups. Downloads
are admin-only `text/plain` attachments with the original source-kind extension;
response content is never executed as app HTML.

Raw browser captures use `draft-departures-capture-v1` and are not independently
publishable. The results/team confirmation creates a `draft-departures-v2`
successor with extraction `cbbd-draft-season-totals-v4`, typed provider identities,
the frozen rating scope and retained source bytes. Earlier extraction v1/v2/v3
remain supported. Normalized annual inputs are the seam a future local stat store
can supply. Scoring captures retain schema/extraction/provider identity; missing
schema means historical v1, which cannot contain provider identities. Review,
publication and scoring never fetch live sources.

Historical `draft-departures-v1` / `nba-results-sidearm-totals-v1` manifests,
HTML parsers, reviews, published revisions and frozen scoring outputs remain
unchanged and deterministically replayable. Their original provider URLs and
source-scoped aliases remain valid historical identities. New HTML acquisition is
rejected before HTTP. An existing historical draft/correction can still retain
unchanged saved HTML through its original recovery form (5 MiB maximum), with
actual original URL, status and capture metadata. This creates a successor and
reuses the historical parser; it is not a new-run fallback. Wrong-season/blank or
unsupported files remain failures. Never rewrite old manifests or revisions.

## CLI acquisition and offline replay

The browser is the normal workflow. File callers may prepare a CBBD plan with
`provider: cbbd`, `schema: draft-departures-v2`,
`extraction_version: cbbd-draft-season-totals-v1`, explicit integer years,
`expected_picks` (array of actual integer picks), `scope_evidence`, `max_requests`
and `retries`. Optional `absent_postseason_team_ids` is an array of reviewed exact
provider IDs. Endpoints/filters are generated by the server; legacy source URLs
cannot enable new HTML acquisition.

Run in the intended Rails environment, through an already running isolated stack
if appropriate (`bin/compose exec web` before `bin/rails`):

```bash
bin/rails departures:acquire PLAN_PATH=/artifacts/plan.json OUTPUT_DIR=/artifacts/draft-capture-1
bin/rails departures:replay CAPTURE_DIR=/artifacts/draft-capture-1 DATASET_PATH=/artifacts/draft-capture-1/dataset.json
bin/rails departures:preview CAPTURE_DIR=/artifacts/draft-capture-1 DATASET_PATH=/artifacts/draft-capture-1/dataset.json REVIEW_PATH=/artifacts/review.json
```

Acquisition requires a new private directory. It retains `<sha256>.json` bodies,
`manifest.partial.json` checkpoints, final `manifest.json` and `dataset.json`.
Keep them in durable private storage outside ephemeral containers and Git.
Interrupted checkpoints preserve responses already received; inspect them and
start a successor directory rather than relabelling the interrupted capture.
The command exits nonzero on unresolved selected failures. A successful fetch
still requires review of actual pick coverage and production completeness.

Replay accepts both explicit v2 JSON and historical v1 HTML contracts, verifies
content-addressed locations/hashes/metadata and produces deterministic annual
inputs. Identical output is a no-op; changed existing output is refused. Preview
replays and compares the saved dataset before applying an optional reviewed file;
it exits nonzero for incomplete coverage. Neither command requests credentials or
performs HTTP/database publication.

A reviewed file retains the existing approval shape (`revision_id`, exact
`dataset_revision`, `reviewed_by`, ISO-8601 `reviewed_at`, `decision: approved`,
`decisions`). V2 eligible stints carry `provider: cbbd`, integer
`provider_athlete_id`/`provider_team_id`, `production_key: cbbd/team/ID`, existing
local `team_id` and captured `identity_evidence_source_ids`; they never fabricate
player URLs. The saved dataset/review and all retained responses are required for
offline import. Historical files keep their original URL/source-ID fields.

Published draft/team pages read a compact SQL projection of the frozen revision.
They do not load acquisition response bodies, replay source captures, or deserialize
raw scope rows just to display results. The immutable revision and retained-source
downloads remain unchanged; publication and corrections still validate full evidence.

## Capture storage and bounded normalization

New browser acquisitions use `departure-captures-v1`. PostgreSQL stores exact
credential-sanitized response bytes once per SHA256 in `departure_source_captures`.
Immutable `departure_capture_observations` retain each response's original
acquisition, ledger ID, request, timestamps, HTTP outcome and extraction version;
identical bytes from different requests share the body without sharing provenance.
Selected source IDs point to the original observation. Checkpoints insert only
new observations/bodies and atomically update the attempt's small reference map.
Successors, corrections and published revisions retain those references. All
existing private-download authorization and attachment behavior applies.

Source normalization uses parser `departure-source-rows-v1`, keyed by content,
source kind, year and logical request/scope. It retains ordered original rows and
indexed team/athlete identities. PostgreSQL's native `json` parser uses one
transaction-scoped cursor and fetches **250 objects** at a time; arrays with
non-object elements, malformed/trailing JSON and non-array envelopes fail
explicitly. JSON fact columns preserve raw numeric semantics for logical hashes.
Bounded fact inserts preserve database uniqueness/foreign-key constraints without
retaining an Active Record object for every annual output row in a transaction
or association cache. A source is usable only after its normalization completes. Interrupted work
cannot certify complete coverage or zero production; explicit retry replaces
incomplete rows without renewing an acquisition's request budget. Duplicate
athlete/team identities across batches remain failures. Capture-only coverage
readers retain normalization failures and expose rows only from completed sources;
failed postseason parsing cannot become evidence of absent participation.

Pre-release development normalizations created before the quoted-JSON whitespace
fix can contain squished string facts under the same `departure-source-rows-v1`
identity. Completed rows are reused, so this fix neither repairs nor detects those
self-consistent old facts; digest checks still reject later row corruption.
Verification of the fix uses fresh disposable databases. Storage is unreleased;
there is no parser-version bump or automatic rewrite of existing evidence.

Annual derivations are keyed separately by the frozen manifest/extraction policy.
They process one provider team at a time with the existing reconciliation and
production rules. Capture-only attempts do not freeze strict reconciliation for a
later automatic policy. Attempts store a small `departure-dataset-v1` reference,
revision digest and summary; ordered normalized records reconstruct the exact
logical dataset. Canonical hashing streams records without assembling an annual
production array. Browser review and publication use bounded persisted projections. Explicit background
validation authenticates every retained retry/selected byte, freshly parses every
successful source, and recomputes annual results before any approval can publish. Published payloads
keep full logical dataset/report/team inputs for existing readers, replacing only
the raw evidence envelope with immutable observation references.

Legacy HTML/JSON/base64 evidence and original revision payload/hash contracts are
retained. File readers/exports may expand a logical dataset; ordinary browser GETs
never invoke replay or create temporary source files. There is no historical
conversion or automatic rewrite. Backups must include captures, observations,
normalizations, validation/proposal/approval tables and acquisition/revision rows.

### Background validation and approval

Acquisition completion queues `PrepareDepartureValidationJob` on the existing
`heavy` queue. Acquisition is not approval. Old batches show their historical
report and downloads with **validation needed** until an operator explicitly
requests validation. Refreshing review, progress or offseason setup performs
bounded persisted reads and never queues a fallback replay.

Validation records move through queued, running, ready, failed or stale. A ready
record contains every pick, unknown/verified-zero accounting, all target-team
inputs and the exact proposed review choices. Manual decisions use searchable,
paginated captured-player choices and paginated source choices; existing selected
choices remain visible across pages. Saving decisions, source recovery or advanced
coverage creates fresh validation work and clears approval. Original acquisition
bytes remain immutable. Saved HTML recovery checks the original URL and capture
metadata, retains a successor, then authenticates all sources before storing its
new dataset reference. Correction drafts copy retained JSON inside PostgreSQL and
preserve the published predecessor.

Approval records the authenticated user, one timestamp, exact decision document
and canonical review hash. No typed approval reason is required. The confirmation
request queues only a scalar approval ID. A capped `PublishDepartureValidationJob`
then rechecks the certificate and predecessor and writes the complete original
payload, canonical input hash and every target profile pointer in one transaction.
Failed publication rolls back every output and retains a visible error; **Retry
approved publication** uses the same immutable approval. Revalidate after changed
inputs. Duplicate delivery of an already published approval returns its original
revision and cannot rewind later correction pointers. GoodJob interruptions remain
visible; close a validation only after verifying its worker was interrupted.

The certificate uses a conservative database generation, not a TTL or supplied
hash. Durable PostgreSQL triggers invalidate it for supported and direct-SQL edits
to acquisitions, mappings, memberships, profile/revision inputs and completed
normalized facts, including unchanged-timestamp edits. Unrelated edits in those
tables can therefore require revalidation. The worker records generation before
parsing and compares under the same row lock used by invalidation triggers; that
lock is held through sealing/publication commit, while lengthy parsing runs
without it. Pending normalization headers, contracts and source IDs use exact JSON
representation comparisons, including integer/float changes. Proposal ownership
and content are write-once from insertion, and only target-season members may
receive proposals. Sealed approval and dataset-row artifacts cannot be edited
or unsealed by changing operation status. Operation batch/acquisition/version
identity is immutable from creation. Approval uses a nonblocking generation lock
and returns an explicit retry response when publication is busy; duplicate queued
approval returns promptly.

Historical validation also checks the retained published revision itself through
exact persisted JSON comparison and bounded canonical hashing. Valid acquisition
bytes do not certify an independently corrupted historical payload/input hash.
Integer versus float representation and array order remain significant to the
original canonical hash. Failed or stale history stays visible and downloadable;
no GET silently upgrades it or treats absent evidence as verified zero.

These durable triggers require SQL schema dumps (`db/structure.sql`); use normal
Rails `db:schema:load`, which dispatches to SQL format. See
[development setup](development.md) for PostgreSQL client prerequisites. Offline
legacy APIs remain compatible; browser validation and publication preserve the
original full dataset/evidence/report/team-input payload for downstream readers.

The complete legacy 1x/2x feasibility pair passed the 400 MiB worker peak and
50 MiB growth limits with ordinary query caching and no forced GC. The final
`departure_validation` benchmark additionally exercises old/new review GETs,
progress and forty distinct real approval requests; see [performance](performance.md).
