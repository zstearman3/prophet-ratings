# Offseason operations

Prepare → review roster/conferences → review inputs → publish preseason → refresh
schedule → activate. Setup never requires a published schedule.

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
3. Resolve unknown/ambiguous source identities in RailsAdmin, then fetch again.
   For absent schools, explicitly verify participation and select a decision;
   absence never proves retirement. Manual decisions are recorded as **Manual Review**;
   unchanged automatic matches retain their source evidence. Explicitly selected
   corrections record **Manual Review** even when accepting the source proposal.
   No typed notes are required.
4. Verify the displayed season start/end dates.
   Click **Approve memberships, participation and dates**. The signed-in admin,
   review time, source year/URL/capture, proposed rows and final decisions are retained.

Approval applies conference ranges, dates and participation together or rolls them
all back. It checks included TeamSeasons and aliases; run `season:prepare` again
for missing rows. Included independents need no conference membership. Changed
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

After completing the review:

```bash
bin/rails season:activate YEAR=2027 ALIGN_CONFERENCES=false
```

After UI approval, use `ALIGN_CONFERENCES=false` to preserve the reviewed decisions
rather than rerunning automatic source alignment. Without that flag, activation
reruns CLI alignment. Both paths preserve local coverage checks. Reviewed mode enforces roster,
date, alias and finite core-input coverage with positive pace. Legacy mode requires
a TeamSeason for every stored team and non-null core values. Failure leaves the
previous current season intact; reactivation is a no-op.

Season activation and the model default are separate. If changing the default for
future jobs, follow the [model rollout safeguards](model-versions.md) and explicitly run:

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

Both tools leave live values at their final replay date. Resume explicitly through
the desired cutoff before returning to ordinary use; later preserved snapshots do
not restore live state. Review/correct stored finalized results through ingestion
first. Historical predictions are reconstructions, not archived live forecasts;
see [replay limits](ratings.md#bounded-historical-ratings-reconstruction).
Conference corrections alone do not recalculate historical outputs. Duplicate repair
is a separate destructive workflow and refuses groups with frozen forecasts.
Broad `ratings:backfill`, `ratings:backfill_all` and `bin/setup_data` are not rollover tools.
