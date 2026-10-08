# Offseason Operations

Use this sequence when preparing a new college basketball season.

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

Then run:

```bash
bin/rails db:seed
```

`db:seed` treats the CSV as authoritative. It upserts matching `(team, start season)` rows, updates changed rows, creates missing rows, and deletes database memberships not present in the CSV.

Do not expect RailsAdmin-only rows to survive `db:seed`.

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

Initialization is transactional. Existing live adjusted values, snapshots,
predictions, final games or current-season status cause a clear refusal to reset
outputs. A failed initialization rolls back all its writes and can be retried.
Repeated successful initialization preserves outputs by refusing the reset.
The separate preseason publishing story owns complete ranks, defaults and
snapshots; this command calls the existing initializer and does not claim those
publication guarantees. Adding teams after initialization requires review of
their missing values before activation.

## 5. Refresh schedules separately

Historical catch-up remains explicit and capped at yesterday:

```bash
bin/rails season:sync_games YEAR=2027 SYNC_RESUME=false SYNC_START_DATE=2026-11-01 SYNC_END_DATE=2026-11-15
```

Before games begin, the existing future-date path can be called in the Rails
console with an explicit inactive season and without enqueuing ratings:

```ruby
season = Season.find_by!(year: 2027)
SyncNightlyGamesJob.perform_later(season.id, enqueue_rankings: false, future_end_date: Date.new(2026, 11, 15))
```

A reliable refresh command and source-failure/date reconciliation reporting belong
to the schedule story. Historical SyncFullSeasonGamesJob still logs exhausted
per-date retries without failing the whole job: inspect its logs, and rerun the
failed date window with SYNC_RESUME=false. Do not infer completeness from the latest
imported game; it may be a future scheduled game. Game sync is never a prerequisite
for preparing the shell or initializing existing preseason values.

## 6. Activate explicitly

After checking conference review and preseason coverage:

```bash
bin/rails season:activate YEAR=2027
```

Activation repeats conference alignment by default. ALIGN_CONFERENCES=false is an
explicit operator decision to defer source review; it does not bypass local
coverage checks. Activation requires ordered dates, at least one TeamSeason, a
row for every stored team, and non-null adjusted offense, defense and pace for
every row. This is a minimum coverage check, not a complete publishing/readiness
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
Resume can update outputs in its window; it does not delete history or implicitly
reset preseason values. RUN_PRESEASON=true is rejected by this task.

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
These are reconstruction tools, not leakage-safe prediction evaluation: existing
backfill ordering may use same-day results.

Operator rating commands invoke the job body synchronously under the shared lock
so exceptions fail the command instead of scheduling a retry and printing success.
Async use of GenerateSeasonRatingsJob now requires rebuild: true and an inclusive
Date date_range; old broad queued invocations must be reviewed and replaced.
Broad legacy ratings:backfill, ratings:backfill_all and bin/setup_data are not
routine rollover commands and do not provide these scoped safeguards.

## Historical corrections

Changing `TeamConference` rows does not automatically recalculate historical games, standings, predictions, or rating snapshots. If you correct historical membership data after games were finalized, rerun the explicit game finalization and ratings workflows needed for the affected season.

## Safety boundaries

- Conference alignment runs during explicit `season:bootstrap` and
  `season:align_conferences` calls, not deploy, application boot, or nightly sync.
- `import:base` imports teams, seasons, team seasons, and conferences, but does not reconcile conference memberships.
- `db:seed` is the only authoritative CSV reconciliation entry point.

## Source smoke verification

On September 10, 2026, the standalone scraper was run against the 2026 standings
URL without loading Rails or connecting to a database. It parsed 365 unique team
memberships across 31 conferences from the live page's commented tables.
Automated specs use a reduced synthetic
HTML fixture reflecting that structure and do not access Sports Reference.
