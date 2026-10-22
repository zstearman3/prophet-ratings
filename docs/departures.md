# Annual drafted-player departure inputs

New acquisitions use CBBD exclusively. Draft year Y requires prior college season
ending Y and target Season.year Y+1. This workflow acquires and reviews annual
inputs; it never creates player/team identities, runs ratings, activates a season,
or imports/backfills game data. A general local player/stat store is future work.

## Saved admin workflow

From **Offseason setup → Review departure batches**, select a target season with
prepared team memberships. Save the explicit draft/prior/target years, actual
expected picks (omit rescinded picks), and reviewed final-scope evidence. Do not
assume every draft has 60 picks. No URLs, HTML uploads, JSON plans or hashes are
needed for a new browser batch.

Set `CBBD_API_KEY` in the worker's runtime environment (locally in ignored
`.env.docker` when needed). Never put the key in preparation, job arguments, source
files or logs. Run the existing GoodJob worker, then queue acquisition and refresh
status. The five generated logical requests are:

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

Every parsed actual pick in both rounds remains visible with its original name,
affiliation, pick/round and nullable provider IDs. CBBD `athleteId` joins exactly
to all captured prior-season player/team rows. Names and affiliation alone never
establish player identity. `sourceTeamCollegeId` is distinct from the draft source
team's own ID. Missing athlete/team identities remain unknown.

Eligible stints require exact existing `TeamExternalIdentity(provider: cbbd,
external_id: teamId)` mappings. Use the linked CBBD review workflow to resolve
mappings; selecting another local team cannot override a durable provider mapping.
No automatic teams, aliases, player records or identity writes occur here. Review
all evidenced prior-season team stints, using each team's independent denominator.

The accounting categories remain eligible, verified no-college, verified
nonparticipant, outside-prior-season, unknown participation, unknown production,
unresolved identity and conflicting evidence. These CBBD endpoints do not provide
positive evidence for the three resolved exclusion categories. New CBBD decisions
cannot turn missing rows, a null athlete ID or club affiliation into a verified
exclusion; retain an unknown category and acknowledge permitted gaps. Historical
HTML decisions retain their original evidence-backed exclusion behavior.

Regular and postseason full-player points must reconcile to the independent team
points **within each scope before merging**. Thus 110/100 regular and 90/100
postseason cannot cancel into an apparently valid season. Duplicate scope keys,
wrong seasons, conflicting labels, invalid/fractional/negative points or games,
nonfinite minutes and inconsistent denominators are hard failures.
Null provider points remain unknown production, while negative/fractional or
conflicting numeric points remain hard failures. An independent known team
denominator is retained even when a player's points are unknown.
Integral numeric values such as `12.0` normalize to 12; original JSON values remain
retained. Player minutes may be fractional and are audit-only. Team `totalMinutes`
is game-clock minutes, may be null, and is never substituted for player-minutes.
The full-team player-minute sum comes from the player rows.

A missing scope/player row is absence, not a fabricated zero. A missing player in
a scope where the team has production keeps that player's season incomplete.
For a team with legitimately no postseason, enter its exact CBBD team ID in the
optional no-postseason field **only with reviewed final-scope evidence** explaining
that absence. Both postseason requests must still have succeeded, and neither may
contain production for that team. This assertion cannot excuse a missing player
when team postseason production exists. Successful empty responses never prove a
zero draft or complete missing participation. Zero-point positive-games players
remain eligible when their scopes are complete.

Save category, reason, evidence choices and stints separately from approval.
Fill the blank stint and save to add another. Numeric facts remain read-only.
The loss is unchanged: sum of drafted prior-season player points / full-team
season points. Known subtotals are never extrapolated. Unknown production for exactly mapped prior-season teams remains local to all
those teams; any unmapped stint or unknown participation keeps
all teams' loss unknown. Complete accounting with no eligible loss yields verified
zero; missing/partial coverage stays null.

Review the saved report and explicitly approve. Permitted gaps require an
acknowledgement of the exact displayed gaps with authenticated reviewer/time.
Failed/corrupt sources, conflicts and invalid facts cannot be acknowledged away.
Changed preparation, evidence, decisions, current provider mappings, aliases,
memberships, profiles or latest revisions require fresh review. Publication
revalidates retained bytes/current mappings under the existing locks and import
transaction. Failure preserves current inputs. Identical publication retries
return the same revision without rewinding pointers. Corrections create successors
with fresh approval and acknowledgement.

## Retention and compatibility

Private PostgreSQL attempts retain JSON response bytes and their ledger. Include
these attempts and immutable published revisions in private backups. Downloads
are admin-only `text/plain` attachments with the original source-kind extension;
response content is never executed as app HTML.

New evidence uses `draft-departures-v2` / `cbbd-draft-season-totals-v1`, typed
`cbbd/athlete/ID` identities and `cbbd/team/ID` production keys. Normalized annual
inputs are the stable seam a future local stat store can supply. Scoring captures
retain the explicit v2 schema/extraction/provider discriminator. Missing schema
means historical v1; provider identities cannot be smuggled into that contract.
No scoring, review or publication path fetches live sources.

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
