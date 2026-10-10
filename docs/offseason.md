# Offseason Operations

Use this sequence when preparing a new college basketball season.

Commands below run in the intended Rails environment. Locally, prefix `bin/rails`
with `bin/compose exec web` after starting an isolated development stack as
described in [Local development](development.md). YEAR=2027 means 2026–27;
example dates are operator-selected windows, not verified season boundaries.
No schedule is needed to prepare or initialize a season. An empty schedule is
expected before source publication, but does not establish ingestion success.

This runbook includes bounded future refresh, complete preseason publication,
and captured prior inputs. Verify the readiness items against the deployed
revision and intended dataset; successful activation alone is insufficient.

## 1. Prepare the season shell

Create the future `Season` and missing `TeamSeason` rows before doing conference realignment:

```bash
bin/rails season:prepare YEAR=2027
```

YEAR is required on setup/activation/rating tasks: 2027 means 2026–27.
Malformed, missing, fractional, zero, negative and greater-than-four-digit years
fail before writes. Reruns preserve stored season names, dates, averages and live
ratings, and create only missing TeamSeason rows. New seasons inherit the prior
season's dates shifted one year, or use November 1–April 10.

Optional date overrides (only supplied boundaries change):

```bash
bin/rails season:prepare YEAR=2027 START_DATE=2026-11-01 END_DATE=2027-04-10
```

`season:prepare` is intentionally limited. It does not make the season current, sync games, deduplicate games, initialize preseason ratings, create ratings config, or run ratings.

## 1a. Review participation and dates explicitly

`Season#participation_review` is empty for existing seasons: **legacy mode** keeps
all stored TeamSeason rows eligible. The additive migration does not change live
values, snapshots, dates or current status. Preparation still creates historical
rows and does not infer participation. Opt in by saving a complete operator review:

```bash
bin/rails season:review_participation YEAR=2027 REVIEW_PATH=/path/to/review.json
```

The JSON format below is synthetic; replace IDs, dates, reasons and evidence with
independently verified information for the target season:

```json
{
  "evidence": "Authoritative target-season roster source and review date",
  "reviewed_by": "Operator name",
  "dates": {
    "start_date": "2026-11-01",
    "end_date": "2027-04-10",
    "evidence": "Independently reviewed schedule boundaries and review date"
  },
  "teams": [
    { "team_id": 1, "status": "included", "reason": "Verified participant, including independents" },
    { "team_id": 2, "status": "excluded", "reason": "Verified departure, with source evidence" },
    { "team_id": 3, "status": "unresolved", "reason": "Identity/participation needs verification" }
  ],
  "unresolved_identities": ["source ID or name without a resolved stored Team ID; next action"]
}
```

Every stored Team needs an explicit decision. Omitted teams are **unresolved**,
never automatically excluded. New teams added later therefore block readiness
until reviewed. Duplicate IDs and malformed entries fail before saving. Incomplete
reviews are saved, then the command exits unsuccessfully with the unresolved IDs,
missing included TeamSeason/alias IDs, and date action. Clear unresolved identities
only after resolving them. Repeating an identical review preserves timestamps.
The review does not create teams, aliases, memberships or rating outputs. Store
source/review dates in the evidence strings; Season.updated_at records the last save.

Included teams need no conference membership. Dates must match the stored season
and have independent evidence: inherited dates or later preparation overrides are
not automatically reviewed. Prepare missing rows with `season:prepare`, correct
aliases and evidence, then repeat review. Standings alignment remains conservative
and separate; absence from its page never decides eligibility or retirement.

Initialization and daily publication use `season.rating_team_seasons`: the included
set in reviewed mode, every row in legacy mode. Excluded rows retain their stats
and history; publication clears only live ranks and creates no new excluded-team
snapshots. Historical snapshots stay intact. New snapshots carry a participation
key derived from the included IDs. Unresolved reviews block publication/activation;
activation additionally checks finite included offense/defense and positive pace.

A new verified team can be prepared, included and initialized with the existing
repeat preseason workflow when no saved forecasts or established in-season outputs
make it unsafe. Removing a team from an already published date requires a new
date/model so old excluded snapshots remain historical rather than mixed with a
revised roster. With saved predictions for the selected model, any difference from the
roster supporting those predictions (including legacy outputs without a participation key) requires
**deliberate new-version publication**, using the existing model-switch/rebuild
safeguards. The error preserves predictions and prior outputs. This does not
implement general input revisions, activate a model, or authorize a rebuild.

