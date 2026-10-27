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

After acquisition finishes, the worker queues durable validation. Validation
rechecks retained bytes, calculates the existing rules and saves a compact report,
choices and exact per-team proposals. **Validation queued**, **Validation in
progress**, **Validation failed**, **Validation stale** and **Validation ready**
are distinct from acquisition and approval. A ready result displays
**Confirm draft results and college teams**.
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

Viewing the page or status endpoint reads saved projections only: no parser,
retained response replay, annual dataset expansion, job enqueue or CBBD call.
The final confirmation records the authenticated admin ID/email, one timestamp
and the exact signed proposal, then queues publication. No typed approval reason
is required; the revision records `Approved by admin` automatically. Source or
participation evidence and substantive correction reasons are retained separately.
The publication worker freshly authenticates actual retained content and the
sealed proposal under locks, then atomically saves the revision, every profile
pointer and the batch result. A stale review is rejected. Publication failures
preserve current inputs; retry the existing approval when offered, or explicitly
validate again. Published results stay frozen. No ratings job runs automatically.

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

Validation certificates use the application's message-verifier secret and bind
exact saved reports, choices, per-team proposals, source artifacts and compact
domain dependencies. Preserve that secret across web and worker processes; a
secret change requires fresh validation. Supplied hashes alone are not authority.
Web currentness checks compact domain identities; actual source bytes, complete
plans and annual facts are reauthenticated only by workers before publication.
Canonical payload hashing streams the unchanged logical dataset contract.

Missing or failed draft proof has an explicit **Validate retained evidence**
action. Confirm an interrupted validation only after checking that the worker
stopped; a live worker rejects interruption recovery promptly. Manual decisions
use captured player/source pages and read-only numeric facts. Saving decisions,
source coverage or historical HTML recovery queues fresh validation, never
approval. Failed manual choices remain editable from previously captured rows.
Corrections copy retained evidence in PostgreSQL and queue validation without
replacing earlier attempts. Historical unsigned published reports remain readable
but setup reports review needed; select **Revalidate retained evidence in a correction** to queue retained evidence
with an automatic reason, then explicitly review and approve the fresh proposal.
A deliberate substantive correction can still retain its own reason. Source/history lists are paginated, and all original sources remain
available as private downloads.

## Retention and compatibility

Private PostgreSQL attempts retain JSON response bytes and their ledger. Include
these attempts and immutable published revisions in private backups. Downloads
are admin-only `text/plain` attachments with the original source-kind extension;
response content is never executed as app HTML.

Raw browser captures use `draft-departures-capture-v1` and are not independently
publishable. Validation proposes `draft-departures-v2` with extraction
`cbbd-draft-season-totals-v4`, typed provider identities and frozen rating scope;
confirmation approves that exact result. The original acquisition is preserved. Earlier extraction v1/v2/v3
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
production array. Browser review uses only persisted compact facts. Validation authenticates all
retained retry/selected bytes and derives annual rows in bounded worker batches;
publication verifies actual retained artifacts and staged annual facts before
applying inputs. Published payloads
keep full logical dataset/report/team inputs for existing readers, replacing only
the raw evidence envelope with immutable observation references.

Legacy HTML/JSON/base64 attempts and revision hashes keep their original reader
and file replay path. No historical conversion or automatic rewrite occurs, and
no production conversion command is provided. Backups must include the new
capture, observation and normalization tables together with acquisition/revision
rows; the additive migration must run before new acquisitions. Source bodies are
private evidence, not disposable cache entries. Database deletion constraints and
immutable models preserve acquisition provenance.

Row transfer batches are bounded, but the full legacy normalization benchmark
still exceeds its 400 MiB peak and 50 MiB growth budgets at 2x; see
`docs/departure-capture-handoff.md` for final source-matched evidence. Legacy synchronous file/API review and export can still expand logical datasets.
The durable browser lifecycle uses scalar-ID HeavyJobs and bounded worker streams.
Early 1×/2× worker phases passed their memory gates; final integrated browser HTTP
performance has not been measured on this source. No new benchmark cycle was run
for this browser integration.


## Durable worker operations

Run the additive `20261027020000` validation migration before using this lifecycle.
Back up `departure_validations`, `departure_proposals` and `departure_approvals`
with the existing source, normalization, batch and revision tables. Both web and
GoodJob workers need the same application secret and migrated schema. HeavyJobs
receive only operation/approval IDs. Acquisition never creates an approval.
Worker locks use a fixed table order; browser mutations use a short timeout and
return an actionable busy response instead of waiting behind heavy publication.
Exact duplicate publication deliveries return the original retained result.
