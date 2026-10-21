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
5. `Importer::GamesImporter.import` translates rows to canonical observations and returns shared persistence reports.
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

With Sports Reference each date gets an initial attempt and up to five retries with 5/10/20/40/80-second
backoff. Imports and completion commit together; failed partial batches roll back.
Recognized empty dates complete with zero rows; failures and interruptions remain
failed/pending. Cumulative attempts, timestamps, row counts and last failure evidence
are persisted. Existing game presence does not create checkpoints automatically.
Completion certifies ingestion of a recognized source date, not finalization,
complete publication or venue coverage. Unmatched, incomplete-final, rejected and
protected reconciliation outcomes fail the date rather than recording completion.

Later dates continue after exhaustion, then `IncompleteSync` raises with a JSON-ready
report (`days`, exact `failed_dates`, bounding `retry_window`). Historical operator
tasks invoke the job body directly so failures exit nonzero instead of silently
enqueuing ActiveJob retries. Sports Reference async jobs retain the existing job retry policy, with
default resume skipping matching completed dates. CBBD uses one explicit run budget
and does not automatically retry incomplete operations; see provider configuration below. The shared date lock prevents concurrent
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

`Ingestion::GameRowEnricher` preserves completion evidence while adding venue/date
enrichment and its actual parser time precision. Canonical import additionally
requires explicit confirmation and complete validated boxes; unmatched observations
remain retained audit outcomes as described below.

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

`import` now returns an array of reconciliation reports. `import_game(row,
season:)` returns the resolved persisted `Game`, or `nil` when no game matched;
`import_report` exposes the full report. `ScheduleRowImporter` returns that same
report. All entry points translate through `SportsReferenceObservationAdapter`
and call `Ingestion::GameObservationImporter`; acquisition never writes boxes
or invokes model math directly.

### Canonical observations (`ingestion-v1`)

Apply migration `20261021010000` before importing. It creates an empty, append-only
`game_observations` audit table; no existing games, identities, forecasts or
snapshots are converted or imported.

A second adapter supplies the same normalized hash (synthetic example):

```ruby
{
  contract_version: 'ingestion-v1', semantic_profile: 'official-team-totals-v1',
  provider: 'synthetic', external_game_id: '00042', season_year: 2027,
  schedule_date: '2026-11-04', start_time: nil,
  source_status: 'scheduled', source_completed: false, completion_evidence: nil,
  captured_at: '2026-11-01T12:00:00Z', source_updated_at: nil,
  source_url: 'https://example.test/games/00042', adapter_revision: 'example-v1',
  raw_payload: {}, payload_digest: nil,
  home: { name: 'Home School', external_team_id: nil, score: nil, stats: {} },
  away: { name: 'Away School', external_team_id: nil, score: nil, stats: {} },
  venue: {}
}
```

`Ingestion::GameObservationImporter.new(observation: payload, season:).call`
returns `outcome`, explicit `reason`, optional `game_id`, `observation_id`,
`accepted`, `applied`, `projected`, `scheduled`, `changes`, `unmatched`, and
`possible_move_ids`. `accepted` identifies a canonical mutation with committed
provider provenance. `projected` identifies a safe missing-ID schedule projection,
which retains `accepted: false`. `applied` counts accepted mutations, unchanged
canonical records, and changed or unchanged safe schedule projections. Held rows
are not counted as imported games. `scheduled` identifies source scheduled rows
for coverage review. Repeats may append attempts, but do not rewrite canonical timestamps, boxes, forecasts, or the accepted provenance head.
New audit records keep the exact original evidence only in `raw_payload`; normalized
JSON excludes that duplicate field. Digests, capture/upstream timestamps, profiles
and append-only history are unchanged; historical audit rows are not rewritten.

Statuses are `scheduled`, `live`, `final`, `postponed`, `cancelled`, `unknown`.
Only `final` plus literal completion confirmation and retained evidence can
finalize. Missing required statistics yield `incomplete`; unmatched participants,
season membership or a required stable result ID yield `unmatched`. Rejections distinguish
`invalid`, `ambiguous`, `conflict`, `stale`, and `superseded`. Missing statistics
are never zero-filled. Counts accept nonnegative integers or digit strings up to
the database integer limit; blanks/null remain unknown. Each side's
`field_availability` retains `observed`, `blank` or `missing` per required count. Only the 18 raw
`TEAM_STAT_KEYS` are accepted; provider-derived possessions/ratings are rejected.
A strict final requires unequal scores, all counts, component consistency,
`duration_minutes` of 40 + 5 per overtime, and side player-minutes of 200 + 25
per overtime. The existing strict finalizer owns derived fields and eligible
prediction outcome errors inside the same transaction.