## 2. Align conference memberships

Run the standings comparison after preparing the season:

```bash
bin/rails season:align_conferences YEAR=2027
```

Without `YEAR`, this task uses the greatest stored `Season#year` (not the current
season). It fails clearly if there are no seasons or the requested year is missing.
It requests `https://www.sports-reference.com/cbb/seasons/men/<YEAR>-standings.html`.

Recognized teams and conferences are aligned automatically. Unchanged ranges are
not saved, so reruns preserve their timestamps. A switch creates a membership at
the target season and closes an open or overlapping prior range at `YEAR - 1`
through `TeamConferenceAssignment`; that preceding season must already exist.
All membership writes roll back if an assignment fails. Source request, structure,
and duplicate/invalid membership errors stop alignment before membership writes.

The report lists created, changed, and unchanged memberships, plus **review-required
suggestions** for unmatched or ambiguous identities and absent teams/conferences.
Safe changes are saved even when suggestions remain, but the task exits nonzero.
No team or conference is automatically created, deleted, retired, or deactivated.
A different membership already starting in the target year requires manual
correction; future membership conflicts fail validation rather than overwrite data.

Identity and roster assumptions:

- Team identity comes from the stored Sports Reference school URL, including legacy
  URLs. An exact school name or alias is a fallback only when the stored source URL
  cannot supply an identity. Nicknames and fuzzy matches are not used.
- Conferences match exact stored slug, name, or abbreviation. Conflicting matches
  require review. Source naming changes can require correcting stored identities.
- Expected teams and conferences come from membership ranges active in the target
  year. `TeamSeason` alone does not imply Division I participation: preparation
  creates those rows for historical teams as well. Absence is not evidence of a
  move to another division, and historical memberships are preserved.

Review the printed identities and candidate IDs in RailsAdmin or the Rails console,
make only independently verified corrections, then rerun the same command. Absent
teams/conferences may need verified range end dates. A future season with incomplete
standings may need a later rerun when the source is complete. There is no persisted
approval queue or ignore flag. Resolve every suggestion before bootstrap can proceed.

Manual correction paths follow below.

### RailsAdmin operational updates

Use RailsAdmin for ad hoc offseason realignment after the target season exists. Create a new `TeamConference` row with the team, conference, and start season.

When created through RailsAdmin, the app automatically closes the prior membership at the season before the new start season if the prior membership is open or overlaps the new assignment. It does not fill intentional gaps.

### Authoritative CSV updates

Edit:

```text
db/seeds/team_conferences.csv
```

Preview the full authoritative diff, then deliberately apply the reviewed file:

```bash
bin/rails import:reconcile_conferences
bin/rails import:reconcile_conferences APPLY=true
```

Use `CSV_PATH=/path/to/reviewed.csv` for an alternative complete file. Preview is
read-only and prints counts plus each proposed create/update/delete, including
membership, team, conference and season IDs before/after. `APPLY` accepts only
`true` or `false`; the default is `false`. Apply recomputes the diff against the
current database, so rerun preview if the file or memberships changed.

The complete CSV is authoritative across all stored memberships. Apply upserts
matching `(team, start season)` rows, preserves unchanged IDs/timestamps, creates
missing rows, and deletes memberships absent from the CSV, including RailsAdmin
and live-alignment assignments. This is separate from conservative
`season:align_conferences`, which preserves unrelated memberships.

Both modes validate all headers, references, duplicate keys and inclusive date
ranges before writes. Missing teams, conferences or seasons fail with row details;
this command never imports base records, prepares seasons or activates them.
Prepare missing references separately (for a season: `season:prepare YEAR=...`),
then preview again. Apply runs transactionally under the shared ratings lock;
write failure rolls back deletions and updates. Inspect the diff before applying.

`db:seed` and `import:base` now import only teams/aliases, conferences, an inactive
2024–25 shell if absent, and missing TeamSeason rows. They preserve existing
season dates, averages, activation and model outputs. They do not reconcile
memberships. Identical base reruns preserve records and timestamps; alias
ownership conflicts fail rather than reassigning an alias.

