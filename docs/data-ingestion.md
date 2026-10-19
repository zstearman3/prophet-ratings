# Data Ingestion Pipeline

This document explains how Prophet Ratings ingests college basketball data into the Rails app. It is intended for agents and contributors working on scraping, imports, game finalization, ratings backfills, or scheduled sync jobs.

For separate preparation, conference review, initialization, schedule refresh,
activation and recovery, see [Offseason Operations](offseason.md), including its
[readiness checklist](offseason.md#readiness-checklist-and-decision-record).

## High-level flow

The core game ingestion path is:

1. A job or rake task chooses one or more dates to sync.
2. `Ingestion::GamesIngestionService` coordinates scraping, venue enrichment, and import for each date.
3. `Scraper::GamesScraper` reads the Sports Reference schedule page for the date.
4. `Ingestion::GameRowEnricher` decorates scraped rows with team schedule enrichment data.
5. `Importer::GamesImporter.import` upserts `Game` and `TeamGame` records.
6. Complete games are finalized through `Game#finalize`, which delegates to `ProphetRatings::GameFinalizer`.
7. Ratings jobs can then aggregate finalized `TeamGame` data.

The most direct entry point is `SyncDailyGamesJob`.

## Primary jobs

### `SyncDailyGamesJob`

File: `app/jobs/sync_daily_games_job.rb`

Purpose: sync one calendar date.

Default behavior:

```ruby
SyncDailyGamesJob.perform_later(Game.current_schedule_date - 1.day)
```

If no date is provided, the job defaults to yesterday in the Eastern schedule-date calendar.

Flow:

1. Build `Ingestion::GamesIngestionService.new(date:)`.
2. The service scrapes games in batches of 10 URLs.
3. Each batch is enriched with Sports Reference team schedule venue data.
4. The enriched rows are passed to `Importer::GamesImporter.import`.
5. Log the imported row count.

This job does not enqueue ratings by itself.

### `SyncNightlyGamesJob`

File: `app/jobs/sync_nightly_games_job.rb`

Purpose: sync a rolling nightly window and then optionally enqueue ratings.

Default behavior:

```ruby
SyncNightlyGamesJob.perform_later
```

It resolves the season from the provided `season_id`, or uses `Season.current`.
With no current season it returns without syncing. Pass an explicit season ID
and `enqueue_rankings: false` when refreshing an inactive future season.

The default sync window includes:

- Recently completed or stale dates from the current Eastern schedule date minus two days through yesterday.
- Upcoming scheduled dates from the current Eastern schedule date through the season end, unless `future_end_date` is provided.

For each date, it runs:

```ruby
SyncDailyGamesJob.perform_now(date)
```

After all dates sync, it enqueues:

```ruby
UpdateRankingsJob.perform_later(season.id)
```

This is the most relevant job for ongoing nightly ingestion during a season.

### `SyncFromLastGamesJob`

File: `app/jobs/sync_from_last_games_job.rb`

Purpose: resume game syncing from the latest imported game date for a season, then optionally enqueue ratings.

It resolves the season from `season_id`, or falls back to `Season.current || Season.last`.

Date range:

- Start: latest existing `season.games.start_time` converted to `Game#schedule_date`, or `season.start_date` if no games exist.
- End: earlier of `season.end_date` and yesterday in the Eastern schedule-date calendar.

Like `SyncDailyGamesJob`, it delegates each date to `Ingestion::GamesIngestionService`, so rows are scraped, enriched, and imported through the standard ingestion flow.

After syncing, it can enqueue:

```ruby
UpdateRankingsJob.perform_later(season.id)
```

This is a legacy resume path. A future imported game can skip earlier historical
gaps; use an explicit date window with `season:sync_games SYNC_RESUME=false` for
recovery rather than treating the latest game as proof of completeness.

### `SyncFullSeasonGamesJob`

File: `app/jobs/sync_full_season_games_job.rb`

Purpose: sync a whole season, or a bounded date range inside a season.

Typical call:

```ruby
SyncFullSeasonGamesJob.perform_later(season)
```

To run duplicate-game repair after the sync finishes, opt in explicitly:

```ruby
SyncFullSeasonGamesJob.perform_later(season, dedupe: true)
```

Optional parameters:

- `start_date:` / `end_date:` inclusive Eastern date bounds, as Date objects or strict `YYYY-MM-DD` strings. Invalid, reversed, future or out-of-season windows raise before scraping. Omitted bounds use season start through the earlier of season end and Eastern yesterday. Future-only seasons have no valid historical window.
- `resume:` defaults to true and skips only completed `GameSyncDate` checkpoints in the window. False explicitly rescans completed dates.
- `dedupe:` defaults to false; opt in to enqueue duplicate repair only after a fully successful sync. Ratings are never enqueued by this job.

Each date gets an initial attempt and up to five retries with 5/10/20/40/80-second
backoff. Imports and completion commit together; failed partial batches roll back.
Recognized empty dates complete with zero rows; failures and interruptions remain
failed/pending. Cumulative attempts, timestamps, row counts and last failure evidence
are persisted. Existing game presence does not create checkpoints automatically.
Completion certifies ingestion of a recognized source date, not finalization,
complete publication, team matching or venue coverage. Ambiguous reconciliation
fails the date rather than recording completion.

Later dates continue after exhaustion, then `IncompleteSync` raises with a JSON-ready
report (`days`, exact `failed_dates`, bounding `retry_window`). Historical operator
tasks invoke the job body directly so failures exit nonzero instead of silently
enqueuing ActiveJob retries. Async jobs retain the existing job retry policy, with
default resume skipping completed dates. The shared date lock prevents concurrent
ingestion across sync/refresh/daily/team callers.

This job is used by `season:sync_games` and the explicit legacy all-season
`import:games` task, not bootstrap or deployment. Prefer small, explicit windows to
adopt checkpoints on old databases. See [Offseason Operations](offseason.md) for
initial checkpoint adoption, explicit rescan and failed-window recovery.

### `SyncTeamGamesJob`

File: `app/jobs/sync_team_games_job.rb`

Purpose: sync games for a single team across a season.

It loops from `season.start_date` through the earlier of `season.end_date` and yesterday in the Eastern schedule-date calendar.

For each date, it:

1. Builds `Ingestion::GamesIngestionService.new(date:, team:)`.
2. Scrapes rows for the target team.
3. Enriches those rows with Sports Reference team schedule venue/start-time data.
4. Imports the enriched rows with `Importer::GamesImporter.import`.

This is useful for targeted repair or team-specific backfills.

## Scraper layer

### Base scraper

File: `app/services/scraper/scraper.rb`

Shared constants:

- `BASE_URL = 'https://www.sports-reference.com'`
- `SLEEP_COUNT = 2.95`

The sleep exists to avoid hitting Sports Reference too aggressively.

### `Scraper::GamesScraper`

File: `app/services/scraper/games_scraper.rb`

Purpose: scrape Sports Reference schedule and box-score pages.

Public methods:

- `to_json`: scrape all game entries for the date.
- `to_json_in_batches(start_at = 0, batch_size = 10)`: scrape a slice of game entries.
- `to_json_for_team(team)`: restrict game URLs to entries involving the team or its aliases.
- `game_count`: count game entries for the date.

Schedule URL format:

```text
https://www.sports-reference.com/cbb/boxscores/index.cgi?month=<m>&day=<d>&year=<yyyy>
```

The scraper returns symbol-keyed row hashes for linked boxscores, completed
score-only schedule results, and scheduled games. Team names may be links or
plain text; poll-rank annotations are excluded. The first source team remains
`away_team`, the second `home_team`. Missing links do not imply division,
database membership or ratings eligibility. Team filtering needs only the known
school or one of its aliases, so an untracked opponent is retained.

Every row includes:

- `home_team`, `away_team`: source names in source order.
- `home_team_score`, `away_team_score`: nonnegative integers when available;
  otherwise `nil`. Explicit zero is preserved.
- `date`: parsed start time, or the existing fallback on the requested Eastern
  schedule date. Completed boxscores use scorebox metadata; schedule rows use
  their tip time if available. Conversion preserves Eastern schedule-date identity.
- `home_team_stats`, `away_team_stats`: available basic totals, or `{}` when
  unavailable. Missing cells remain blank strings; no zero counts are fabricated.
- `url`: relative boxscore path when fetched, otherwise the full daily schedule
  URL. Score-only schedule results retain this date-level identity, not an
  invented game identifier.
- `source_completed`: boolean source confirmation, independent of database team
  matching and statistical completeness.
- `source_completion_evidence`: one of the values below when confirmed,
  otherwise `nil`.

Completion requires two valid, unequal integer scores plus supported evidence:

| Evidence | Supported source context |
| --- | --- |
| `schedule_final` | Explicit `Final` text in the schedule's gamelink cell, with or without an anchor. |
| `schedule_winner_loser` | A winner/loser row pair whose scores agree with the declared winner. |
| `boxscore` | A dated `/cbb/boxscores/YYYY-MM-DD-*.html` path, two named scorebox team containers, scorebox metadata and valid scores. Detailed tables are optional. |

A past date or bare scores do not confirm completion. Explicit canceled,
postponed, suspended, abandoned, live, in-progress, halftime or scheduled status
raises `Scraper::GamesScraper::SourceError`, including before following a
schedule's boxscore link. Malformed final scores, tied finals and contradictory
winner/loser scores also raise. An explicit `Final` accepts either no outcome
classes or one winner and one loser on the two team rows; contradictory outcome
classes raise before following a boxscore link. Descriptor rows do not supply
team outcome evidence. Without supported evidence, schedule rows remain
unconfirmed even if scores are present. A recognized empty `game_summaries`
container is an empty date; failed HTTP requests, unavailable/unrecognized pages,
and malformed team pairs are source errors rather than empty dates.

Boxscores additionally provide `box_score_location`. Basic stats are selected
using the corresponding team's school-link identifier and table ID, so a missing
away table cannot shift home statistics into the away payload. If an unlinked
scorebox name cannot be safely associated with a table, its stats remain `{}`.

`Ingestion::GameRowEnricher` preserves the completion keys, names, scores and
source URL while adding existing venue/date enrichment. The importer uses literal
`source_completed: true` with valid result names/scores and an unresolved incoming
Team or TeamSeason to classify a raw-only `final_unmatched` result. Fully matched
games still require ordinary complete-stat and numerical validation before
finalization; source confirmation alone does not bypass those checks. UI support
remains follow-on work.

Source-derived fixtures and their explicitly labeled synthetic transformations
are documented in [the fixture provenance](../spec/fixtures/games_scraper/README.md).

Team stats parsed from completed box scores include:

- Minutes
- Field goals made/attempted
- Two-point made/attempted
- Three-point made/attempted
- Free throws made/attempted
- Offensive and defensive rebounds
- Total rebounds
- Assists
- Steals
- Blocks
- Turnovers
- Fouls
- Points

## Importer layer

### `Importer::GamesImporter`

File: `app/services/importer/games_importer.rb`

Purpose: turn scraped rows into `Game` and `TeamGame` records.

Public entry point:

```ruby
Importer::GamesImporter.import(data)
```

`data` is expected to be an array of row hashes from `Scraper::GamesScraper`.

For each row, the importer:

1. Finds the season covering `row[:date]`.
2. Resolves home and away teams with `Team.search`.
3. Logs if either team cannot be matched.
4. Finds existing games by unique non-placeholder URL, then home team name, away team name, and Eastern schedule date. It also has a legacy raw-date fallback for old date-only imports and a neutral-site reversed-team fallback.
5. Builds a new `Game` if no matching game exists.
6. Creates or finds home/away `TeamGame` records when team seasons can be resolved.
7. Writes team-game stat attributes.
8. Finalizes a statistically complete, fully matched game through strict box validation.
9. Stores a source-confirmed completed unmatched result as described below; otherwise leaves the game scheduled.

A scraped row is considered complete only when all are present:

- Home score
- Away score
- All required home team stat keys
- All required away team stat keys

Required team stat keys are defined by `TEAM_STAT_KEYS` in `GamesImporter`.

Incomplete rows still preserve the scheduled game and team-game associations where possible. This allows future schedule-aware prediction workflows without requiring box-score stats.

### Completed unmatched results

The status integers remain scheduled=0, final=1 and canceled=2; final_unmatched=3
is additive. `Game.completed` and `completed?` include both completed statuses.
`Game.final` and `final?` remain the matched, numerically validated boundary.

An unmatched result requires literal `source_completed: true`, present distinct
team names, unequal nonnegative integer scores (integers or digit-only strings),
and an incoming Team or TeamSeason that cannot be resolved. Scores, dates or full
box keys alone do not confirm completion. This status describes database identity,
not verified division membership.

The importer stores scores/names and available known-side raw counts without
creating placeholder schools or team seasons, inferring missing statistics,
calculating matchup statistics or updating prediction residuals. Reused side rows
have previous raw/derived statistics cleared before incoming raw counts are stored;
unresolved stale associations and game possessions/minutes/conference flags are
cleared. Unknown sides have no TeamGame.

Partial refreshes preserve completed unmatched results, and unresolved corrections
preserve valid matched finals. A later fully matched, statistically complete row
can promote the same game ID through ordinary finalization. Failed validation
restores the entire previous unmatched result and boxes; any persistence failure,
including prediction residual writes, rolls the promotion back and propagates.
Fully matched malformed boxes cannot use unmatched status to bypass validation.
Schedule reconciliation reports unchanged completed results as protected, and
played-season safeguards recognize both statuses. No historical rewrite, import
or backfill is performed by this change.

## Venue classification

Games store explicit venue metadata:

- `venue_type`: `home`, `neutral`, or `unknown`
- `venue_source`: currently `sports_reference_team_schedule`, `sports_reference_box_score_header`, or `manual_override`
- `venue_confidence`: `confirmed`, `manual`, or `unknown`
- `venue_name`: optional venue text

The default venue type is `unknown`. Missing Sports Reference venue text is not treated as a normal home game.

Normal game ingestion enriches scraped rows before import through `Ingestion::GameRowEnricher`. It currently adds Sports Reference team schedule venue and start-time data, matching team schedule rows by box-score URL when present, then falls back to game date plus actual opponent/team pair. It does not match venue data by team and date alone.

`Game#start_time` stores the actual timestamp, but ingestion treats calendar dates as Eastern schedule dates because Sports Reference publishes college basketball schedules in Eastern Time. Use `Game#schedule_date` and `Game.on_schedule_date(date)` for import matching, selected-date pages, backfill windows, and other basketball-date queries rather than `start_time.to_date` or `date.all_day`.

`Importer::GameVenueEnricher` remains a small, idempotent, opt-in backfill/repair service. It is not run by the standard Sports Reference game import pipeline. Manual venue corrections are stored directly on `games`, typically via Rails admin or console changes, using `venue_confidence: manual`.

The enricher scrapes the Sports Reference team schedule table via `Scraper::TeamScheduleEnrichmentScraper`. The scraper reads:

- `date_game` from the table row `csk` date
- `time_game`, displayed by Sports Reference in Eastern Time and used to enrich import rows with a more precise `Game#start_time`
- `game_location`, where blank means the team page's home game, `@` means away, and `N` means neutral
- `opp_name`
- `arena`

The team schedule row is treated as the highest-priority Sports Reference venue source because it has an explicit location marker. The box-score scraper still captures header location text as transient `box_score_location` data, but games no longer persist a separate `location` column. During import, `Importer::GamesImporter` only uses `box_score_location` as a lower-priority fallback when no schedule-enriched venue fields are present and the existing game does not already have venue data:

- exact match against the home team's `home_venue`, or inclusion of the home team's `location`, marks a confirmed home game
- other present header text is stored as `venue_name` with source `sports_reference_box_score_header`, but leaves `venue_type` unknown
- blank header text leaves the game unknown

Manual classifications stored on `games` are not overwritten by scraped Sports Reference data unless the service is called with `overwrite_manual: true`.

Use these tasks to enrich and review coverage:

```bash
bundle exec rails venue:enrich
bundle exec rails venue:enrich SEASON=2026
bundle exec rails venue:coverage
bundle exec rails venue:coverage SEASON=2025
```

The coverage task prints counts by venue type and lists unknown games for manual review. Venue enrichment is a separate workflow, not a side effect of the box-score import.

## Game finalization

Complete imported games are finalized by:

```ruby
game.finalize
```

`Game#finalize` delegates to `ProphetRatings::GameFinalizer`.

Finalization uses its own transaction savepoint, including when called from an
outer transaction. It performs:

1. Validation of both stored team boxes and scores before derived writes.
2. Derived game field updates: possessions, minutes and in-conference flag.
3. Validation that game possessions, minutes and 40-minute pace are finite and positive.
4. `calculate_game_stats` on both `TeamGame` records, using raising saves.
5. Transition to `final` inside the savepoint after box and derived-stat validation.
6. Prediction error updates for stored predictions, validating snapshot/version identity.
   A rating run supplies its pinned model and updates that model's predictions;
   ordinary ingestion finalization updates all stored model predictions without
   looking up the global active version.
   Invalid snapshot/model associations are logged and skipped during ordinary
   ingestion, leaving their prediction errors unchanged. A pinned rating run
   raises on the same mismatch and rolls back finalization for review.

The status transition and prediction updates commit only after every required write succeeds.

Both home and away sides are mandatory. Required stored counts are field goals,
two-point shots, three-point shots and free throws (made and attempted); offensive,
defensive and total rebounds; assists, steals, blocks, turnovers, fouls and points.
Counts and game scores must be finite and nonnegative. Each side's total player
minutes must be finite, positive and equal to the other side's total; 225 player
minutes per side still produce a 45-minute game. Each side's calculated possessions
must be finite and positive before averaging. Validation also requires:

- The game score equals that side's points.
- Points equal `2 * two_pt_made + 3 * three_pt_made + free_throws_made`.
- Made shots do not exceed attempts in each shot category, including total field goals.
- Total field goals made and attempted equal the two-point plus three-point components.
- Total rebounds equal offensive plus defensive rebounds.

No cross-team rebound/missed-shot or steal/turnover accounting assumptions are
added. Zero-event boxes remain valid when these relationships hold and possessions
are positive. Rates with no opportunities persist as null; see
[undefined rates](ratings.md#undefined-rates).

Invalid boxes raise `GameFinalizer::MissingDerivedStatsError` with game, side and
field/reason context. Validation or persistence failure rolls back derived game
fields, both sides' statistics, prediction errors and final status together, even
if a caller rescues inside its own transaction. Persistence errors propagate.

The importer requires both incoming team seasons to resolve before finalizing a
complete row, even when a matched game already has valid stored sides. It logs
invalid-box or unresolved-side warnings and leaves new or scheduled malformed
games scheduled with their available raw boxes for inspection. A complete correction to
an existing final game includes its raw game and box writes in the same savepoint
as finalization: an invalid correction logs a warning and preserves the previous
consistent final record, both boxes and prediction errors. Other save failures
roll back the complete row and propagate. No historical data is repaired or
rewritten by this validation change.

Finalized games are the authoritative inputs for ratings aggregation.

## Base data import

### `Importer::Setup::BaseDataImporter`

File: `app/services/importer/setup/base_data_importer.rb`

Purpose: import foundational records needed before game ingestion.

It runs:

1. `import_teams`
2. `import_seasons`
3. `import_team_seasons`
4. `import_conferences`

Seed files currently include:

- `db/seeds/scraped_teams.csv`
- `db/seeds/conferences.csv`

`db:seed` and `import:base` run this importer transactionally under the shared
ratings lock. Teams resolve to persisted records before aliases are created;
identical team/alias reruns preserve timestamps, and conflicting alias ownership
fails without reassignment. It creates the inactive 2024–25 historical shell
(`YEAR=2025`, ending-year convention) only if missing. Existing season dates,
averages, current status, live ratings, snapshots and predictions are untouched.
Missing TeamSeason rows are created for stored teams/seasons; this is historical
storage, not proof of current participation. Conference memberships are separate.

Rake task:

```bash
bin/rails import:base
```

In Docker/local development:

```bash
bin/compose exec web bin/rails import:base
```

## Rake task workflows

### `import:base`

File: `lib/tasks/import.rake`

Imports foundational teams/aliases, inactive historical season, missing team-season rows and conferences. Does not reconcile memberships or activate a season.

```bash
bin/rails import:base
```

### `import:reconcile_conferences`

Preview the complete authoritative `db/seeds/team_conferences.csv` diff:

```bash
bin/rails import:reconcile_conferences
bin/rails import:reconcile_conferences APPLY=true
```

`CSV_PATH` selects another complete CSV. Default preview writes nothing; only
`APPLY=true` permits writes. Other values except `false` fail. Counts and row
changes expose membership/team IDs and before/after conference and season IDs.
Apply recomputes the diff; preview again after file/database changes. It preserves
matching natural-key IDs, updates changed rows and deletes all absent memberships,
including admin/live-alignment rows. This differs from conservative standings
alignment. Both modes reject missing references, malformed/empty files, duplicate
keys and overlapping inclusive ranges. No base import, season creation or
activation occurs. Prepare references separately, then rerun preview. Apply is
atomic under the shared ratings lock; failures roll back all membership changes.

### `import:games`

File: `lib/tasks/import.rake`

Runs `SyncFullSeasonGamesJob` synchronously for every season ordered by year, printing reports and exiting nonzero on failure. Future-only seasons require the separate future refresh workflow; prefer `season:sync_games` with an explicit YEAR and small window for controlled checkpoint adoption.

```bash
bin/rails import:games
```

### `season:bootstrap`

File: `lib/tasks/season_bootstrap.rake`

Purpose: repeat preparation and conference review without activating or changing
rating/prediction outputs. YEAR is required; existing dates are preserved unless
START_DATE or END_DATE is supplied. Missing TeamSeason rows are created.

```bash
YEAR=2027 bin/rails season:bootstrap
```

Conference alignment remains enabled by default. Source failures or unresolved
suggestions stop the operation after preserving the prepared shell and safe
membership changes. ALIGN_CONFERENCES=false explicitly defers source review.
Former sync/dedupe/preseason/rating bootstrap flags fail when enabled; use separate
tasks. Preparation never starts sync or ratings.

See [Offseason Operations](offseason.md) for separate initialization, schedule
refresh, explicit activation, non-deleting resume and confirmed, bounded rebuild
commands, including partial-failure recovery and shared ratings locking.

### `season:align_conferences`

```bash
bin/rails season:align_conferences YEAR=2027
```

Omit `YEAR` to use the greatest stored season year. A missing season fails clearly.
`Scraper::ConferenceStandingsScraper` fetches the target Sports Reference men's
standings page and parses ordinary or commented conference tables without writes.
It rejects unsupported structure, wrong-year links, missing identity fields,
duplicate team memberships, and inconsistent source conference identities.
`ConferenceAlignmentMatch` resolves stored identities conservatively;
`SeasonConferenceAlignment` applies safe assignments transactionally using
`TeamConferenceAssignment`, preserving unchanged rows and historical ranges.

Output includes year, source URL, created/changed/unchanged counts and details,
and review suggestions. Suggestions are informational; no team/conference lifecycle
changes are applied. Safe assignments can succeed while suggestions cause a nonzero
exit. Resolve identities or membership ranges manually, then rerun the same command.
See [Offseason Operations](offseason.md) for roster assumptions, conflict handling,
review steps, and the distinction from destructive authoritative CSV reconciliation.

### `season:sync_games`

File: `lib/tasks/season_bootstrap.rake`

Purpose: sync historical games for an explicit existing YEAR, capped at yesterday.
Prints a per-date JSON report and exits nonzero for exhausted retries. Historical windows are inclusive Eastern dates inside the target season and no later than yesterday.

Example:

```bash
YEAR=2026 SYNC_RESUME=true bin/rails season:sync_games
```

It supports:

- `YEAR`
- `SYNC_RESUME` (default true: skip only completed date checkpoints; false explicitly rescans)
- `SYNC_START_DATE`
- `SYNC_END_DATE`

### `season:refresh_schedule`

Refresh every date in an explicit existing target season's future window:

```bash
bin/rails season:refresh_schedule YEAR=2027 SCHEDULE_START_DATE=2026-11-01 SCHEDULE_END_DATE=2026-11-15
```

Both inclusive Eastern dates are required and must be today or later and inside
the target season. It reuses date scraping, enrichment and game imports without
activation or ratings. The JSON report distinguishes empty dates from failures,
records changed/unmatched games and lists ambiguous identities, possible moves and
source absences for manual review. No absent game is deleted. Exhausted date
retries produce a nonzero exit while preserving successful dates. See
[Offseason Operations](offseason.md) for retry, reconciliation and review details.

### `games:dedupe`

File: `lib/tasks/game_dedupe.rake`

Purpose: report or repair duplicate games created by historical import matching issues.

By default this task is a dry run:

```bash
bin/rails games:dedupe
```

The task looks for duplicate groups using the same conservative identifiers used by the importer:

- unique non-placeholder game URLs
- ordered teams plus Eastern schedule date
- ordered teams plus legacy raw stored date for old date-only rows
- neutral-site unordered team pairs plus schedule date

It hard-orders survivors as strict final, then final_unmatched, then other statuses. Within each status priority it prefers complete `TeamGame` data, predictions/odds, manual or known venue data, unique URLs, and then lower ids as a tie breaker. An unmatched survivor retains its result and known raw side; duplicate boxes and derived game values are not copied into it or used to upgrade its status. In dry-run mode it only prints the groups and planned survivor.

To repair records, set `APPLY=true`:

```bash
APPLY=true bin/rails games:dedupe
```

For production-sized repairs, enqueue the same repair as a background job instead of keeping a console session open:

```bash
APPLY=true ENQUEUE=true bin/rails games:dedupe
```

You can also enqueue directly:

```ruby
RepairDuplicateGamesJob.perform_later(season_id: season.id, apply: true)
```

The apply mode reassigns safe dependent records such as `TeamGame`, `Prediction`, `GameOdd`, `BookmakerOdd`, and `BetRecommendation` where unique constraints allow it, deletes conflicting duplicate dependents, and then deletes duplicate `Game` records. You can restrict the scope with `YEAR=<year>` or `SEASON_ID=<id>`.

Use this carefully because it deletes records.

## Local Docker examples

From the host, using the local Docker setup:

```bash
bin/compose exec web bin/rails import:base
```

Sync all seasons:

```bash
bin/compose exec web bin/rails import:games
```

Prepare and review an explicit target season without activating it:

```bash
bin/compose exec web bin/rails season:bootstrap YEAR=2026
```

Sync a bounded season window:

```bash
bin/compose exec web bin/rails season:sync_games YEAR=2026 SYNC_START_DATE=2025-11-01 SYNC_END_DATE=2025-11-15
```

The broad legacy data setup script is a separate, explicit import/backfill:

```bash
bin/compose exec web bin/setup_data
```

`bin/setup_data` is not a routine rollover or verification command. Its existing
broad production bootstrap sequence is unchanged. Base seeding no longer activates
a season or reconciles memberships; review/prepare required seasons and run the
separate authoritative CSV preview/apply before game ingestion when needed. It runs:

1. `bin/rails db:prepare`
2. `bin/rails import:base`
3. `bin/rails import:games`
4. `bin/rails ratings:backfill_all`

## Data integrity notes

- Team identity is resolved by `Team.search` and team aliases. If team names change upstream, update aliases rather than hardcoding importer exceptions when possible.
- Games are matched first by unique non-placeholder URL, then by home team name, away team name, and Eastern schedule date, with legacy and neutral-site fallbacks. Be careful changing matching logic because duplicate games can affect ratings and snapshots.
- Scheduled rows intentionally preserve games without complete stats.
- Complete rows must include all required stats before finalization is attempted.
- Finalized games should not be overwritten by later partial/scheduled rows.
- Ratings only use finalized games through `TeamGame` and `Game` queries.
- Sports Reference scraping includes sleeps. Avoid reducing the sleep without considering rate limits and source-site terms.

## Agent guardrails

When changing ingestion code:

- Inspect `SyncDailyGamesJob`, `SyncNightlyGamesJob`, `SyncFullSeasonGamesJob`, `Ingestion::GamesIngestionService`, `Scraper::GamesScraper`, `Importer::GamesImporter`, and `ProphetRatings::GameFinalizer` first.
- Preserve idempotency where possible. Re-running a sync for the same date should update or preserve existing records, not create unnecessary duplicates.
- Keep scheduled-game support intact; future prediction workflows may rely on scheduled games before box scores are final.
- Do not silently alter team matching behavior without tests and alias migration/seed updates.
- Do not make destructive dedupe behavior broader without explicit review.
- Add tests for edge cases involving missing teams, incomplete stats, scheduled rows, duplicate games, and finalization failures.
- Be clear whether a job only imports games or also triggers ratings.
- Keep ingestion changes grounded in stored source data. Do not invent team names, scores, stats, or locations.

## Current implementation notes

- `SyncDailyGamesJob` imports one date and does not enqueue ratings.
- `SyncNightlyGamesJob` imports a rolling window and then can enqueue `UpdateRankingsJob`.
- `SyncFromLastGamesJob` resumes from the latest imported game date, delegates each date to `Ingestion::GamesIngestionService`, and then can enqueue `UpdateRankingsJob`.
- `SyncFullSeasonGamesJob` requires a target season, validates historical bounds, checkpoints successful/empty dates transactionally and retries failed/unknown dates on resume. Exhausted dates raise a structured incomplete-run report after later dates run. It does not enqueue ratings by itself. See [Offseason Operations](offseason.md) for initial checkpoint adoption, bounded rescan and recovery.
- All ingestion service callers share a per-date advisory lock. Historical sync and future refresh hold it through their date transaction commit; contention fails visibly instead of starting concurrent imports.
- `SyncTeamGamesJob` is useful for targeted repair, delegates team-date rows to `Ingestion::GamesIngestionService`, and defaults `season_id` to `Season.last.id`.
- `Scraper::GamesScraper#scrape_day_batch` slices with an exact batch size; adjacent batches do not overlap. Schedule responses are cached per scraper and failed/unrecognized pages raise instead of counting as empty dates.
- `Importer::GamesImporter` logs partial team matches but can still preserve games with missing team-season associations.
- `GameFinalizer` updates prediction errors if a matching prediction and snapshots already exist.

Duplicate repair refuses an affected group containing frozen forecast context,
including a forecast on the survivor. It locks the group's games and checks before
merging any fields or dependents. Review forecast provenance before applying a
repair; there is no automatic reparenting or snapshot-pair deduplication of frozen
revisions. Dry runs remain available. Legacy-only groups retain existing behavior.

## Reviewed season participation

The admin-only **Seasons → Review memberships** action reuses
`Scraper::ConferenceStandingsScraper` and `ConferenceAlignmentMatch` to save a draft
in `Season.membership_proposal`. Fetching is explicit (POST), not a GET, deploy or
nightly side effect. It does not call the applying alignment service. The table
compares prior-year stored membership with the explicitly chosen source membership, including
unresolved schools and source identities. Unchanged matches are collapsed; absent
teams require an explicit decision and evidence, never automatic exclusion.
Discovery is allowed for current/historical seasons with established outputs;
publication guards apply to full participation/date approval, not fetching drafts.

The separate **Start from previous season** action fetches exactly YEAR−1 into a
YEAR draft. It stores `source_year` and `target_year` independently, labels every
carried-forward row unverified and requires explicit target-year verification plus
evidence before applying. HTTP/parse failures never cause an automatic source-year
fallback. Only the target year or its immediate predecessor is supported. The
scraper still validates links against its actual requested source year.

Approval atomically applies conference ranges and the existing participation/date/
alias contract under the season/ratings lock. It records the signed-in reviewer,
review time, source rows/URL/capture and final decisions in `participation_review`.
Included independents remain eligible. Source failures preserve prior drafts;
changed local input or a replaced proposal blocks stale approval. Full approval
for existing published outputs/current seasons is refused. No teams, aliases, ratings, snapshots or
predictions are created by this review. Apply the additive membership-proposal
migration before use. Existing seasons are not opted into review by migration.

**Apply selected conference corrections only** is separate from full approval and
can run on established seasons. It accepts only explicitly selected local school
IDs, membership choices, evidence and scope confirmation. Other unresolved schools
can remain open. Source-year verification is still required for previous-season
drafts. The action changes only the target year's conference metadata, preserving
surrounding ranges and unchanged assignments; missing adjacent boundary seasons
fail visibly rather than creating implicit shells. A selected N/A participation
exclusion is refused; use no conference for metadata-only changes.

Corrections run atomically under the same season/ratings lock. They append an audit
to `Season.membership_corrections` and clear the consumed proposal. The audit retains
reviewer/time, source years/rows, scope/evidence, selected decisions and before/after
membership records. Apply migration `20261016010000` before using this action.
No existing participation review, dates, live ratings, captures, snapshots, predictions
or stored game conference flags are recalculated. Historical re-finalization or
rating reconstruction still requires the separately reviewed ingestion/recovery flow.

The file-based `season:review_participation` command remains compatible for scripted
reviews. CLI alignment/bootstrap still apply safe source changes directly and do
not create UI proposals. See [Offseason Operations](offseason.md#1a-review-participation-and-dates-explicitly)
for the recommended prepare → UI review → preseason publication path. After UI
approval, activation with `ALIGN_CONFERENCES=false` preserves explicit source overrides.

## Coaching-change discovery

Open **Review coaching** from a Season in RailsAdmin, or from the Coaching changes
list to choose a year before a Season exists. Click **Fetch coaching changes** to
queue discovery through GoodJob. The yearly screen retains job status, errors and
last successful fetch time, and displays stored candidates for editing/approval.
See [annual coaching review](offseason-inputs.md#4-review-coaching-when-the-model-enables-it)
for the complete workflow. There is no operator JSON report or discovery command.

The selected year uses the ending-year convention: 2027 discovers the public
2026 HoopDirt coaching tracker for 2026–27. No Season preparation is necessary.
`Scraper::CoachingChangesScraper` reads the annual page, selects its explicitly
labelled D1 configuration and follows its current public all-data request. Table
IDs and nonces are discovered afresh on every run. Other divisions are excluded;
missing/ambiguous tables, limited requests, HTTP failures, malformed rows,
duplicate schools and empty D1 input fail visibly before any writes. The entire
candidate import is transactional under the coaching year lock. Failed imports
preserve existing candidates/decisions/readiness. Fetch again after
source recovery; if the page structure changed, repair the adapter and fixtures
rather than treating the failure as an empty year or deleting candidates.

The screen shows stored destination schools, source incoming/former coach labels,
proposed previous teams and reviewed facts, including source conflicts and absences.
Team selectors let the operator correct identities without managing candidate IDs.
Fetched source coverage is not proof of complete D1 membership or correct coaching history. No teams or
aliases are created. Exact canonical school names and existing aliases from all
sources are combined; case and surrounding whitespace are ignored. Only a unique
identity resolves. Nicknames, ambiguous aliases, interim annotations and spelling
variants remain for review; there is no fuzzy coach or team matching. Resolve
missing labels by adding a reviewed TeamAlias with source `hoopdirt` in Rails Admin,
then fetch again. Inspect ambiguous labels before choosing a team; never reassign an
existing alias merely to force a match.

An incoming coach is matched to *other rows' former coaches*, never to the
former coach at the destination. One exact cross-row match proposes a previous
school/Team; multiple matches leave the previous Team unresolved. No
match leaves history incomplete, including assistants, first-time hires and
coaches whose previous school is absent. Every proposal requires manual review;
previous year/role and full-season responsibility are never inferred. Pending
proposal changes clear unsupported prior responsibility fields if the incoming
coach or proposed prior school/Team changes.

Discovery retains a normalized source school key and the latest incoming/former
coach labels, resolved destination/prior Team IDs and a source-presence flag for
matching, idempotency and detecting changed input. Alias corrections that change
these resolved proposals also clear readiness once, including newly ambiguous
identities. Source URLs, snapshots, fingerprints and revision-history records are
not persisted; the screen links to the annual tracker for verification. Reruns use
that school/year key first, then unique destination Team/year/coach equivalents,
including manual entries. Colliding equivalents remain intact and receive a
separate pending candidate with all relevant IDs. Confirmed/rejected facts and
review decisions are never overwritten; changed source proposals remain visible
beside stored facts for manual correction/reconfirmation. Identical reruns preserve
readiness. New pending candidates and changes in observed coaching labels or
pending facts clear readiness, including changes to the former-coach label.
Attaching equivalent discovery labels to a manually reviewed move preserves
readiness. An already reported, unchanged conflict does not repeatedly invalidate
an operator's subsequent readiness decision. Source omissions appear as warnings
and clear readiness once; reappearance also clears it. Neither deletes a candidate
nor undoes a decision. Imports never mark a year ready or change ratings, pace
adjustments, snapshots or the legacy offseason profile flag.

See [annual coaching review](offseason-inputs.md#4-review-coaching-when-the-model-enables-it)
for the operator's review/revision steps.

## Annual draft departures

Draft departures use an explicit file-only acquisition layer, separate from game
imports and ratings. See [Annual departure acquisition](departures.md) for
`departures:acquire`, `departures:replay`, `departures:preview`, supported NBA results
and official-school Sidearm tables, saved-source recovery, and the reviewed-file
contract. Sources, response bytes/hashes, capture times, failures, full selection
ledger and normalized totals are retained. Identity review is a separate immutable
mapping revision; incomplete evidence never becomes a verified zero. These commands
perform no database writes, data imports, scoring or scheduled scraping.

## Recruiting review

The season admin's **Review recruiting** action fetches the prior year's 247 Recruit
Composite rankings into database batches and normalized entries. Review mappings
and approve there; no recruiting file import commands are provided. Failed captures
remain inspectable and new fetches create separate batches. See
[recruiting review](recruiting.md) for acquisition, validation and recovery details.

Recruiting and coaching share `Team.matching_school_or_alias(name)`. It returns a
chainable relation of distinct candidates from canonical school names and aliases
across all sources, ignoring case and surrounding whitespace. Callers must require
a unique candidate before auto-mapping; the query never chooses the first match
or uses fuzzy matching.

## Annual evidence to preseason handoff

Follow the [2026-to-2027 bundle checklist](offseason-inputs.md)
for the complete acquire → identity/participation review → input import → model
preview sequence. Acquisition/parsing and loss arithmetic are automated; approval,
source scope and ambiguous identities require operator evidence review. Recruiting
captures and decisions are retained in database batches/revisions; retain departure
capture files, approved decisions and coverage reports. Missing recruiting
points or incomplete draft accounting remain unknown, including in approved partial
inputs; never infer zero from source absence. Approve recruiting in the admin UI;
departure import uses the decisions file and original replayable capture. Each
publication validates its own reviewed evidence and guarded preview key.

Input imports only write reviewed revisions and profile pointers. They do not
publish/activate a season. Revised sources/reviews need immutable successors and
a fresh import preview. Model publication has a separate preview key and transaction;
its rollback does not undo earlier deliberate input imports. Old captures retain
their original evidence, so a correction requires a new model revision to affect
future publication. See the checklist for explicit incomplete-preview reporting
when annual evidence or stored history has not yet been supplied.