The approved `official-team-totals-v1` basis includes player and team-charged
rebounds (excluding dead-ball rebounds) and turnovers. The scraper bridge uses
`sports-reference-legacy-v1`: its historical basis is explicitly uncertified,
not silently relabeled official team totals. Mixed profiles are invalid. These
profiles identify input semantics, without tuning formulas or rewriting stored
model configuration hashes. Cross-profile changed finals require review.

Provider IDs are opaque strings. Existing external game identities resolve first;
superseded sources cannot write. Supplied team IDs require an existing exact
`TeamExternalIdentity`; there is no fallback to labels for unmapped IDs. Label
bootstrap requires a unique `Team.matching_school_or_alias` result and existing
TeamSeason for both distinct participants. No teams/memberships are created.
Bootstrap considers unique source URLs and same-date participants, including
legacy date encoding; multiple/cross-season candidates are held. Bootstrap and
source transaction advisory locks persist through the outermost commit; existing
games are row-locked and authority is rechecked. Game, identity, both sides,
finalization and accepted provenance commit atomically. Rejected updates preserve
the exact previous domain state; infrastructure failures propagate.

A stable box URL is the Sports Reference game key. Shared daily schedule URLs
are **not** game identities or URL bootstrap candidates, including when a later
stable-ID observation arrives. A missing-ID row may project only literal
`source_status: scheduled`, `source_completed: false` metadata for two uniquely
resolved, distinct teams with existing memberships. It uses the same bootstrap
and row locks and same-date participant checks (including uniquely resolvable
stored aliases when membership links are missing); it never guesses a cross-date
reschedule from a shared source document. New Games retain a document URL and
known tip or date sentinel, with membership links for pregame use. Refreshes retain
existing usable URLs and stronger/manual venue evidence. Projection never creates
external identities or copies incoming scores, box counts, derived values, result
statuses or forecast inputs. Completed and canceled Games remain untouched.
Changed projections report `outcome: projected`; repeats report `unchanged`, both
with `projected: true`, `accepted: false`, `applied: true`, the matched `game_id`,
and reason `missing_stable_game_identity_projection`. Accepted provenance is not
replaced. A later compatible stable-ID observation reuses the projected Game.
Other missing-ID statuses and unresolved opponents remain audit-only review
candidates, without creating results or `final_unmatched` Games. Existing
`final_unmatched` records keep their status/local IDs and may promote when a
stable candidate, both memberships and a complete confirmed box resolve.
Unresolved refreshes preserve existing records/associations. No partial participant
replacement or orientation swapping is automatic; conflicts require review.
When a stored side is missing, its existing participant label is checked before
adopting incoming membership: a known different team or ambiguous alias is held
without changing canonical state. An unknown label can resolve through incoming
reviewed identity/membership; no old TeamSeason is invented or required. Existing
TeamGame participant evidence remains authoritative. The legacy status enum and
completed scopes remain compatible.

Changed completed results require the same provider, stable game ID and semantic
profile, with strictly increasing **actual upstream** `source_updated_at` on both
accepted and incoming observations. Older updates are stale; equal contradictory
revisions or unknown ordering are conflicts. Capture time never establishes source
freshness. Legacy finals without accepted provenance cannot silently adopt a
conflicting result. Identical observations from another profile/provider may add
a safe identity but never replace the accepted provenance head. Initial compatible
scheduled-to-final transitions use explicit source completion evidence. Pending
schedule revisions also respect available upstream ordering and provider/profile
authority, including prior compatible projected metadata and successful unchanged
projection attempts. Missing-ID projections compare provider/profile without
inventing or adopting a stable identity. Existing
accepted stable-ID authority remains the head for later canonical updates. Actual
upstream ordering remains protected even after an update with unknown ordering;
older/equal-conflicting changes are held. Unknown ordering permits compatible
pending updates, never final corrections.