## 3. Repeat preparation and conference review safely

As a convenience, this combines steps 1 and 2:

```bash
bin/rails season:bootstrap YEAR=2027
```

Bootstrap creates missing rows and runs conference alignment. It does not activate,
initialize preseason values, sync games, deduplicate, create a ratings config, or
generate daily history. Source failures and review suggestions still stop the task.
The prepared shell and safe membership changes remain available for review and
rerun. ALIGN_CONFERENCES=false explicitly defers that review; it does not activate
the season. Review conference alignment before activation.

Former bootstrap flags SYNC_GAMES, DEDUPE_GAMES, RUN_PRESEASON, RUN_RATINGS and
RATINGS_RESUME now fail when enabled, before preparation writes, with directions
to use separate operations. Remove them from saved bootstrap commands.

## 4. Initialize and review preseason values

For a fresh, inactive season:

```bash
bin/rails season:initialize_preseason YEAR=2027
```

Initialization atomically captures priors and publishes adjusted offense, defense,
pace, net ratings, ranks, home boosts and volatility defaults, plus snapshots dated
one day before the stored season start. Snapshots use the configured bundle and
include captured prior provenance. Ties break by ascending team ID; unavailable
Five Factors remain unranked rather than receiving invented values.

A safe repeat reuses captures and snapshot identities, and can initialize newly
prepared teams. Current-season status, final games, snapshots on other dates or
live core ratings differing from their preseason values cause a clear refusal.
Scheduled predictions permit an unchanged repeat. A repeat that would change
the efficiency or pace baseline while saved predictions exist is refused and
rolled back; review dependent predictions before changing coverage or inputs. A failed publication rolls
back all writes and can be retried. Review team coverage and season boundaries
before activation; changing boundaries after publication requires explicit review.

With scheduled games and both TeamGame associations available, the existing
prediction builder uses the configured bundle's latest applicable snapshots.
Missing/incomplete core inputs produce no prediction and a warning in Rails logs.
Publication does not itself import schedules or generate predictions. Example:

```ruby
season = Season.find_by!(year: 2027)
ProphetRatings::GamePredictionBuilder.new(season.games.scheduled.first).call
```

Only the explicit rebuild job uses the initializer's separate reset entry point;
it preserves the rebuild's existing date window and publishes no additional
preseason snapshot outside that window.

Review `TeamSeason` preseason/live offense, defense, pace, rating, ranks and
prediction defaults in `/admin`, together with the preseason snapshots and captured
`PreseasonPrior` inputs. Keep missing publication outputs open in the readiness
record. Use initialization for offseason publication rather than ordinary rankings;
rankings aggregate observed games and write snapshots at their own cutoff.

## 5. Refresh schedules separately

Historical catch-up remains explicit and capped at yesterday:

```bash
bin/rails season:sync_games YEAR=2027 SYNC_RESUME=false SYNC_START_DATE=2026-11-01 SYNC_END_DATE=2026-11-15
```

Refresh an explicit target season before activation or whenever schedules change:

```bash
bin/rails season:refresh_schedule YEAR=2027 SCHEDULE_START_DATE=2026-11-01 SCHEDULE_END_DATE=2026-11-15
```

Both dates are required, ordered, inclusive Eastern schedule dates, today or later,
and entirely inside the stored season. The operation does not activate the season,
resume from a latest game, enqueue rankings, or generate predictions. Every date
in the window is requested again on each run. Use small windows to respect Sports
Reference rate limits and keep synchronous runs manageable.

The command prints a JSON report with each date's imported row count and game
outcomes (`created`, `updated`, `unchanged`, `protected`, `ambiguous`). `changes`
contains changed stored Game fields; `unmatched` lists names without a TeamSeason
association. A unique game-specific URL can move an existing game to a new date
while retaining its ID. Partial rows with daily placeholders preserve an existing
game-specific URL. Shared daily schedule URLs are not identity keys.
`possible_move_ids` lists other scheduled games with the same ordered team names;
these may be legitimate repeat matchups or ambiguous moves and require review.
Ambiguous URL/date matches are reported with candidate IDs and left untouched.

