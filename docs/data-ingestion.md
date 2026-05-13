# Data Ingestion Pipeline

This document explains how Prophet Ratings ingests college basketball data into the Rails app. It is intended for agents and contributors working on scraping, imports, game finalization, ratings backfills, or scheduled sync jobs.

## High-level flow

The core game ingestion path is:

1. A job or rake task chooses one or more dates to sync.
2. `Scraper::GamesScraper` reads the Sports Reference schedule page for each date.
3. The scraper returns either completed box-score rows or scheduled-game rows.
4. `Importer::GamesImporter.import` upserts `Game` and `TeamGame` records.
5. Complete games are finalized through `Game#finalize`, which delegates to `ProphetRatings::GameFinalizer`.
6. Ratings jobs can then aggregate finalized `TeamGame` data.

The most direct entry point is `SyncDailyGamesJob`.

## Primary jobs

### `SyncDailyGamesJob`

File: `app/jobs/sync_daily_games_job.rb`

Purpose: sync one calendar date.

Default behavior:

```ruby
SyncDailyGamesJob.perform_later(Date.yesterday)
```

If no date is provided, the job defaults to `Date.yesterday`.

Flow:

1. Build `Scraper::GamesScraper.new(date)`.
2. Ask the scraper for `game_count`.
3. Scrape games in batches of 10 URLs.
4. Pass each batch to `Importer::GamesImporter.import`.
5. Log imported batch ranges.

This job does not enqueue ratings by itself.

### `SyncNightlyGamesJob`

File: `app/jobs/sync_nightly_games_job.rb`

Purpose: sync a rolling nightly window and then optionally enqueue ratings.

Default behavior:

```ruby
SyncNightlyGamesJob.perform_later
```

It resolves the season from the provided `season_id`, or falls back to `Season.current || Season.last`.

The default sync window includes:

- Recently completed or stale dates from `today - 2.days` through yesterday.
- Upcoming scheduled dates from today through the season end, unless `future_end_date` is provided.

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

- Start: latest existing `season.games.start_time`, or `season.start_date` if no games exist.
- End: earlier of `season.end_date` and `Date.yesterday`.

Like `SyncDailyGamesJob`, it imports each date in batches of 10.

After syncing, it can enqueue:

```ruby
UpdateRankingsJob.perform_later(season.id)
```

Use this when trying to catch up from whatever has already been imported.

### `SyncFullSeasonGamesJob`

File: `app/jobs/sync_full_season_games_job.rb`

Purpose: sync a whole season, or a bounded date range inside a season.

Typical call:

```ruby
SyncFullSeasonGamesJob.perform_later(season)
```

Optional parameters:

- `start_date:` override the sync start date.
- `end_date:` override the sync end date.
- `resume:` start from the latest imported game date instead of the season start.

Date range:

- End is capped at the earlier of the requested end date, season end date, and `Date.yesterday`.
- Start is capped at no earlier than the season start date.
- If `resume: true`, start defaults to the latest imported game date or season start.

Each date is retried up to five times with exponential backoff:

- Base delay: 5 seconds
- Max retries: 5

This job is used by season bootstrap and import rake tasks.

### `SyncTeamGamesJob`

File: `app/jobs/sync_team_games_job.rb`

Purpose: sync games for a single team across a season.

It loops from `season.start_date` through the earlier of `season.end_date` and `Date.yesterday`.

For each date, it:

1. Builds a `Scraper::GamesScraper`.
2. Skips dates with zero games.
3. Scrapes rows for the target team with `to_json_for_team(team)`.
4. Filters rows against the team's school name and aliases.
5. Imports matching rows with `Importer::GamesImporter.import`.

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

The scraper handles two kinds of entries:

- Completed games with a box-score link.
- Scheduled games on the schedule page without a final box-score link.

Completed game rows include:

- Home team name
- Away team name
- Home score
- Away score
- Start date/time
- Location
- Home team stats
- Away team stats
- Box-score URL