Manual venue corrections win. Unknown venue stays unknown. A parsed time carries
`time_precision: 'instant'`; fallback dates carry `'date'`. Legacy adapter rows
without precision default to date-only, even if their Ruby value is a Time.
`start_time` in observation provenance remains null for unknown tips. Game's
existing Eastern-midnight date sentinel remains a storage compatibility convention,
not evidence of an actual midnight tip. Enrichment preserves parser precision.
Known RFC3339 starts must agree with the Eastern schedule date.

Saved forecast contexts, snapshot IDs and source identities stay frozen; only
eligible actual-result evaluations are recalculated by the existing finalizer.
Participant conflicts preserve sides and forecasts. No observation writes rating
snapshots or changes published model assumptions.

Historical reconciliation fails the entire date for invalid, ambiguous or
conflicting observations. Accepted rows/audits roll back together; rejected raw
and normalized evidence is retained after that rollback, with rolled-back foreign
keys removed. Stale/superseded rows are safe skips. Unmatched, unchanged and valid
nonfinal rows retain distinct reports without claiming strict finalization.
Future refresh includes matched/projected IDs in its seen set. If a scheduled
source row has no safely matched local Game, absence conclusions are suppressed
for its entire date. Fully reconciled dates and recognized empty dates still
report genuine absences; ambiguity/conflicts still fail and roll back the date.

## Provider-scoped external identities

`TeamExternalIdentity` and `GameExternalIdentity` attach durable provider keys to
existing local records. The shared importer uses these identities before conservative bootstrap discovery. Adding an identity preserves
Prophet primary keys, team-game relationships, predictions, aliases, manual venue
corrections and existing odds identifiers. The migration creates empty tables;
it does not convert aliases, guess mappings or backfill provider IDs.

Supply stable string identifiers. Provider namespaces and external IDs are opaque,
case-sensitive and nonblank: no trimming or lowercasing occurs, and `"00042"` is
distinct from `"42"`. Rails string attributes can cast numeric input, so callers
must preserve the provider's original string rather than converting it to a number.
Each entity type has a database-unique `(provider, external_id)` and a real foreign
key to its local owner. Team and game keys occupy separate namespaces.

```ruby
TeamExternalIdentity.associate!(team:, provider: 'provider_a', external_id: '00042')
TeamExternalIdentity.associate!(team:, provider: 'provider_b', external_id: '00042')
GameExternalIdentity.associate!(game:, provider: 'provider_a', external_id: 'source-game-1')
GameExternalIdentity.associate!(game:, provider: 'provider_b', external_id: 'another-key')

identity = TeamExternalIdentity.find_by(provider: 'provider_b', external_id: '00042')
identity&.team # nil lookup when no exact mapping exists
```

Repeated `associate!` returns the same identity without changing its timestamps.
An existing key assigned to a different owner raises that model's `Conflict`;
it never reparents the mapping. Normal model updates cannot change provider,
external ID or owner. Invalid attributes raise `ActiveRecord::RecordInvalid`.
Database indexes arbitrate competing inserts. A game has at most one active key
per provider, while keys from different providers may coexist; this establishes
no cross-provider update precedence.

A reviewed reschedule/source replacement explicitly retires the old game key:

```ruby
old_source = GameExternalIdentity.find_by!(provider: 'provider_a', external_id: 'source-game-1')
new_source = old_source.supersede!(external_id: 'source-game-2')
old_source.reload.superseded? # true; old key still resolves to the same game
new_source.superseded?        # false
GameExternalIdentity.active.where(game:)
```

Replacement locks the game and reloads the source inside a transaction savepoint.
The original mapping remains with `superseded_at`; the replacement keeps the same
local game/provider. Blank targets, ownership conflicts and persistence failures
roll back retirement and all replacement writes, even if an outer transaction
rescues the error. `supersede!` raises; `supersede` returns false for validation or
authority conflicts and still propagates unexpected persistence failures. Reload
objects after a failed write before inspecting their persisted state.