`absent_ids` lists scheduled records missing from successfully refreshed dates,
excluding games seen elsewhere in the same window. Absence alone never deletes or
cancels games. Review these IDs and ambiguous changes in Rails admin/console against
the source before correcting them. Refresh both old and new dates when investigating
moves; placeholder-only entries across dates are retained separately pending review.
Manual venue fields and completed games are protected from partial source rows.
Broken legacy final records without derived completion data retain the existing
repair behavior. Enrichment failures remain warnings with schedule-row fallback;
this report does not certify venue coverage.

HTTP errors, unsupported page structures and malformed entries fail the date,
whereas a recognized empty schedule succeeds with zero rows. Each failed date is
rolled back and retried up to three times with 5/10/20-second backoff, then reported
in `failed_dates`; later dates still run. The command exits nonzero for failed dates.
Successful dates remain committed. Rerun failed windows explicitly after fixing
source/identity issues; do not infer coverage from stored games. The existing
nightly job continues to use its rolling window and may enqueue rankings.

Historical SyncFullSeasonGamesJob still logs exhausted per-date retries without
failing the whole job: inspect its logs, and rerun the failed date window with
SYNC_RESUME=false. Its latest-game resume heuristic now excludes today/future
games, but historical game presence is still not proof of complete date coverage.
Game sync is never a prerequisite for preparing the shell or initializing existing
preseason values.

Repeat `season:refresh_schedule` with explicit windows as schedules fill in;
it revisits every requested date without selecting a resume point. Review its
`failed_dates`, `unmatched`, `ambiguous`, `possible_move_ids` and `absent_ids` after
every run. Earlier historical gaps require the bounded historical command with
resume disabled. Historical sync still logs exhausted retries without failing
the whole job; inspect logs even when it completes. For a single historical failed
date, use `SyncDailyGamesJob.perform_later(Date.new(2026, 11, 3))` and inspect its
outcome. That daily path selects the season by date, so first verify stored season
boundaries do not overlap. Empty successful future-refresh dates differ from failed
dates, but neither establishes complete source publication or venue coverage.

## 6. Activate explicitly

After checking conference review and preseason coverage:

```bash
bin/rails season:activate YEAR=2027
```

Activation repeats conference alignment by default. ALIGN_CONFERENCES=false is an
explicit operator decision to defer source review; it does not bypass local
coverage checks. Activation requires ordered dates, at least one TeamSeason, a
row for every stored team, and non-null adjusted offense, defense and pace for
every row in legacy mode. Reviewed mode instead enforces the explicit roster/date/alias
contract above and finite included-team core inputs with positive pace.
This is a minimum coverage check, not a complete publishing/readiness
report or proof of Division I participation.

The switch is atomic: any failure leaves the previous current season in place.
Reactivating an already-current season is a no-op. Preparation, initialization,
activation and ratings rebuild/resume share the scheduled rankings advisory lock.
A busy operator command exits unsuccessfully and must be retried after the active
operation finishes. Nightly predictions also use this lock; async jobs use the
existing bounded ActiveJob retry policy. Scheduled rankings retain their existing
skip-on-contention behavior.

Production's eight-hour game-sync cron selects the current season and queues
rankings/predictions for that season. Nightly jobs no longer fall back to the last
inserted season when none is current. Jobs already queued with an explicit season
ID retain that target across activation. No deploy or cron changes are performed
by these commands.

Daily rankings use the supplied season's end to cap both default and explicit
cutoffs. Timestamps normalize to the Eastern schedule date before aggregation,
adjustment and snapshot publication. An explicit target works without any current
season; a missing/invalid target fails visibly instead of silently skipping work.
All daily rating writes share a savepoint, so a later solver or snapshot failure
restores the previous live state and snapshots even when an outer caller rescues.
Predictions are queued only after successful publication and the enclosing commit;
rollback discards the enqueue callback. The existing bounded retry policy remains.

## Explicit ratings recovery and rebuilds

Non-deleting resume is separate from setup:

```bash
bin/rails season:resume_ratings YEAR=2027
bin/rails season:resume_ratings YEAR=2027 RATINGS_START_DATE=2026-11-01 RATINGS_END_DATE=2026-11-15
```

