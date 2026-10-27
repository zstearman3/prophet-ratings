# Offseason operations

Prepare → review roster/conferences → review inputs → publish preseason → refresh
schedule → activate. Setup never requires a published schedule.

Admins can open **Admin → Offseason setup** for a season-specific dashboard and
**Admin → Model analysis** for existing prediction evaluation. The dashboard
links to the existing membership, recruiting and coaching reviews and returns to
the selected target season from those screens. Its fixed progress sequence is a
summary of stored evidence, recalculated on every page load; opening it does not
create review records or fetch source data. Membership and input reviews remain
independent actions. A changed membership/date or recruiting source/mapping can
make only that evidence step require review again while its historical approval
remains available. Coaching readiness follows the existing review's stored ready
flag and pending candidates. Later steps link to preseason publication, bounded
schedule review and retained readiness with separate activation actions; the
dashboard itself does not certify or execute them.

On the dashboard, enter the season's **ending year** (2027 means 2026–27). The
UI accepts 2–9999. Blank start/end dates preserve dates on an existing season,
or use `season:prepare` defaults for a new one. Enter a date only when making an
intentional date change. Preparation is locked and transactional, creates missing
TeamSeason rows, and never selects the season as current or resets ratings.
Recruiting capture is offered as an actionable next step only when its source
supports the prior year (target ending years 1901–2201); outside that range the
dashboard directs the operator to manual review.

`YEAR=2027` means 2026–27. Run commands in the intended Rails environment; locally,
prefix `bin/rails` with `bin/compose exec web` in an
[isolated development stack](development.md). Dates below are examples, not verified
season boundaries. Retain command reports with the target year, deployed commit,
model name, reviewer/time, unresolved IDs/dates and next actions.

## 1. Prepare the season shell

```bash
bin/rails season:prepare YEAR=2027 START_DATE=2026-11-01 END_DATE=2027-04-10
```

Creates an inactive Season and missing TeamSeason rows. Reruns preserve outputs
and stored dates unless explicitly overridden. Without dates, a new season uses
the prior season's dates shifted one year, or November 1–April 10; verify them.
Preparation includes historical teams, so its row count is not a participant count.
It does not import games, initialize ratings, publish a model or activate anything.

## 1a. Review participation and dates explicitly

Open **RailsAdmin → Seasons → target season → Review memberships**. No JSON file
is needed for the normal workflow:

1. Click **Fetch proposals from Sports Reference**. This saves a draft using the
   existing standings scraper without changing memberships or the approved roster.
   Fetching/viewing also works for current or historical seasons with published data.
2. Review **School | prior-year Membership | target-year Proposed Membership**.
   Changes and absent schools appear first; unchanged source memberships are
   collapsed and included in approval. The decision selector accepts a conference,
   **Independent (included)** or **N/A (not in D1)**.
3. Map unmatched conferences on this screen using the conference dropdowns and
   **Save mappings and refresh proposals**. Each source slug is stored in the selected
   conference's `sports_reference_slugs` array for future syncs. Canonical conference
   IDs, slugs and membership history are preserved; conflicting mappings are rejected.
   Matching checks canonical slugs first, then source aliases, then exact names/abbreviations.
   Proposals rebuild from the saved scrape without another request to Sports Reference.
   Save mappings before editing memberships: rebuilding resets unsaved decisions.
   Under **Schools needing setup**, click **Import / finish setup**, review the
   Sports Reference name and edit school details, then **Save school and season setup**.
   This creates or updates the school, preserves its source-name alias and creates
   its missing TeamSeason for the target year. It uses the saved scrape and rebuilds
   proposals without approving memberships. Existing schools missing a season row or
   alias use the same action. Ambiguous team identities still require resolving the
   duplicate records in RailsAdmin before fetching again.
   For absent schools, explicitly verify participation and select a decision;
   absence never proves retirement. Manual decisions are recorded as **Manual Review**;
   unchanged automatic matches retain their source evidence. Explicitly selected
   corrections record **Manual Review** even when accepting the source proposal.
   No typed notes are required.
4. Verify the displayed season start/end dates.
   Click **Approve memberships, participation and dates**. The signed-in admin,
   review time, source year/URL/capture, proposed rows and final decisions are retained.

Approval applies conference ranges, dates and participation together or rolls them
all back. It checks included TeamSeasons and aliases; use **Import / finish setup**
for source schools missing those dependencies. `season:prepare` remains available
for bulk preparation. Included independents need no conference membership. Changed
local identities, memberships, coverage or dates require a fresh proposal; a failed
fetch preserves the previous draft and approved review. Full participation/date
approval remains blocked once ratings exist or the season is current; discovery
and the conference-only correction action remain available.

If the target page is unavailable (for example HTTP 404 for YEAR=2027), click
**Start from previous season (2026)** explicitly. This fetches 2026 standings to
seed a 2027 draft; it does not silently retry against another year. The source and
target years are stored/displayed separately, and carried-forward rows are marked
**unverified**. Verify realignment, arrivals, departures and target-season evidence,
then check the target-year confirmation before either approval action. Previous-year
source coverage alone never establishes target-year participation.