A same-key request on an active source is a no-op. Retrying a retired source is
idempotent only when the requested key is currently active for that game/provider.
A different target, a target retired by a later replacement, or a retired key
requested as a new replacement raises `GameExternalIdentity::Conflict`. Repeated
association of a retired key returns it as superseded and never reactivates it.
Normal timestamp updates cannot retire or reactivate a source.

The shared importer reloads authority under the game lock before applying
observations. Reviewed mapping and bulk reconciliation belong to ticket 05;
`TeamAlias` remains a separate label/bootstrap discovery mechanism.

Identity-bearing teams/games cannot be destroyed: association restrictions run
before destructive dependent callbacks, and foreign keys also protect database
ownership. Duplicate-game repair checks all planned deletion candidates for any
external identities, including superseded ones, and immutable observations of any
outcome before applying any group. It raises `ArgumentError` with the sorted
affected game IDs and an instruction to review identity mappings or observation history before repair (identity guidance
takes priority when both exist). Resolve protected duplicates through reviewed
work first; repair does not transfer or delete either history. Dry runs remain
read-only, and evidence on the chosen survivor alone does not prevent repair.
Each group is checked again after its game locks and frozen-forecast validation,
before dependent moves. Evidence added after preflight can therefore reject a
later group; groups already committed remain applied in that concurrent case.

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

Before any group is applied, deletion candidates with external identities
(including superseded mappings) or immutable observations reject the run with an
`ArgumentError` listing sorted affected game IDs. Review identity mappings or
observation history before retrying; identity errors take priority. Repair neither
transfers nor deletes that evidence. Protected survivors are allowed, and dry
runs still report planned groups without writes. After locking each group and
validating frozen forecasts, apply rechecks deletion candidates before merging.
Concurrent protected evidence added after preflight can reject a later group without
undoing earlier committed groups.

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

## CBBD bounded dry run and replay

`Ingestion::Cbbd::Adapter` is an additive, file-only acquisition adapter. It does
not call the importer, resolve local team identities, write games, enqueue jobs,
activate a provider or change ratings. Its canonical observations use format
`ingestion-v1`, normalization version `1` and semantic profile
`official-team-totals-v1`. This records the October 20, 2026 approved official team
rebound/turnover basis separately from legacy data: rebounds include team rebounds
and exclude dead-ball rebounds; `turnovers.total` includes team turnovers, with no
addition/subtraction of `teamTotal`. Existing formula coefficients stay unchanged.
Vendor possessions, ratings and Four Factors are excluded from canonical inputs.

Supply the API key securely through `CBBD_API_KEY` in the runtime environment;
never put it in command arguments, tracked files or reports. Example bounded
commands, inside the application's configured runtime:

```bash
SEASON=2026 START_DATE=2025-11-01 END_DATE=2025-11-02 \
  CAPTURE_DIRECTORY=/private/persistent/cbbd bundle exec rake cbbd:dry_run
MANIFEST=/private/persistent/cbbd/run-UUID.json bundle exec rake cbbd:replay
```

Dates must be explicit strict `YYYY-MM-DD`, ordered and within July 1 through
June 30 of the ending-year season. Bounds are inclusive Eastern calendar dates,
converted to UTC through the last millisecond of the final date, including DST.
These are source observation bounds, not a claim that every scheduled game has
been published. The command prints a small JSON summary and private manifest path;
acquisition failures, unresolved coverage, conflicting duplicates/metadata and
orphan boxes exit nonzero. Missing/invalid numeric boxes are retained with reasons
and counted separately; acquisition success is not statistical or model eligibility.

The adapter reads `/games` and `/games/teams` only. Public OpenAPI 1.30.1 inspected
October 20, 2026 describes both as returning up to 3,000 games, with inclusive
`startDateRange`/`endDateRange`, no pagination. Retained feasibility evidence observed
3,000 team rows. Both endpoints therefore conservatively treat **3,000 rows** as
saturated. Saturation splits the same bounded interval into overlapping inclusive
children. Identical identities deduplicate deterministically; disagreement remains
incomplete with both references. Repeated duplicate rows count toward saturation.
Saturation at a one-second interval is incomplete. The estimate starts at two
requests; subdivision is data-dependent and is not an exact call estimate.