Resume is capped at the earlier of today in Eastern schedule time and season end,
even for explicit end overrides. A future season does no daily work. Legacy future
snapshots are ignored when choosing the resume date. Each day's writes are
transactional; a failed day is rolled back and the command fails, leaving completed
days available for resume. The latest completed snapshot date is reprocessed.
Resume can update outputs in its window; it does not delete history or capture
new preseason inputs. It restores the selected captured priors on each date before
calculating from bounded results. Every participant requires a complete matching
capture; missing/invalid provenance fails and rolls back that day.
RUN_PRESEASON=true is rejected by this task.

An intentional destructive rebuild requires an explicit season, date window and
confirmation:

```bash
bin/rails season:rebuild_ratings YEAR=2026 REBUILD=true RATINGS_START_DATE=2025-11-01 RATINGS_END_DATE=2025-11-15
```

Only predictions for games in that Eastern schedule-date window and snapshots in
that window, for the active ratings configuration and target season, are deleted
and recalculated. Other seasons, configurations and dates are preserved. If a
snapshot in the window supports a prediction outside the scope, the command fails
before deletion; review dependencies and deliberately widen the window. Future
dates, missing boundaries, reversed ranges and out-of-season ranges fail before
deletion. RUN_PRESEASON=true explicitly resets prior/live values only when the
window starts at season start; it is off by default.

The entire rebuild is transactional; a failure restores deleted records and live
values. A long rebuild holds a database transaction and the shared ratings lock,
so schedule it during an appropriate maintenance window. Its final day's values
become the live TeamSeason state even when later snapshots are preserved; resume
through the desired current cutoff before returning that season to ordinary use.
These are reconstruction tools, not live pregame archives. New saved predictions
use reconstructed prior-day ratings and season anchors, with actual generation
time and explicit reconstruction provenance. Historical prior-day working state
is not published outside the requested snapshot window. Reconstruction inputs
record their capture IDs and result cutoff, without pretending to have persisted
prior-day snapshot IDs. Replay learns only from one verified pregame issuance per
game/model; legacy rows and reconstructions are excluded from learning. Legacy
backfill rows may retain same-day leakage.

Resume leaves live values at its final replay date, too. To restore a desired
cutoff, run resume with explicit RATINGS_START_DATE and RATINGS_END_DATE (set both
to that date for a single-date restoration). Later snapshots are preserved and
are not starting state. Corrected source results and changes to calculation code
can change reconstruction; the tool does not recover historically available data.
Prepared finalized game/team-game statistics are inputs: replay no longer invokes
GameFinalizer to recalculate/import them or rewrites archived outcome errors.
Review/correct those stored results through the separate ingestion workflow first.

Operator rating commands invoke the job body synchronously under the shared lock
so exceptions fail the command instead of scheduling a retry and printing success.
Async use of GenerateSeasonRatingsJob now requires rebuild: true and an inclusive
Date date_range; old broad queued invocations must be reviewed and replaced.
Broad legacy ratings:backfill, ratings:backfill_all and bin/setup_data are not
routine rollover commands and do not provide these scoped safeguards.

## Readiness checklist and decision record

Use `/admin` for stored records, `/games/schedule` for schedule inspection, and the
admin-only `/good_job` dashboard for queued/retried/discarded jobs. Record the target
year, deployed commit, review time, intended refresh window, config bundle name,
counts, unresolved IDs/dates and the next action. Mark each item **pass**, **open**,
or **deferred with a reason**; there is no automatic readiness approval.