Scheduled game rows include:

- Home team name
- Away team name
- Scheduled start time if parseable
- Optional scores if present on the schedule page
- Empty team stats
- Schedule-page URL

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
4. Finds existing games by home team name, away team name, and date.
5. Builds a new `Game` if no matching game exists.
6. Creates or finds home/away `TeamGame` records when team seasons can be resolved.
7. Writes team-game stat attributes.
8. Finalizes the game if the row is complete.
9. Otherwise leaves or marks the game as scheduled.

A scraped row is considered complete only when all are present:

- Home score
- Away score
- All required home team stat keys
- All required away team stat keys

Required team stat keys are defined by `TEAM_STAT_KEYS` in `GamesImporter`.

Incomplete rows still preserve the scheduled game and team-game associations where possible. This allows future schedule-aware prediction workflows without requiring box-score stats.

## Venue classification

Games store explicit venue metadata:

- `venue_type`: `home`, `neutral`, or `unknown`
- `venue_source`: currently `sports_reference_schedule` or `manual_override`
- `venue_confidence`: `confirmed`, `manual`, `inferred`, or `unknown`
- `venue_name`: optional venue text

The default venue type is `unknown`. Missing Sports Reference location text is not treated as a normal home game.

`Importer::GameVenueEnricher` is intentionally small, idempotent, and opt-in. It is not run by the standard Sports Reference game import pipeline. It first checks manual overrides in `db/data/game_venue_overrides.yml`. Overrides match by season year, game date, and unordered team pair, and can set `venue_type` plus an optional `venue_name`.

If no manual override exists, the enricher can use the imported `Game#location` text:

- exact match against the home team's `home_venue`, or inclusion of the home team's `location`, marks a confirmed home game
- other present location text is treated as an inferred neutral venue
- blank location leaves the game unknown

Manual classifications are not overwritten by inferred Sports Reference data unless the service is called with `overwrite_manual: true`.

Use this task to review coverage:

```bash
bundle exec rails venue:coverage
bundle exec rails venue:coverage SEASON=2025
```

The task prints counts by venue type and lists unknown games for manual review. The next venue ingestion path should be a separate scraper/importer, not a side effect of the box-score import.

## Game finalization

Complete imported games are finalized by:

```ruby
game.finalize
```

`Game#finalize` delegates to `ProphetRatings::GameFinalizer`.

Finalization runs in a transaction and performs:

1. Derived game field updates:
   - Possessions
   - Neutral-site flag
   - Minutes
   - In-conference flag
2. Finalization prerequisite validation.
3. `calculate_game_stats` on each `TeamGame`.
4. Prediction error updates for matching predictions.
5. `game.final!` status transition.

A game cannot finalize unless it has enough derived data to compute pace. If finalization fails due to missing derived stats, the importer logs a warning and leaves the game scheduled.

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
5. `import_team_conferences`

Seed files currently include:

- `db/seeds/scraped_teams.csv`
- `db/seeds/conferences.csv`
- `db/seeds/team_conferences.csv`

The importer upserts teams, creates aliases from `secondary_name`, creates seasons, creates `TeamSeason` rows for all teams/seasons, imports conferences, and creates team-conference membership rows.

Rake task:

```bash
bin/rails import:base
```

In Docker/local development:

```bash
docker compose exec web bin/rails import:base
```

## Rake task workflows

### `import:base`

File: `lib/tasks/import.rake`

Imports foundational team, season, team-season, conference, and team-conference data.

```bash
bin/rails import:base
```

### `import:games`

File: `lib/tasks/import.rake`

Runs `SyncFullSeasonGamesJob` for every season ordered by year.

```bash
bin/rails import:games
```

### `season:bootstrap`

File: `lib/tasks/season_bootstrap.rake`

Purpose: create/update a season, ensure team seasons exist, optionally sync games, optionally dedupe, and optionally run ratings.

Default year is `2026`.

Example:

