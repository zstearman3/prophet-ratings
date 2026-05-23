# Odds Integration

This document captures the current state of the odds integration and the work that appears to remain.

Last audited: 2026-05-23

## Summary

The app has a partial integration with The Odds API for college basketball odds.

Implemented:

- an API client for `basketball_ncaab` odds
- a sync service that fetches current odds and imports returned games
- a thin job wrapper that calls the sync service and logs summary/failure details
- persistence for consensus game odds and per-bookmaker odds
- team alias / external ID support for matching The Odds API team names to local teams
- importer and consensus-calculation services with specs
- a betting recommendations table and generator service
- a `/games/betting` page that displays current recommendations

Not yet wired end to end:

- no recurring schedule currently enqueues the live odds sync job
- no existing workflow appears to run `BetRecommendationGenerator` after odds or predictions change
- no production-facing observability, retry, or partial-failure handling exists around odds import
- odds are not yet linked into a daily ingestion/prediction pipeline

## External Source

The current client is `OddsApi::Client`.

File: `app/services/odds_api/client.rb`

It calls:

```text
https://api.the-odds-api.com/v4/sports/basketball_ncaab/odds
```

with these request parameters:

- `regions: us`
- `markets: spreads,totals,h2h`
- `oddsFormat: american`
- `dateFormat: iso`

The client reads `ODDS_API_KEY` from the environment with `ENV.fetch`, so invoking the client without the key raises immediately. `docs/development.md` correctly treats this key as optional for booting the app, but it is required for live odds fetching.

## Data Model

### `game_odds`

Model: `GameOdd`

Purpose: one consensus odds row per game.

Important columns:

- `game_id`
- `fetched_at`
- `moneyline_home`
- `moneyline_away`
- `spread_point`
- `spread_home_odds`
- `spread_away_odds`
- `total_points`
- `total_over_odds`
- `total_under_odds`

There is a unique index on `game_id`, so each game should have only one consensus odds row.

### `bookmaker_odds`

Model: `BookmakerOdd`

Purpose: preserve sportsbook-level market outcomes for audit/debugging.

Important columns:

- `game_id`
- `bookmaker`
- `fetched_at`
- `market`
- `team_name`
- `team_side`
- `value`
- `odds`

Markets currently use The Odds API keys:

- `h2h` for moneyline
- `spreads` for point spread
- `totals` for over/under

The importer uses `find_or_initialize_by(game:, bookmaker:, market:, team_name:)` to update bookmaker rows, but the database currently only indexes `game_id`. Duplicate prevention for bookmaker odds is therefore application-level, not database-enforced.

### `teams.the_odds_api_team_id`

Teams have a nullable `the_odds_api_team_id` column with a unique index. The matching code also uses `TeamAlias` rows, which are important because The Odds API team display names often differ from the app's `Team#school` values.

### Legacy prediction odds fields

`predictions` still has `vegas_spread` and `vegas_total` columns, but the audited code does not currently read or write them. The active odds path is `GameOdd` plus `BetRecommendation`.

## Import Flow

The intended low-level flow is:

1. `OddsApi::SyncService.call` fetches current odds through `OddsApi::Client`.
2. The sync service imports each returned game independently through `OddsApi::Importer`.
3. `TeamMatcher` matches `home_team` and `away_team` names from each payload game.
4. `Game.on_schedule_date(Game.schedule_date_for(commence_time))` finds the local game by schedule date and team IDs.
5. `OddsApi::ConsensusCalculator` calculates consensus values.
6. `GameOdd` is created or updated.
7. `BookmakerOdd` rows are created or updated.

Important behavior:

- Imports are idempotent for `GameOdd`.
- Imports are intended to be idempotent for `BookmakerOdd` by lookup key.
- The importer supports symbol and string payload keys.
- The importer raises `ActiveRecord::RecordNotFound` if teams or local games cannot be matched.
- The sync service rescues expected per-game matching failures, continues importing other games, and returns failure details with the API game id, team names, commence time, error class, and message.
- Consensus `GameOdd#fetched_at` is set to `Time.current`, while bookmaker rows use API `last_update` timestamps.

Example manual sync from Rails console:

```ruby
result = OddsApi::SyncService.call
result.fetched_count
result.imported_count
result.failed_count
result.failures
```

An empty out-of-season API response is treated as a successful sync with zero fetched, imported, and failed games.

The job wrapper can be run manually with:

```ruby
SyncOddsJob.perform_later
```

`SyncOddsJob` is intentionally thin. It calls `OddsApi::SyncService`, logs `fetched`, `imported`, and `failed` counts, and logs each failure mapping. It does not own retry policy or scheduling.

## Consensus Calculation

Service: `OddsApi::ConsensusCalculator`