| Check | Evidence and action before activation/prediction launch |
| --- | --- |
| Dates/current season | Verify `Season` start/end against the intended schedule, ordered and without overlapping season windows. Record the current season and the intended switch. Inferred preparation dates need review. |
| Expected participation | Record an independently verified target-year Division I roster/source and expected count. Compare it with active `TeamConference` ranges and target `TeamSeason` rows; list missing, unexpected and duplicate identities. Preparation includes historical teams, so its row count is not the expected participant count. |
| Memberships/identities | Run alignment and resolve every suggestion. Compare roster teams without memberships separately: local membership ranges cannot identify a wholly missing team. Review stored school URLs, exact conference identity and aliases in `/admin`. Preserve historical ranges; do not infer retirement from absence. |
| Aliases | List expected teams with no `TeamAlias` and ambiguous/duplicate alias values; inspect unmatched names in sync logs against source spellings. `Team.search` joins aliases, so even an exact school match can fail without an alias. A nonempty alias list alone does not prove matching coverage. |
| Preseason values | For every expected participant, check finite preseason/live offense, defense, pace and rating, with positive pace; review missing history and optional profiles. In legacy mode also check every stored team's TeamSeason and live offense/defense/pace; reviewed mode enforces included coverage. Do not reset established outputs to fill a gap. |
| Ranks/defaults | Check overall/offense/defense/pace ranks for completeness and plausible ordering, plus home boosts and efficiency/pace volatility defaults. Initialization publishes these; unavailable Five Factors intentionally remain unranked. Inspect missing core ranks/defaults before prediction launch. |
| Snapshots/config | Choose the intended preseason snapshot date and config explicitly. Require one usable snapshot per expected participant for that date/config, with matching team/season, live values, ranks and required prediction stats. Count missing teams rather than all snapshots. Check stored config against `config/ratings.yml`; name reuse with changed config is rejected. Inspect `PreseasonPrior` and snapshot `stats.preseason_prior` provenance; legacy outputs may be uncaptured. |
| Schedule/venues | Record requested dates, imported counts, failed dates and reviewed empty dates from the refresh report. Review `unmatched`, `ambiguous`, `possible_move_ids` and `absent_ids`. Check both TeamGame/team-season associations, duplicate pairs/URLs, shifted/removed entries, missing start times and unknown/unconfirmed venues. Unknown venues receive no home advantage; missing source evidence stays open. No games before schedule publication is an explicit deferred item. |
| Predictions | Once scheduled games and snapshots exist, inspect prediction coverage and snapshot dates/configs for each matchup. Inspect default uncertainty rather than treating the confidence label as calibration evidence. Zero games can defer predictions, but cannot prove prediction readiness. |
| Job outcomes | Record job IDs, target season/date arguments, failed/retried/discarded dates, errors and successful recovery. Inspect logs even for completed historical sync jobs: exhausted per-date retries can be swallowed. Confirm queued explicit-season jobs still target the intended season after a switch. |

Useful read-only checks in the intended environment's Rails console:

```ruby
season = Season.find_by!(year: 2027)
rows = season.rating_team_seasons
puts({ dates: [season.start_date, season.end_date], current: Season.current&.year,
       team_seasons: rows.count, games: season.games.count,
       configs: season.team_rating_snapshots.distinct.pluck(:ratings_config_version_id) })
puts Team.where.not(id: rows.select(:team_id)).pluck(:id, :school).inspect
puts Team.where.not(id: TeamAlias.select(:team_id)).pluck(:id, :school).inspect
puts rows.where(adj_offensive_efficiency: nil)
         .or(rows.where(adj_defensive_efficiency: nil))
         .or(rows.where(adj_pace: nil)).pluck(:team_id).inspect
puts rows.where(overall_rank: nil).pluck(:team_id).inspect
```

These identify local gaps, not an authoritative roster or a pass/fail report.
Snapshot review must use the selected date/config, not simply the latest date or
an aggregate count. Keep activation deferred while identity/date/live coverage
issues remain; keep prediction launch deferred while publishing/schedule/model
evidence remains open. Explicit deferrals belong in the operator record.

## Local rehearsal and production handoff

Automated rehearsal uses synthetic records and scraper fixtures, with no live
source requests, domain imports, production copies or real-data rebuilds:

```bash
bin/test spec/tasks/season_preparer_spec.rb spec/tasks/season_conference_alignment_spec.rb spec/services/season_preparer_spec.rb spec/services/season_conference_alignment_spec.rb spec/services/scraper/conference_standings_scraper_spec.rb spec/jobs/sync_nightly_games_job_spec.rb spec/jobs/sync_full_season_games_job_spec.rb spec/jobs/resume_season_ratings_job_spec.rb spec/jobs/generate_season_ratings_job_spec.rb spec/tasks/ingestion/future_schedule_refresh_spec.rb spec/services/ingestion/future_schedule_refresh_spec.rb spec/services/prophet_ratings/preseason_initializer_spec.rb spec/services/prophet_ratings/team_rating_snapshot_service_spec.rb spec/services/prophet_ratings/overall_ratings_calculator_spec.rb
bundle exec overcommit --run
bundle exec overcommit --run pre_push
```

