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
- a betting recommendations table, generator service, and job triggered after odds sync or a nightly prediction pass
- a `/games/betting` page that displays current recommendations

Not yet wired end to end:

- no production-facing observability, retry, or partial-failure handling exists around odds import
- odds sync and prediction generation remain independently scheduled

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
4. The importer finds a unique local game by Eastern schedule date and participant IDs, allowing reversed sides for stored neutral games.
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

### Neutral-site matching and side alignment

The Odds API `home_team`/`away_team` and CBBD `homeTeam`/`awayTeam` are read
literally. The providers can designate opposite sides for neutral-site events;
the schedule importer preserves its provider's designations. Odds matching accepts
reversed participant IDs only when the stored game has `neutral: true` or
`venue_type: neutral`. Games without this evidence still require ordered sides.

Same-date matching uses the Eastern schedule calendar. Neutral games within
three elapsed hours of the API tip time are also candidates across the date
boundary, covering small timestamp disagreements near midnight. This tolerance
is an explicit matching policy, not a correction to the stored schedule or proof
of the actual tip time. It does not allow broad adjacent-day/reschedule matching.
All eligible candidates are considered together: multiple participant matches
raise `ActiveRecord::RecordNotFound` with `Multiple games match odds payload` and
write no odds for that payload, even if one candidate has ordered sides or the
same schedule date. Missing team mappings remain errors.

After matching, exact source outcome labels are aligned to the stored participant
IDs. Consensus moneylines, spread prices and bookmaker `team_side` values use the
local game's home/away orientation. `spread_point` is the mode of **local home
team** spread outcomes only, preserving that team's sign independently of outcome
ordering; absent home spread outcomes leave it unavailable. Totals are unchanged.
No Game, TeamGame, alias, prediction or rating records are rewritten by this match.
Existing odds are corrected on the next successful sync; no historical repair or
historical recommendation regeneration runs automatically.

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

`SyncOddsJob` calls `OddsApi::SyncService`, logs `fetched`, `imported`, and `failed` counts and each failure mapping, then enqueues `GenerateBetRecommendationsJob`. Partial import failures do not prevent this handoff. If fetching odds raises, recommendation generation is not enqueued and the existing application-job retry policy applies.

Production schedules `SyncOddsJob` through the `odds_sync` GoodJob cron entry in `config/environments/production.rb`. The current cadence is every six hours (`0 */6 * * *`). Recommendation generation follows the sync job and successful `GenerateNightlyPredictionsJob` passes; it has no separate cron entry. Manual sync jobs also enqueue recommendations, while calling `OddsApi::SyncService.call` directly only imports odds.

Prediction passes enqueue recommendation generation only after all enclosing transactions commit, including the direct invocation inside CBBD analytics. A rolled-back analytics transaction or failed prediction pass does not release this handoff. This refresh uses stored odds without another API request. Direct per-game prediction-builder calls do not enqueue a batch refresh.

## Consensus Calculation

Service: `OddsApi::ConsensusCalculator`

Consensus behavior:

- moneyline odds are averaged across matching bookmaker outcomes
- spread odds are averaged by side
- spread point is the mode of the local home team's spread outcome points
- total line is the mode of all total points
- over/under odds are averaged by outcome name

Team outcome matching uses:

- `Team#school`
- `Team#the_odds_api_team_id`
- `TeamAlias#value`

The importer supplies exact source labels aligned to local participant IDs.
Direct calculator callers may also supply Team records, using the identifiers
listed above. Spread-line ties retain the first encountered local home line.

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
- the game's current usable prediction for `RatingsConfigVersion.published_default`
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
- Spread and total rows retain the evaluated `team` even below the EV threshold;
  `recommended` determines whether the selection is actionable. Historical no-play
  rows with no saved side remain unchanged and display `Evaluated side: Not saved`.
- Moneyline compares only sides with a stored, nonzero price. A single priced side can produce a negative-EV, non-recommended result; an unavailable side cannot win the comparison.
- Spread and total keep their existing probability-based selection rule, but skip the market if that selected side has a missing or zero price. No `-110` price is assumed, and the selection is not switched to the other side solely because its price is available.
- A refresh retires the game's existing current recommendations before regenerating eligible markets, in the same transaction. Missing markets, unusable predictions, or deterministic uncertainty therefore cannot leave stale picks current. An explicitly inactive-model evaluation does not retire active-model picks. Historical rows remain stored.

`GenerateBetRecommendationsJob` runs on the serialized `heavy` queue after odds sync or a successful nightly prediction pass. It processes all scheduled games with stored odds whose start time is strictly after the job begins, including future schedule dates. It uses existing predictions and odds; it does not fetch odds or build predictions. Games missing a usable current prediction have their prior recommendations retired, and started, final, and canceled games are excluded. Stored odds are used even if that game's latest import was skipped; there is no new freshness cutoff.

The generator updates existing rows for the same prediction, odds row, and market when rerun. Each game's writes run in a transaction. A generation failure rolls back that game's changes and is logged with its game ID; later games are still processed. The job then raises with the failed game IDs, using the existing retry policy independently of odds sync, so retries do not repeat the API request. Earlier successful games can be revisited on retry without adding duplicate rows. A newly selected prediction can create new recommendation rows while retaining prior rows as non-current.

To run a recommendation refresh without fetching odds:

```ruby
GenerateBetRecommendationsJob.perform_later
```

The `/games/betting` page only displays `current_bet_recommendations`; it does not generate them.

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
- pairs the recommended (or explicitly labeled no-play evaluated) side with its
  saved line/odds in both the summary and expanded details, so refreshed consensus
  odds do not appear beside an older EV
- labels EV as **Expected ROI**, with a tooltip expressing model-estimated net
  profit per $100 wagered, and labels the selected side's model win/cover/over/under
  probability explicitly; these model probabilities remain uncalibrated
- retains model spread and predicted total as supporting comparison details

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

- odds sync job delegation, logging, and recommendation-job handoff (including partial failures)
- recommendation generation for upcoming games, eligibility skips, and repeat refreshes without duplicate rows
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
- unmatched team/game handling and logging
- bookmaker uniqueness at the database level, if duplicate rows become a problem

## Likely Next Steps

A pragmatic next increment would be:

1. Add lightweight operational logging or admin visibility for imported, skipped, unmatched, and failed games.
2. Decide whether bookmaker odds need a database-level uniqueness constraint on `game_id`, `bookmaker`, `market`, and `team_name`.

Keep the first production version conservative: import available odds, preserve bookmaker rows, generate recommendations only when required model data exists, and clearly skip games that cannot be matched.