To inspect the known 2026 source, open the **2026 Season** and fetch normally, even
if it has ratings. This writes a proposal only; it does not reset any outputs.

### Correct conference memberships without replacing the roster

Select the **Select for correction** row checkboxes for the schools to fix, choose
conferences (or **Independent / no conference**), confirm the limited
scope, and click **Apply selected conference corrections only**. Other unresolved
schools do not block selected corrections. The scope confirmation does not select
schools. Use **Select all schools for correction** to toggle every row, including
collapsed rows, or select individual schools. Unresolved decisions must still be
resolved before applying selected rows. Approval records **Manual Review** as overall
evidence; scripted reviews retain their explicit evidence requirements. N/A participation exclusions require the
full preseason review rather than this metadata-only action.

Corrections apply to the selected year only, splitting membership ranges to retain
preceding/following years. Prepare any missing adjacent boundary Season reported
by the action, then fetch/review again. All selected changes roll back if one fails.
`Season.membership_corrections` retains source years/rows, reviewer/time, evidence,
decisions and before/after memberships. Existing participation decisions, dates,
live ratings, priors, snapshots, forecasts and stored game `in_conference` flags
are preserved. Historical result/rating recalculation remains a separate explicit
operation; correcting metadata does not rewrite published model history.

Without a participation review, **legacy mode includes every stored TeamSeason**.
Reviewed publication uses only included teams; excluded history remains intact and
live ranks are cleared. Unresolved roster/date/alias coverage blocks publication
and activation. The file-based `season:review_participation YEAR=... REVIEW_PATH=...`
command remains available for existing scripted reviews.

## 2. Conference alignment alternatives

The review UI applies approved conference changes; no separate alignment command
is needed for that path. Existing CLI operations remain available:

```bash
bin/rails season:align_conferences YEAR=2027
```

This command immediately saves recognized changes and reports identity/range
suggestions. `season:bootstrap YEAR=2027` combines preparation and this alignment;
it does not produce or approve the UI proposal. Prefer `season:prepare` followed
by the review UI when approval before writes is desired.