Coverage includes no-schedule initialization, repeat preparation with explicit
dates, unchanged outputs, review-required alignment with safe changes, rollback,
bounded future refresh and partial-date failures, repeat publication/capture reuse,
thin-team priors, historical retry exhaustion and transactional rating recovery.
Solver calls are stubbed; this is operational safety evidence, not a real-data
model accuracy or live source availability assessment.

For an explicitly requested manual local rehearsal, use a separate Compose project
and distinct app/database ports per [Local development](development.md). Record
the revision and run preparation twice with explicit dates; compare dates, current
season and outputs. Review alignment, initialize twice, confirm the repeat reuses
captured priors and snapshot IDs, then fill the checklist. Run bounded refresh and review its report
when schedules are available. Live alignment/refresh requires an
intentional source operation and dataset. Stop only that project's services with
`bin/stop`; preserve the maintainer's database and stack.

Production is a separate operator action: verify deployed commands/migrations,
backup and recovery access, admin dashboard access and cron/worker health; review
existing queued jobs and lock contention before the explicit activation. Recheck
the checklist against production data and record the switch and subsequent sync,
ratings and prediction outcomes. Local specs do not establish production readiness.
This ticket performs no deployment, production import, activation or manual data
correction. Model limitations and config-version rules are in
[Ratings System](ratings.md#preseason-blending).

## Conference-alignment handoff reconciliation

The September 28 audit's missing-task observation does not apply to the current
development checkout: `lib/tasks/conference_alignment.rake` exists, is loaded by
`spec/tasks/season_conference_alignment_spec.rb`, and is documented in step 2 and
[Data Ingestion](data-ingestion.md#seasonalign_conferences). Reuse these tasks and
fixture/service specs. The older handoff's combined bootstrap sequence is superseded
by the separate prepare/initialize/activate operations above. No duplicate
alignment implementation or new live-source smoke claim is needed.

## Historical corrections

Changing `TeamConference` rows does not automatically recalculate historical games, standings, predictions, or rating snapshots. If you correct historical membership data after games were finalized, rerun the explicit game finalization and ratings workflows needed for the affected season.

## Safety boundaries

- Conference alignment runs during explicit `season:bootstrap` and
  `season:align_conferences` calls, not deploy, application boot, or nightly sync.
- `import:base` imports teams, seasons, team seasons, and conferences, but does not reconcile conference memberships.
- `import:reconcile_conferences` is the authoritative CSV preview/apply entry point; `db:seed` imports base records only.

## Source smoke verification

On September 10, 2026, the standalone scraper was run against the 2026 standings
URL without loading Rails or connecting to a database. It parsed 365 unique team
memberships across 31 conferences from the live page's commented tables.
Automated specs use a reduced synthetic
HTML fixture reflecting that structure and do not access Sports Reference.

## Selecting a stored model version

Read [Model configuration versions](model-versions.md) before rollout or changing
the default. Apply the additive live-input provenance migration and explicitly
publish the reviewed complete bundle. Publication does not activate it; looking
up or evaluating a version does not change the active row.

Use `MODEL_VERSION=<stored bundle name>` with `season:initialize_preseason`,
`season:resume_ratings`, `season:rebuild_ratings`, or `ratings:compare_preseason`
to select one existing version without activation. Otherwise calculation defaults
select the active stored row (or an already-published authored bundle if none is
active). Queued rating/prediction jobs retain the selected version ID even if
activation or YAML changes later. `SOURCE_CONFIG` in the comparison remains the
previous-season snapshot source; `MODEL_VERSION` supplies candidate settings.

Fresh seasons can initialize priors/live ratings/snapshots for the selected model.
Legacy or differently-versioned established live ratings are not relabeled.
An intentional model switch requires the existing explicitly confirmed and
scoped rebuild path, starting at season opening with `RUN_PRESEASON=true`;
review authority, dates and dependencies before running it. The reset applies
that version's captures and defaults. Other versions' history is preserved.
Activation is separate:

```bash
bin/rails ratings_config_version:activate MODEL_VERSION=v1.6-pinned-model
```

Neither deployment nor activation repairs legacy inputs or freezes mutable data.
Older already-queued jobs with no version argument need review during rollout;
their original intended settings were not recorded. No production import,
backfill, rebuild, migration, or deployment was run to verify this change.

### Shared-pace model rollout

`v1.7-shared-pace` is the newly authored uncertainty baseline. Publish explicitly,
then select the stored version for fresh preseason inputs and snapshots before
activation, following the model-switch safeguards above. Its exact score/margin/
total moments share one uncertain pace; win probability uses efficiency difference.
The matchup screen reports confidence as Uncalibrated. Inspect numerical outputs
and coverage without claiming calibration; see [Ratings](ratings.md#shared-pace-uncertainty-baseline).
Older immutable models retain their numerical behavior and published predictions.
No import, rebuild, model activation, or production operation is automatic.

### Saved forecast provenance rollout

Apply `20261010010000_freeze_prediction_context` before running prediction jobs.
The additive fields preserve historical rows as `legacy_unverified`; no historical
issuance time or live provenance is fabricated. The migration replaces snapshot
pair uniqueness with game/model/revision uniqueness so corrected inputs append a
forecast instead of overwriting one. Deploy application and migration together.

Before prediction readiness, publish complete snapshots dated before the Eastern
game date for the selected model. Missing eligible ratings log a skipped prediction;
inspect source dates, volatility completeness and publication timing before retrying.
Nightly jobs forecast scheduled games in the next seven days and no longer fill
missing forecasts for final games. Historical workflow predictions are labeled
reconstructions and excluded from live display/evaluation.

For manual review, generate an upcoming forecast twice and confirm one revision;
correct a source input and confirm a new revision with the old replay unchanged.
Check `calculation_context`, `input_cutoff`, `generated_at`, `forecast_start_time`
and `revision_key`. Finalize a synthetic/local game and confirm outcomes attach to
the latest saved pregame revision. Existing legacy outputs remain labeled unverified;
this rollout does not repair historical leakage or establish calibrated confidence.
No production import, backfill or activation is required by the code change.

Duplicate-game repair previews remain available, but apply refuses any affected
group with frozen forecasts before mutating it. Review provenance explicitly;
reassigning a saved forecast's game or collapsing revisions is not supported.

### Synthetic reviewed-roster solver check

The standard spec stubs numerical effects and asserts the included matrix dimensions
and anchor. Run the same fixture with the real solver in a disposable Docker project:

```bash
solver_project="prophet-ratings-participation-solver-$$"
trap 'docker compose -p "$solver_project" -f compose.test.yml down --volumes' EXIT
docker compose -p "$solver_project" -f compose.test.yml up -d --wait db
docker compose -p "$solver_project" -f compose.test.yml run --rm --no-deps -T -e REAL_SOLVER=true test bash -c 'bundle exec rails db:schema:load db:abort_if_pending_migrations && bundle exec rspec spec/services/prophet_ratings/adjusted_stat_calculator_participation_spec.rb && bundle exec ruby script/check_model_solver.rb'
```

The fixture has two included teams at 100 efficiency and an excluded team at 900.
Only the included observation pair and anchor reach Python; zero centered effects
must reconstruct offense/defense of 100 while the excluded row stays untouched.
The existing independent ridge checks also run. These synthetic checks establish
boundary arithmetic, not live roster coverage or model accuracy.

## Opening-period prior/transition comparison

`ratings:compare_preseason` now extends the fixed-weight benchmark with three
preregistered sequential hypotheses: calendar baseline, two-year prior and
effective-game-count decay. It solves core observations in memory through the
prior Eastern schedule day, excluding late-created/revised prepared inputs, and
writes no model outputs. Use Docker Python/NumPy and an explicitly authorized
local dataset; pin `MODEL_VERSION` and `SOURCE_CONFIG`. See
[Preseason comparison](preseason-comparison.md) for coefficients, fallback rules,
coverage fields, chronology, roster follow-up contract and known data gaps.
The recorded single eligible season cannot support coefficient selection;
production defaults and published models remain unchanged.