Consensus behavior:

- moneyline odds are averaged across matching bookmaker outcomes
- spread odds are averaged by side
- spread point is the mode of all spread outcome points
- total line is the mode of all total points
- over/under odds are averaged by outcome name

Team outcome matching uses:

- `Team#school`
- `Team#the_odds_api_team_id`
- `TeamAlias#value`

One caveat: the spread-point mode is calculated across both sides of the spread market. Since home and away outcomes are inverse signs, ties can depend on payload order. If this becomes model-critical, prefer deriving `spread_point` from the home-team outcome only.

## Team Matching Support

There are two odds-related team mapping tasks:

```bash
bin/rails teams:match_the_odds_api_ids
bin/rails teams:import_odds_api_aliases
```

Files:

- `lib/tasks/match_the_odds_api_ids.rake`
- `lib/tasks/odds_api_aliases.rake`
- `db/data/the-odds-api-team-map.json`
- `db/data/odds_api_matches.csv`

`teams:match_the_odds_api_ids` reads the JSON mapping and writes `the_odds_api_team_id`.

`teams:import_odds_api_aliases` reads the CSV and creates `TeamAlias` records with `source: odds-api`.

These tasks are setup/backfill helpers. They do not fetch or import game odds.

## Betting Recommendations

Service: `BetRecommendationGenerator`

Input requirements:

- a game
- the game's current prediction for `RatingsConfigVersion.current`
- the game's `GameOdd`

Generated bet types:

- `spread`
- `moneyline`
- `total`

The generator stores rows in `bet_recommendations` and marks current rows when the prediction's ratings config version is current. It compares model projections against market odds and uses `config/betting.yml` for the recommended EV threshold.

Important details:

- `recommended_ev_threshold` is currently `0.05`.
- Spread and total probabilities use a normal CDF against prediction standard deviations.
- Moneyline EV uses `prediction.home_win_probability`.
- Existing current recommendations for the same game and bet type are marked non-current before saving a new current recommendation.

Current gap: no audited job, rake task, controller action, or importer callback invokes `BetRecommendationGenerator` automatically. The `/games/betting` page only displays `current_bet_recommendations`; it does not generate them.

## UI Surface

Route:

```text
GET /games/betting
```

Files:

- `app/controllers/games_controller.rb`
- `app/views/games/betting.html.erb`
- `app/javascript/controllers/betting_expand_controller.js`
- `app/javascript/controllers/betting_sort_controller.js`

The page:

- filters by schedule date
- loads predictions, `game_odd`, and current bet recommendations
- sorts by recommendation EV for spread, moneyline, or total
- expands rows to show model value, Vegas line/odds, EV, and confidence

The page does not filter to games that have odds despite the empty-state copy saying "No games with odds available for this date." It loads all games for the date and then displays missing recommendations as "No recommendation."

## Local Development Helpers

Fake local odds can be seeded with:

```bash
bin/rails fake_odds:seed
```

File: `lib/tasks/seed_fake_odds.rake`

This task is development-only and should not be used in production. It creates fake `GameOdd` and `BookmakerOdd` records for existing games.

## Existing Tests

Relevant specs:

- `spec/services/odds_api/importer_spec.rb`
- `spec/services/odds_api/consensus_calculator_spec.rb`
- `spec/services/bet_recommendation_generator_spec.rb`
- `spec/models/game_odd_spec.rb`
- `spec/models/bookmaker_odd_spec.rb`
- `spec/models/bet_recommendation_spec.rb`

Coverage exists for:

- odds sync job delegation and logging
- syncing live odds from an injectable client
- empty odds responses
- per-game matching failures during sync
- importing consensus and bookmaker odds from a symbolized payload
- repeat imports updating existing odds rows
- consensus moneyline, spread, and total calculations
- missing market handling
- spread, moneyline, and total recommendation creation

Coverage gaps to address when finishing the integration:

- `OddsApi::Client` request/response behavior
- an end-to-end odds sync task/job schedule
- unmatched team/game handling and logging
- recommendation refresh after odds import
- bookmaker uniqueness at the database level, if duplicate rows become a problem

## Likely Next Steps

A pragmatic next increment would be:

1. Add a recurring schedule for `SyncOddsJob` on a conservative cadence, such as every six hours during the season.
2. After odds import, generate recommendations for games that have both current predictions and `GameOdd` rows.
3. Add lightweight operational logging or admin visibility for imported, skipped, unmatched, and failed games.
4. Decide whether bookmaker odds need a database-level uniqueness constraint on `game_id`, `bookmaker`, `market`, and `team_name`.

Keep the first production version conservative: import available odds, preserve bookmaker rows, generate recommendations only when required model data exists, and clearly skip games that cannot be matched.