For manual realignment, create a TeamConference in RailsAdmin with its target start
season. The prior overlapping/open membership closes at YEAR−1, which must exist.
For a complete authoritative CSV replacement, use the separate
[conference reconciliation workflow](data-ingestion.md#importreconcile_conferences):
preview before `APPLY=true`, which deletes memberships absent from that file.
Base seeds do not reconcile memberships or activate seasons.

## 3. Select the model and review offseason inputs

Choose a published immutable bundle using [model versions](model-versions.md).
Use `MODEL_VERSION=<stored-name>` consistently for publication and recovery;
omitting it selects the stored default. Reusing a name with changed settings fails.

For recruiting, draft departures or coaching effects, complete the separate
[annual input workflow](offseason-inputs.md) **before capturing preseason priors**.
These effects are experimental; missing evidence stays unknown. Basic initialization
can use the selected model's stored history/fallbacks without annual source files.
Review those fallbacks rather than interpreting them as observed inputs.

## 4. Initialize and review preseason values

For a fresh inactive season, preview first, then publish the selected model:

```bash
bin/rails season:initialize_preseason YEAR=2027 MODEL_VERSION=<stored-name> PREVIEW=true
bin/rails season:initialize_preseason YEAR=2027 MODEL_VERSION=<stored-name>
```

Publication atomically captures priors, sets live offense/defense/pace, net ratings,
ranks, home boosts and volatility defaults, and writes snapshots one day before
season start. Unavailable Five Factors remain unranked. Inspect included-team
coverage, fallbacks, ranks, season anchors and `PreseasonPrior`/snapshot provenance
in `/admin` using the selected date/model, not total snapshot counts.

Safe repeats reuse captures/snapshot identities and can initialize newly prepared
teams. They do not reread corrected inputs. Current seasons, finalized games,
later snapshots or changed live ratings require explicit recovery instead.
Saved predictions also protect baseline/roster changes; use a new version through
[deliberate preseason revision](#deliberate-inactive-preseason-revisions) when eligible.
A failed publication rolls back all its writes.

## 5. Refresh schedules separately

For today or later, request a small explicit window inside the stored season:

```bash
bin/rails season:refresh_schedule YEAR=2027 SCHEDULE_START_DATE=2026-11-01 SCHEDULE_END_DATE=2026-11-15
```

Both inclusive dates use Eastern schedule time. Every requested date is revisited.
Retain the JSON report and review `failed_dates`, `unmatched`, `ambiguous`,
`possible_move_ids` and `absent_ids`. Verify both TeamGame associations, duplicate
URLs/pairs, times and venues. Refresh old and new dates when investigating moves.
Absence never deletes a game; ambiguous matches require manual review. Completed
games and manual venue fields are protected from partial source rows.

For past dates, use checkpointed historical sync, capped at yesterday:

```bash
bin/rails season:sync_games YEAR=2027 SYNC_RESUME=true SYNC_START_DATE=2026-11-01 SYNC_END_DATE=2026-11-03
```

Resume skips completed GameSyncDate checkpoints only; existing games do not prove
completion. On an existing database, start with bounded windows rather than an
unbounded whole-season scan. After fixing failures, rerun `failed_dates` or the
report's `retry_window`; completed dates between holes are skipped. Use
`SYNC_RESUME=false` for a deliberate bounded rescan of completed dates.

Both commands preserve successful dates when other dates fail and exit nonzero
on exhausted retries. An empty recognized date means ingestion succeeded, not
that upstream publication is complete. Future refresh does not create historical
checkpoints. Neither command activates the season or generates ratings/predictions.
See [ingestion operations](data-ingestion.md) for matching and checkpoint details.

## Readiness checklist and decision record

Mark each item **pass**, **open**, or **deferred with a reason** in the retained
operator record. Activation checks minimum coverage; it does not certify readiness.

| Check | Evidence to retain |
| --- | --- |
| Dates and participants | Verified boundaries, independent target-year roster/count, included/excluded/unresolved IDs, missing TeamSeasons and aliases. Historical rows and conference memberships alone do not establish participation. |
| Conferences and identities | Approved UI proposal or CLI alignment report, with source identities resolved; reviewed aliases, membership changes and teams without conferences. |
| Preseason publication | Selected model/date, one usable snapshot and matching captured prior per included team; finite live/preseason offense, defense, net and positive pace; ranks, home boosts, volatility and fallback review. |
| Schedule and venues | Requested windows, counts, failed/empty dates, completed historical checkpoints and reviewed unmatched/ambiguous/moved/absent records. Unknown venues receive no home advantage. |
| Predictions | Once games exist, verify matchup coverage, eligible prior-date snapshots, model and frozen inputs. Inspect uncertainty defaults; confidence labels are uncalibrated. No schedule means prediction readiness remains deferred. |
| Operations | Intended current-season/model switch, deployed migrations, backup/recovery access, worker/cron health and queued job target IDs. Review retries/discards in the admin-only `/good_job` dashboard. |

Keep activation deferred for unresolved identity/date/live coverage. Keep prediction
launch deferred while required publication, schedule or model evidence remains open.
Local specs do not establish live-source availability, model accuracy or production
readiness. Use [development verification](development.md#reliable-tests-and-hooks)
for code checks; imports and manual rehearsals need an intentional target dataset.

## 6. Activate explicitly

Open the target season's **Review readiness and explicit activation** link on the
Offseason setup dashboard. Inspect required checks and optional work, acknowledge
input gaps, record any deferral reasons and save the review. Use **Activate season**
and **Make model default** as separate deliberate actions, reviewing the displayed
previous/target IDs. Refresh and save another review when evidence or either flag
changes. See [retained readiness](#retained-readiness-and-explicit-activation) for
freshness, rollback, audit and revisit rules.

The existing CLI remains available for deliberate operational use:


```bash
bin/rails season:activate YEAR=2027 ALIGN_CONFERENCES=false
```

When using CLI after UI approval, use `ALIGN_CONFERENCES=false` to preserve the reviewed decisions
rather than rerunning automatic source alignment. Without that flag, activation
reruns CLI alignment. Both paths preserve local coverage checks. Reviewed mode enforces roster,
date, alias and finite core-input coverage with positive pace. Legacy mode requires
a TeamSeason for every stored team and non-null core values. Failure leaves the
previous current season intact; reactivation is a no-op.

Season activation and the model default are separate. If changing the default for
future jobs, prefer the separate readiness action after the [model rollout safeguards](model-versions.md),
or explicitly use the existing CLI:

```bash
bin/rails ratings_config_version:activate MODEL_VERSION=<stored-name>
```

Production's eight-hour sync selects the current season and queues rankings/
predictions. Already queued jobs retain their explicit season/model targets;
review them around the switch. Recheck sync, ratings and prediction outcomes afterward.
Operator publication/recovery commands share the scheduled rankings lock; retry a
busy command after the active operation finishes.

## Deliberate inactive preseason revisions

For corrected captured inputs or changed participant coverage, publish a **new**
immutable model name, even if coefficients are unchanged, then preview and apply:

```bash
bin/rails season:revise_preseason YEAR=2027 MODEL_VERSION=<new-name>
bin/rails season:revise_preseason YEAR=2027 MODEL_VERSION=<new-name> APPLY=true PREVIEW_KEY=<reviewed-key>
```

Review included/added teams, evidence, before/after outputs and anchors. Changed
inputs invalidate the key. Publication captures fresh priors, updates live preseason
values/ranks/anchors and publishes opening-minus-one snapshots, retaining other
versions and saved forecasts. Later corrections need another new version.

Current seasons, finalized games, changed live adjusted values or later snapshots
require scoped recovery instead. Legacy forecasts can block changed baselines;
review their provenance rather than deleting or relabeling them. Revisions do not
regenerate forecasts or activate a season/model.

Heavy operations now share one serial heavy worker pool; odds/mailers retain an
ordinary pool in the same process. CBBD comparison refresh is asynchronous and
pins the current evidence/draft identities. Inspect its retained job on the private
run page before requesting a fresh comparison. See [worker concurrency and
recovery](development.md#worker-concurrency-and-recovery) for bounded contention,
interrupted acquisition and publication recovery. No retry automatically resets a
request budget, approves mappings or activates a season.

## Explicit ratings recovery and rebuilds

Recovery is separate from annual setup. Resume recalculates without deleting history:

```bash
bin/rails season:resume_ratings YEAR=2027 MODEL_VERSION=<stored-name> RATINGS_START_DATE=2026-11-01 RATINGS_END_DATE=2026-11-15
```

Dates are capped at Eastern today/season end; future seasons do no daily work.
Without bounds, resume reprocesses the latest completed date. Each day rolls back
on failure; earlier completed days survive. Complete matching captured priors are
required. Resume reuses them and rejects `RUN_PRESEASON=true`.

A destructive rebuild requires explicit confirmation and an in-season past/today window:

```bash
bin/rails season:rebuild_ratings YEAR=2026 MODEL_VERSION=<stored-name> REBUILD=true RATINGS_START_DATE=2025-11-01 RATINGS_END_DATE=2025-11-15
```

Deletes/recalculates only the target season/model's snapshots and predictions in
that Eastern date window. Out-of-window prediction dependencies block deletion.
`RUN_PRESEASON=true` explicitly resets prior/live values and requires a window
starting at season opening; use this for a reviewed in-season model switch.
The whole rebuild is transactional and holds the ratings lock: plan a maintenance window.

### Chunked local ratings replay

For a large local replay, use the host runner from the checkout containing the
new code, targeting the intended **existing populated** Compose project:

```bash
COMPOSE_PROJECT_NAME=prophet-ratings bin/backfill-ratings \
  --year 2026 --model v1.12-probability-precision \
  --from 2025-11-01 --through 2026-04-10 \
  --initialize-preseason --chunk-days 7 --progress-seconds 30
```

`--initialize-preseason` explicitly permits capture for a fresh selected model.
It requires the season opening date and refuses to initialize over any existing
season/model predictions or snapshots. Existing complete matching captures are
reused, even when this flag is supplied again; partial/invalid captures require
review. This command never resets existing model outputs or activates the model.
Use the separate explicit rebuild workflow when intentionally replacing history.

Rerun the same command after a failure: planning finds the earliest date missing
full included-team snapshot coverage, then replays from there through the requested
end. A complete range is a no-op. Snapshot coverage is the checkpoint, relying on
the existing daily transaction to publish ratings and predictions together; it is
not an audit of manually edited or imported outputs. Use an explicit resume/rebuild
for deliberate source corrections rather than this completion-oriented runner.
Snapshots with conflicting participation provenance are rejected, including when
a smaller roster would otherwise appear complete. The model ID, season dates and participant IDs are pinned and checked between
chunks; changed selections or missing earlier checkpoints require replanning.

Each day commits independently, including the opening-day preseason capture. A
failure rolls back that date while retaining earlier days. Every chunk starts a
fresh Rails process; this trades whole-season atomicity for bounded process
lifetimes and recovery. The original `season:rebuild_ratings` remains atomic.
The shared ratings lock is held per chunk, including planning, and refuses an
already-running operation. Run this only after any current replay finishes.
See [local runtime details](development.md#bounded-local-ratings-replays) for
memory caps, progress, dependency requirements and retained failure containers.

Both tools leave live values at their final replay date. Resume explicitly through
the desired cutoff before returning to ordinary use; later preserved snapshots do
not restore live state. Review/correct stored finalized results through ingestion
first. Historical predictions are reconstructions, not archived live forecasts;
see [replay limits](ratings.md#bounded-historical-ratings-reconstruction).
Conference corrections alone do not recalculate historical outputs. Duplicate repair
is a separate destructive workflow and refuses groups with frozen forecasts.
Broad `ratings:backfill`, `ratings:backfill_all` and `bin/setup_data` are not rollover tools.

### Provider-specific game-sync recovery

Game sync defaults to Sports Reference. The additive provider-scope checkpoint
migration leaves old completion records explicitly legacy; initial current-scope
runs revisit them. See [provider-aware sync](data-ingestion.md#provider-aware-sync-and-completion-scope)
for CBBD runtime secrets/storage, explicit total request/retry budgets, mapping
prerequisites and structured incomplete reports. Existing `season:sync_games`
windows support `SYNC_RESUME=false` correction rescans; `season:refresh_schedule`
always revisits its explicit future bounds without deleting absent games. An
incomplete CBBD run requires deliberate operator resumption and receives no
automatic ActiveJob retry/new budget. Production cadence/defaults remain
unactivated and require operational review.

### CBBD reviewed season memberships

With `GAME_SYNC_PROVIDER=cbbd`, **Review memberships** fetches only
`/teams/directory?season=YEAR`. YEAR is the season's ending year. The previous-year
button explicitly requests YEAR−1 and marks the proposal unverified for the target;
there is no automatic fallback to older seasons or an unfiltered current roster.
Use the same explicit CBBD API key, private capture directory, maximum requests and
retry settings documented in [data ingestion](data-ingestion.md#provider-aware-sync-and-completion-scope).
Fetching requires these settings; viewing or mapping a retained proposal needs no
API credentials and performs no HTTP requests. Failed acquisition preserves the
previous proposal. Raw sanitized response captures remain private immutable files;
the proposal retains their hashes and request provenance. Keep those files with
the operator's evidence, outside the public web root and version control.

Stored `TeamExternalIdentity` and `ConferenceExternalIdentity` mappings with provider
`cbbd` and the exact opaque source ID (`id`, never `sourceId`) remain authoritative.
For first-time mappings, the review preselects a unique exact school name or any
stored TeamAlias, and a unique exact conference name or abbreviation. Matching
ignores surrounding whitespace and case; it does not use fuzzy similarity or
Sports Reference slugs. Ambiguous candidates and multiple source school IDs
resolving to one local school require a decision.

Under **Review CBBD school and conference matches**, unresolved rows appear first
and exact matches are collapsed with their selections already filled in. Review or
override those selections, then click **Save CBBD identity matches and refresh
proposals** once to save the selected batch. Blank rows remain unmapped. This saves
provider identities only and rebuilds from retained evidence without fetching;
it does not approve memberships, change team metadata or publish ratings. Full
roster approval requires saved identity mappings. Existing mappings cannot be
reparented by this form. Changed local identities or aliases invalidate stale
submissions; refresh and review again.

For missing/unprepared schools, click **Create / finish school setup** in the
membership review. The inline form prefills the CBBD name or existing local metadata.
Supply a verified Sports Reference school URL (the relative
`/cbb/schools/school-name/men/` path or its HTTPS Sports Reference URL) and any
verified optional nickname, short name, location, venue and color. No metadata is
scraped or inferred. Save creates or completes the Team, adds its CBBD source-name
alias and target-year TeamSeason, saves its exact CBBD identity, and rebuilds the
proposal from retained source evidence without another fetch. Conference membership,
participation, dates and ratings still require their separate review steps.

Setup validates the proposal fingerprint and source ID under the review locks.
Stale/unknown source submissions, conflicting existing school names/aliases/URLs,
and provider identity conflicts are rejected without partial setup. Invalid form
values remain available for correction. An alias alone is not an approved provider
identity for game ingestion.

A nonempty directory and matching echoed season do **not** prove complete D1
population coverage or announced future realignment: open-ended upstream membership
ranges can extend into future years. Independently verify the complete target-year
roster, arrivals/departures and realignment, then check the explicit source coverage
confirmation before full approval. This attestation is retained in the approved
participation review. Missing source schools stay unresolved; absence or null
conference information never establishes departure or independence. Unknown source
schools block full approval until manually resolved. Previous-year drafts require
the additional target-year confirmation. Selected conference-only corrections do
not certify the full roster or replace its approved participation review.

Full offseason approval, for both CBBD and Sports Reference, applies conference
decisions **from the target year forward**. A switch closes the prior membership
at YEAR−1 and starts the approved conference at YEAR. New memberships are open-ended
unless the active range has an explicit end or a separate future membership already
starts later; those stored boundaries, deliberate gaps and later records are preserved.
An independent or N/A decision closes/removes the active conference from YEAR onward
without automatically restoring it in YEAR+1. Distinct later memberships remain intact.
Participation and date approval still describe only the target season.

Full approval does not require YEAR+1 merely to restore the prior conference. A
preceding boundary is still needed to close earlier history, or to end a new range
immediately before an explicit future start; a missing required boundary fails the
whole approval without writes. Prepare only that reported boundary, then fetch/review
again. New approval evidence records `conference_scope: from_target_year`. Earlier
approval evidence is unchanged; legacy CBBD full approvals used target-year-only scope.
This change does not repair or infer the intent of existing future records.

**Apply selected conference corrections only** remains scoped to the selected year
and preserves both surrounding years. It may still require YEAR−1/YEAR+1 boundary
seasons to split a range. Full approval still protects current seasons and stored
outputs; corrections preserve participation, dates, games, ratings and predictions.
No model calculation is triggered.

For CBBD use `season:prepare` and the review screen. Legacy `season:align_conferences`,
automatic bootstrap alignment and automatic activation alignment reject CBBD before
Sports Reference HTTP. Explicit `ALIGN_CONFERENCES=false` preserves the existing
manual bootstrap/activation path after review; CSV/manual reconciliation is separate.

Departure review is available from the season's **Review departure batches** link.
Prepare the target memberships first, then select **Fetch draft and college stats**.
Years are derived from the target season. Confirm the displayed drafted players
and their college teams after background validation, then approve the exact saved
proposal to queue publication. Production is calculated automatically;
players without a matching prior-season team are skipped. Missing stats for a
matched college remain visible and affect only that team's estimate. See
[departures](departures.md#saved-admin-workflow) for recovery and correction steps.
Model selection and rating initialization remain separate runbook operations.

### Admin preseason preview and publication

From **Offseason setup → Preview and publish preseason ratings**, select the target
season and an already-published model. The selection persists for that season;
it does not activate the model or season and never erases recruiting/departure
approvals. Changing models, including switching away and back, requires a fresh
publication review. The dashboard certifies only a still-current successful review
for that selection using a conservative database dependency stamp saved after publication.
Preseason progress checks never recalculate ratings or load raw input revisions. The stamp
tracks current/previous season rows, all team identities and aliases, profile
values/revision pointers, and applicable coaching facts/source seasons. Revisions and
captures retain their immutable identities.
Unrelated edits to those rows can require a fresh review. Older saved publications
without a dependency stamp remain readable but show `needs_review`, as do legacy CLI
outputs unverified by this workflow. Previously saved pending reviews may require a
fresh preview after the compact evidence/report update; retain the old review for its
audit history. Full-size memory verification covers new compact reviews, not execution
of historical reviews containing duplicated raw source bodies.

Choose **Initialize / safe repeat** to retain existing captures for that model.
Choose **Revise reviewed inputs** explicitly when publishing corrections, using an
eligible already-published immutable version. After an explicit revision, changing
models requires **Revise reviewed inputs** with an eligible unused published model;
**Initialize / safe repeat** only repeats that same revision model. This keeps the
season's revision and live/capture coverage aligned for activation. A reused
capture's operands remain
visible; current evidence is checked separately for staleness even on safe repeats.
The preview shows coverage, history fallbacks, live and proposed ratings/net/rank,
changes, components, source facts and revision identities. **Create read-only rating
preview** stores a request pinned to the model and selection generation, then queues
`PreviewPreseasonJob`. The HTTP request performs no rating calculations. GoodJob
builds and saves the compact report in the background; preview status is
`preview_queued`, `preview_running`, `review`, or `preview_failed`. No Publish button
appears until the review is ready. Creating a preview never writes ratings, captures
or snapshots. Changing model selection while the request is queued fails that pinned
request rather than silently adopting a new selection. Retry a failed/interrupted
preview only after the old worker stops, or create a fresh preview after selection changes.

Read every missing-evidence gap. Unknown recruiting/departure inputs are not
verified zero. Where the model permits fallback, check the explicit acknowledgement
before publishing. The retained acknowledgement records the admin, time, exact gaps
and season/model/input identity; it stays visible after publication. Coaching
readiness and other hard validation failures cannot be acknowledged away.

**Publish reviewed preseason ratings** queues a pinned review ID through GoodJob.
Run the worker (`bin/dev` runs it locally); restart web and worker after updating this
workflow. No new schema migration is required. The review shows
queued/running/published/failed status and error guidance. Published results show
named teams, saved ranks, net rating, offense, defense and pace from this publication’s
snapshots, without loading their large provenance payloads. The original proposal
and adjustment details remain expandable below the results; input-capture and
snapshot IDs remain retained in the publication record. Active review pages poll a metadata-only endpoint every
five seconds while visible, for at most ten minutes; manual refresh remains available.
Scheduling checks the saved fingerprint, status, pinned model selection and required
acknowledgement. The worker rechecks the full proposal before any writes;
changed inputs, dates, roster, model selection or protected outputs require a fresh
preview or the existing scoped recovery procedure. Rating writes and the success
record commit together under the shared ratings, season and applicable coaching
locks. A competing operation returns a visible lock conflict; let it finish.

If enqueue fails, the review reports failure and can be explicitly retried. If a
request stops between recording queued state and creating its worker job, use
**Requeue reviewed publication** on that queued review. It checks the pinned selection and
enqueues the same ID while retaining the original acknowledgement/admin/time; the worker
rechecks current evidence. Recovery after failed or interrupted publication also preserves
that original acknowledgement.
Repeated queued submissions may create duplicate jobs; their serialized execution
preserves capture/snapshot IDs and never repeats a committed success. If a
worker stops while status says running, first confirm the old worker has stopped,
then use **Recover interrupted publication** on that original review. The shared
writer lock prevents overlap with a live operation, and recovery rechecks the
original fingerprint. Duplicate successful deliveries preserve capture/snapshot
identities. A changed reviewed proposal requires a new review; a correction to an
already-used immutable version requires an eligible new version. Current seasons,
completed games, later snapshots and changed live ratings remain protected. This
workflow never deletes history, activates seasons, changes default models or
regenerates forecasts.

## Bounded browser schedule refresh

Admins use **Offseason setup → Refresh and review schedule** for the selected
ending-year season. Apply migrations through `20261024010000` with `bin/migrate`
and restart web and the GoodJob worker. GET pages only read stored state.
Choose **Upcoming schedule** for today or later, or **Historical games** for dates
through yesterday. Both require ordered inclusive Eastern dates inside the selected
season. Completed seasons default to a historical import of the first week.
Upcoming jobs that age into the past still fail before acquisition; create a
historical import instead. No activation, ratings or predictions are queued.

Historical imports use the same provider-scoped `GameSyncDate` checkpoints as
`season:sync_games`. By default they skip completed dates; explicitly select
**Reimport completed dates too** to rescan them (including after a production
restore). Rescanning uses the existing reconciliation rules, not a forced overwrite
of protected data. The saved mode/rescan choice is immutable and retained on
retries. Each successful date's safe report and completion checkpoint commit with
its imported games; interruption preserves completed progress. The results table
distinguishes skipped dates, empty dates, imports and failures. A retry imports
only the parent run's unfinished dates with a new explicit request budget.

Historical CBBD imports retain valid games even if another game on the same date
needs review. Each held game is rolled back independently and keeps its audit;
the date remains incomplete, and its results show how many rows were committed.
Unexpected database/runtime errors still roll back the date. Retrying an
incomplete date recognizes the valid games already stored without duplicating them.
Games against name-only opponents stay visible, with no fabricated opponent
membership. Completed name-only games use `final_unmatched` and do not enter
ratings calculations. Inconsistent supplied scoring totals remain held for review.

For eligible historical CBBD scoring discrepancies, open **Review date → Resolve
scoring discrepancy**. Compare reported game/box points with the supplied shooting
arithmetic and box counts. The reported final score is selected by default. Choose
a trusted supplied total for each affected team, review the resulting score, then
**Approve and import selected result**. No written reason is required: the app
records **Approved by admin**, the reviewer, time, and exact choices automatically.
A choice that changes the reported score is flagged before confirmation.

The selected total becomes the stored game score and team points; eligible games
enter ratings with those points even when unchanged shooting counts do not add
up. Name-only opponents retain `final_unmatched` and remain outside ratings.
The original observation stays unchanged, with an immutable review and linked
accepted import recording the exception. Other invalid/missing stats or identity
conflicts remain blocking; this action cannot overwrite a completed game.

Approval imports one game. The original run keeps its historical failure evidence
and displays the resolved game/review. Use **Retry unfinished dates with new
budget** to recompute date completion. Identical source facts reuse the saved
choice without duplicate games; changed source facts or stored game inputs remain
held rather than silently reusing an approval. No ratings backfill is queued.

A retained run records requester/time, provider, requested dates, fixed numeric
limits, status and safe date/import/outcome evidence. Sports Reference permits
three additional attempts for upcoming dates (5/10/20 second waits), or five for
historical dates (5/10/20/40/80 seconds). CBBD needs the
worker's `CBBD_API_KEY` and a private persistent writable `CBBD_CAPTURE_DIRECTORY`
(see data ingestion), plus an explicit positive total request ceiling and 0–5
retries. Environment limits can populate the form; saved limits never change with
the environment. Credentials and capture paths are never job arguments or retained
browser reports. A run acquires one CBBD range/budget, including both endpoints,
partitions and retries. This canonical importer uses filesystem captures, unlike
the separate database-backed CBBD identity review acquisition screen.

Reopen the retained report or use **Refresh status** after leaving the page.
Queued is not acquired; succeeded, including recognized empty dates, establishes
neither complete upstream publication nor reviewed/prediction-ready schedules.
The report distinguishes CBBD retrieval failures from per-date reconciliation failures,
shows rejected-game counts and scoped source matchup names, and links their retained
observations without exposing raw source errors.
Review outcome counts, failed/pending dates, source absence and possible moves via
the existing game/edit and CBBD identity review links. Links preserve the target
season. Source absence never deletes games. Reports exclude source error messages,
raw payloads and unknown reason text; use private ingestion evidence to diagnose
those details. Failed dates link distinct recreated rejection-observation audits through
existing admin evidence screens. Only matching provider, target year and requested
dates link; each audit screen returns to that season's schedule review. Reports
retain durable numeric audit references, never rolled-back observation/game IDs or
raw participant/error text. Failed date imports roll back; successful date evidence commits
atomically with domain changes.

A live duplicate delivery leaves the run unchanged. After an interrupted worker
releases its run lock, redelivery marks the prior running attempt incomplete without
reacquiring, including GoodJob's interrupted-delivery callback before `perform`.
Interrupted queued work becomes failed before acquisition, allowing explicit retry;
terminal runs and live lock contention stay unchanged. Explicit **Retry unfinished dates with new budget** creates a linked
run using only original failed/unattempted dates and original provider/limits;
successful dates and the original report remain. Review quotas before granting this
fresh budget. A sparse CBBD range can retrieve successful interior dates, but never
imports them. No automatic job retry renews a budget. If all dates committed before
interruption, there may be no unfinished dates; inspect retained evidence and start
an explicit new bounded run only when needed.

Each run permits one persisted retry child. Repeated or concurrent submissions
return an error without another enqueue; the parent report links its existing
retry. Continue from the unfinished leaf, including a child whose enqueue failed.
Reports, successful dates and original limits remain unchanged along the chain;
a separately requested full refresh starts a new root. Execution failures log
only run ID and exception class, never source exception messages.

Apply migration `20261022030000` before using this retry constraint. It replaces
the parent index transactionally; existing duplicate retry history causes failure
without deleting, merging or reassigning runs or removing the old index. Review
any existing duplicates before rollout, using this read-only query:

```sql
SELECT retry_of_id, COUNT(*) FROM schedule_refresh_runs
WHERE retry_of_id IS NOT NULL GROUP BY retry_of_id HAVING COUNT(*) > 1;
```

When no scheduled game has both stored team associations, record a reasoned
schedule/prediction-readiness deferral. Requester, time and reason remain as history;
this does not approve preseason inputs or activate anything. When usable schedules
later appear, the dashboard retains the deferral and requires reassessment. Continue
preparation and preseason work through their existing links while readiness remains
unresolved.

## Retained readiness and explicit activation

Apply migration `20261022040000` using `bin/migrate` before opening this screen.
From **Admin → Offseason setup → target season → Review readiness and explicit
activation**, inspect the fresh selected-model report. Membership/date/alias
review, a persisted valid selected model, finite core outputs with matching
applied captures and preopening snapshots/ranks, and applicable coaching readiness
are required for either switch. Existing legacy participation approval without
retained membership choices requires another membership review. No model formula
or configuration default changes with this feature.

Optional recruiting/departure approvals, current and captured input gaps, schedule,
venue, prediction coverage and latest operation results remain visible. Missing
inputs are unknown, including when their contract uses a zero fallback; observed
zero is distinct. Acknowledge the exact displayed gap set. Leave optional work
open or select its deferral checkbox; new UI deferrals record `Approved by admin`
automatically. Required checks cannot be deferred.
Absent schedule leaves prediction readiness open/deferred and does not prevent
otherwise valid season preparation. Follow the season-scoped repair links and
return through that season's dashboard to readiness.

Readiness projects operation summaries and hashes fingerprint-only database rows
in PostgreSQL instead of copying retained source bodies into the web request.
Captured inputs are checked one team at a time. Current-input checks share one
request-local revision cache, which verifies each full revision before retaining
only its compact operands and unchanged source identity. Departure setup progress reads only a saved signed publication and scalar profile
pointers. It never replays departure sources during a setup request. Unsigned
historical departure revisions remain retained and readable, but require a
reviewed correction for a current signed publication. Approval, pointer, provenance
and stale-review checks remain enforced. Reviews saved with an older fingerprint
format require a fresh review before activation. No rating formulas or published
captures are changed.

The readiness page leads with required-check blockers and review/activation
actions. Check cards summarize the evidence; input gaps use a bounded, scrollable
table. Full diagnostic JSON, participant evidence and saved approval/action audit
remain available in closed details panels. Saved-review evidence is separated
from the fresh report. Stale reviews and unresolved required checks disable new
activation actions; successful recorded actions remain replayable.

Save a review to retain the displayed report, reviewer/time, fingerprint,
acknowledgement and deferrals. This changes no current/default flags.
Then deliberately use **Activate season** or **Make model default** as separate
actions, inspecting each displayed previous/target ID. Season activation reuses
stored membership choices and the existing season activation API. Neither action
runs source alignment, calculations, imports or job enqueueing. Activating the
season leaves the default model unchanged. Model activation affects future work
that resolves the default, independently from season selection/publication.

Any reviewed change requires refreshing readiness and saving a fresh review,
including the first successful switch before requesting the second switch. Changed
aliases, dates, roster, profiles, gaps, outputs, model-selection generation,
current/default IDs or relevant later operations invalidate pending actions.
The ratings advisory lock, target-season lock, ordered model locks and annual
coaching locks coordinate existing participating writers; arbitrary SQL and
writers outside these existing locking contracts are not globally serialized.
Operators should avoid concurrent manual input edits during activation.

Successful switch and result persist in the same transaction; result-save failure
rolls back the switch. A failed attempt is saved after rollback and includes the
actual flags and next-step error. If that failure record cannot be saved, the
request raises an error and retention must be checked. A recorded successful action
replays its original outcome without switching back after another operator changes
flags. The retained review and fresh evidence show actual current/default state
separately. Keep these private audit tables in database backups; no history deletion
or new storage service is configured.

After activation, reopen retained readiness to inspect the original unknowns and
fresh schedule, venue, prediction and operation evidence. Use schedule/game review,
model analysis and GoodJob links to investigate later failures. Operational readiness
does not certify model accuracy, complete predictions or launch readiness.

Jobs explicitly serialized with season and model IDs stay pinned across both
switches. Existing scheduler/sync callsites pass season IDs. Legacy/manual queued
jobs without a season ID still resolve the current season at execution; inspect
and deliberately handle those jobs in GoodJob before switching. No queue payload
is rewritten or retroactively pinned. CLI activation retains its existing semantics.

### CBBD future-ingestion cutover

Use the [CBBD cutover runbook](cbbd-cutover.md) after reviewed memberships and
identity mappings. The proposed disposition retains production history; future
provider routing is separate from historical replacement, deployment and season
activation. Operational gates currently require a NO RELEASE recommendation.