Default limits are 50 total HTTP attempts across both endpoints, including retries,
and two extra attempts per request. Ruby callers can lower `max_requests:` or change
`retries:` (0–5); tests inject a small `row_cap:`. Timeout, transport/5xx and 429
responses can retry with 1/2-second backoff. Numeric or HTTP-date `Retry-After` is
honored; a delay above 30 seconds stops retries instead of waiting a shorter time.
401/403 authentication, other HTTP failures (including redirects), malformed JSON
and malformed envelopes are distinct non-retried outcomes. Redirects are never
followed. Production quota/cap stability is not guaranteed; no authenticated live
verification was performed for this implementation.

Each attempt retains a unique immutable `.body` plus metadata `.json`: safe
endpoint/filters, UTC capture time, status/outcome, digest/byte size and allowlisted
quota/retry headers. Network exception messages are discarded. Credentials and
request headers are never retained; exact API-key echoes are redacted from response
bytes/allowed headers and sanitized bodies are labelled. Digests describe retained
bytes after any redaction. Capture failures raise rather than claiming acquisition
success. Files use mode 0600 and the explicit directory 0700. Choose a private
persistent mounted directory when running in containers; application deployment does
not provision one. The operator owns backups, retention and deliberate removal.
Do not commit raw captures or share the directory as public assets.

The run manifest records requested bounds, every attempt and partition, selected
successful leaf capture IDs, original failures and deterministic duplicate/conflict
decisions. Saturated parents and failed attempts remain separate evidence. Replay
verifies **every** retained body digest, reconstructs only selected leaves and
original duplicate decisions, then runs the current normalizer without API keys
or HTTP. Original acquisition failures/completeness and capture times are preserved;
replay cannot upgrade incomplete acquisition. Treat the manifest as trusted private
input (body digests are integrity checks, not cryptographic authentication of the
manifest). New source corrections require a new capture/run and never overwrite old
evidence. Normalization versions identify changed interpretations on later replays.

Every one of the 18 basic totals retains value, availability/reason, raw value,
source path, units and derivation. Absent, null, blank and invalid values never turn
into zero. Nonnegative representable integer counts and lossless trimmed digit
strings are accepted; booleans, fractions, negatives and overflow are rejected.
`gameMinutes` converts once to summed player minutes (40→200, 45→225), with equal
side duration, regulation/OT grid, period, shooting, rebound, score and positive
possession checks. Mirrors are checked when supplied, never used to fill missing
authoritative totals. Conflicting participant/orientation/season/date/status/neutral
metadata rejects the observation; orphan boxes remain visible in the report.

Canonical statuses are scheduled/live/final/postponed/cancelled/unknown. Only literal
source `final` with unequal valid integer scores and no contradictory box status
confirms completion. A malformed final keeps its final claim and rejection reasons.
Scheduled/postponed/cancelled zero scores are unknown placeholders with raw zeros
retained. A timezone is required for an exact instant. A CBBD TBD timestamp supplies
its Eastern schedule date by the provider timestamp convention, while the start
instant stays null. Missing/invalid timestamps retain unknowns; no midnight is
invented. Only `neutralSite: true` proves a neutral venue; false/absent leaves venue
certainty unknown. Home/away orientation does not establish home venue. All internal
identities remain unmapped and every observation has `model_eligible: false`.

Offline tests use small synthetic provider-shaped fixtures. They exercise failures,
bounded splitting, replay and statistical edge cases, not provider-wide live payload
coverage or an SLA. No production ingestion path consumes these observations yet.

## Provider-aware sync and completion scope

`SyncFullSeasonGamesJob`, `SyncDailyGamesJob`, `SyncNightlyGamesJob` and
`FutureScheduleRefresh` select one provider for each operation. `GAME_SYNC_PROVIDER`
defaults to `sports_reference`; Ruby callers can supply `provider:` and
`provider_options:`. There is no fallback or provider blending. Historical and
future windows use strict inclusive `YYYY-MM-DD` Eastern schedule dates inside the
explicit season. A daily CBBD call requires `season_id:`. Nightly passes its target
season through the same atomic date importer, and incomplete dates prevent rankings.