```bash
YEAR=2026 bin/rails season:bootstrap
```

Useful environment variables:

- `YEAR`: target season year.
- `START_DATE`: override season start date.
- `END_DATE`: override season end date.
- `SYNC_GAMES`: whether to sync games during bootstrap.
- `SYNC_RESUME`: whether game sync should resume from latest imported game date.
- `SYNC_START_DATE`: override game sync start date.
- `SYNC_END_DATE`: override game sync end date.
- `DEDUPE_GAMES`: whether to run `games:dedupe`.
- `RUN_PRESEASON`: whether to initialize preseason ratings.
- `RUN_RATINGS`: whether to run ratings after sync.
- `RATINGS_RESUME`: whether to resume ratings backfill.
- `RATINGS_START_DATE`: override ratings backfill start date.
- `RATINGS_END_DATE`: override ratings backfill end date.

### `season:sync_games`

File: `lib/tasks/season_bootstrap.rake`

Purpose: sync games for an existing season.

Example:

```bash
YEAR=2026 SYNC_RESUME=true bin/rails season:sync_games
```

It supports:

- `YEAR`
- `SYNC_RESUME`
- `SYNC_START_DATE`
- `SYNC_END_DATE`

### `games:dedupe`

File: `lib/tasks/game_dedupe.rake`

Purpose: remove duplicate games grouped by:

- `home_team_name`
- `away_team_name`
- `start_time.to_date`

It keeps the lowest-id game and deletes duplicate associated `TeamGame` rows. It also deletes odds associations if those classes are defined.

Use this carefully because it deletes records.

## Local Docker examples

From the host, using the local Docker setup:

```bash
docker compose exec web bin/rails import:base
```

Sync all seasons:

```bash
docker compose exec web bin/rails import:games
```

Bootstrap the current target season:

```bash
docker compose exec web bin/rails season:bootstrap YEAR=2026
```

Sync a bounded season window:

```bash
docker compose exec web bin/rails season:sync_games YEAR=2026 SYNC_START_DATE=2025-11-01 SYNC_END_DATE=2025-11-15
```

Run the project setup script:

```bash
docker compose exec web bin/setup_data
```

`bin/setup_data` runs:

1. `bin/rails db:prepare`
2. `bin/rails import:base`
3. `bin/rails import:games`
4. `bin/rails ratings:backfill_all`

## Data integrity notes

- Team identity is resolved by `Team.search` and team aliases. If team names change upstream, update aliases rather than hardcoding importer exceptions when possible.
- Games are matched by home team name, away team name, and calendar date. Be careful changing matching logic because duplicate games can affect ratings and snapshots.
- Scheduled rows intentionally preserve games without complete stats.
- Complete rows must include all required stats before finalization is attempted.
- Finalized games should not be overwritten by later partial/scheduled rows.
- Ratings only use finalized games through `TeamGame` and `Game` queries.
- Sports Reference scraping includes sleeps. Avoid reducing the sleep without considering rate limits and source-site terms.

## Agent guardrails

When changing ingestion code:

- Inspect `SyncDailyGamesJob`, `SyncNightlyGamesJob`, `SyncFullSeasonGamesJob`, `Scraper::GamesScraper`, `Importer::GamesImporter`, and `ProphetRatings::GameFinalizer` first.
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
- `SyncFromLastGamesJob` resumes from the latest imported game date and then can enqueue `UpdateRankingsJob`.
- `SyncFullSeasonGamesJob` handles retry/backoff per date but does not enqueue ratings by itself.
- `SyncTeamGamesJob` is useful for targeted repair but defaults `season_id` to `Season.last.id`.
- `Scraper::GamesScraper#scrape_day_batch` slices with `batch_urls[start_at..end_at]`, which is an inclusive range. Be careful if changing batch semantics.
- `Importer::GamesImporter` logs partial team matches but can still preserve games with missing team-season associations.
- `GameFinalizer` updates prediction errors if a matching prediction and snapshots already exist.