Apply the additive `ScopeGameSyncDatesToProvider` migration before using these
entry points. Completion now identifies season/date/provider/contract/semantic
profile/adapter revision. Existing rows keep their attempts/status/error and are
marked `legacy-unscoped`; they do not certify the current Sports Reference bridge
or CBBD. The first current-scope run revisits them. Resume skips only matching
completed dates; a normalization revision invalidates incompatible completion.
Imports and date completion commit together under the shared provider-neutral date
lock. Existing identity/bootstrap/game locks also serialize cross-provider games
and known identities that move across dates. Unknown cross-provider moves remain
held for review. Source absence never deletes or cancels a stored game.

CBBD requires reviewed team mappings and explicit runtime configuration:

- `CBBD_API_KEY` through the runtime environment; never include it in commands/logs.
- `CBBD_CAPTURE_DIRECTORY`, a private writable evidence directory (captures are 0600,
  directory 0700). It must persist for operator review/replay and needs an operator
  retention/storage policy.
- `CBBD_MAX_REQUESTS`, a positive integer covering both endpoints, partitions and
  all retries for the entire operation.
- `CBBD_RETRIES`, an explicit integer from 0 through 5 for bounded transport/quota
  retries. No implicit production request ceiling or correction cadence is activated.

Ruby `provider_options:` accepts corresponding `api_key`, `capture_directory`,
`max_requests` and `retries` values. Do not serialize secrets into queued job
arguments; use runtime environment configuration for async production jobs.
CBBD acquires one bounded range across pending dates, then imports only those dates;
completed interior dates can be retrieved between resume holes but are ignored.
Empty pending sets make no source requests. Reports include provider scope,
retrieval/acquisition completeness, request attempts/retries/quota, private manifest
path, ignored observations, failed/deferred dates and retry windows. Private capture
bodies and normalized source payloads stay out of these reports.

Each date reports valid empty coverage, outcome counts, accepted/protected/rejected/
unmatched/incomplete counts and final-box coverage separately. A recognized empty
window can complete. Scheduled/live rows can succeed without final boxes; final
rows missing required boxes, invalid/conflicting/ambiguous/unmatched rows and stale
or superseded holds leave the date unfinished. Any earlier domain writes on that
date roll back. Retained rejection audits have `accepted:false`, `game_id:nil` and
an explicit `date_rolled_back` reason; failed reports mark `rolled_back` and zero
committed accepted rows. Sports Reference and CBBD both classify final-box coverage
from the current source observation as `complete`, `missing`, `invalid` or
`not_final`; unchanged stored values cannot supply missing source boxes.
`unknown` remains only for callers that provide no observation coverage metadata.
Missing fields and zero values retain original availability evidence in the audit;
no source update timestamp is inferred from capture time.

CBBD date failures do not repeat acquisition, and ActiveJob does not automatically
retry incomplete CBBD runs with a new budget. Operator tasks print structured
reports and exit nonzero. Inspect the private manifest, repair mappings/evidence
or wait for quota recovery, then explicitly resume with a fresh reviewed budget.
An exception during acquisition is memoized as failed for the operation, so later
dates do not renew it. Legacy scraper bounded retry behavior remains available.

After reviewing operational scope and supplying the runtime configuration above:

```bash
GAME_SYNC_PROVIDER=cbbd YEAR=2026 SYNC_START_DATE=2025-11-01 SYNC_END_DATE=2025-11-03 bin/rails season:sync_games
GAME_SYNC_PROVIDER=cbbd YEAR=2026 SYNC_START_DATE=2025-11-01 SYNC_END_DATE=2025-11-03 SYNC_RESUME=false bin/rails season:sync_games
GAME_SYNC_PROVIDER=cbbd YEAR=2027 SCHEDULE_START_DATE=2026-11-01 SCHEDULE_END_DATE=2026-11-03 bin/rails season:refresh_schedule
```

`SYNC_RESUME=false` is an explicit correction rescan. Future refresh always revisits
its bounded dates and reports absences only for fully successful dates, including
globally seen moved-game IDs. Nightly CBBD additionally requires explicit
`past_lookback_days:` and `future_end_date:` and refuses `enqueue_rankings:true`;
there is no new scheduled CBBD activation. Review production mappings, budgets,
correction/lookahead cadence and capture storage before enabling it. Verification
uses synthetic HTTP responses and disposable databases; no live source coverage,
quota plan or production operational readiness is established by the test suite.
