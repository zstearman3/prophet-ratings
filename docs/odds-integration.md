# Odds Integration

This document captures the current state of the odds integration and the work that appears to remain.

Last audited: 2026-11-02

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

- A usable American price is numeric, real, finite, and has magnitude at least 100.
  Missing values, numeric strings, zero, sub-100 magnitudes, NaN and infinities are
  excluded without coercion. No valid contributing quotes leaves that side unavailable.
- Each valid price `A` becomes an implied probability: `100 / (A + 100)` for
  positive prices, or `abs(A) / (abs(A) + 100)` for negative prices. Take the
  equal-weight mean `p`, retaining bookmaker margin (no de-vig).
- Convert the mean back to American odds: `100 * (1-p) / p` below 0.5,
  `-100 * p / (1-p)` above 0.5, and canonical `+100` at exactly 0.5. Exact ratios
  avoid floating point drift at even money; round only the final price to the
  nearest integer (halfway values away from zero).
- For example, `+100/-102` produces `-101`, `+100/-100` produces `+100`,
  `-150/-145` produces `-147`, and `+130/+135` produces `+132`. A lone valid
  integer quote keeps its price, except `-100` becomes canonical `+100`.
- The spread line is the mode of finite numeric local-home points. Home prices
  contribute only at that line; away prices only at its exact opposite.
- The total line is the mode of all finite numeric total points. Over and under
  prices contribute only at that exact line. A side missing at the selected line
  remains unavailable, even when another line has prices for it.
- Missing, nonnumeric and nonfinite points cannot define a line; zero is a valid
  spread. Both spread and total mode ties retain the first encountered line.

These prices are a **synthetic consensus**, not an executable sportsbook offer.
A bettor must check the actual sportsbook's current line and price. This changes
market representation only: model probabilities, uncertainty, the 5% EV threshold,
side-selection rules, matching and refresh cadence remain unchanged. Raw bookmaker
rows retain their source prices/points, including quotes excluded from consensus;
these mutable rows are audit evidence of the latest import, not an immutable API
response archive.

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
- Moneyline compares only sides with a usable American price. A single priced side can produce a negative-EV, non-recommended result; an unavailable side cannot win the comparison.
- Spread and total keep their existing probability-based selection rule, but skip the market if that selected side has an unusable American price. No `-110` price is assumed, and the selection is not switched to the other side solely because its price is available.
- A refresh retires the game's existing current recommendations before regenerating eligible markets, in the same transaction. Missing or invalid-priced markets, unusable predictions, or deterministic uncertainty therefore cannot leave stale picks current. An explicitly inactive-model evaluation does not retire active-model picks. Historical rows remain stored.

`GenerateBetRecommendationsJob` runs on the serialized `heavy` queue after odds sync or a successful nightly prediction pass. It processes all scheduled games with stored odds whose start time is strictly after the job begins, including future schedule dates. It uses existing predictions and odds; it does not fetch odds or build predictions. Games missing a usable current prediction have their prior recommendations retired, and started, final, and canceled games are excluded. Stored odds are used even if that game's latest import was skipped; there is no new freshness cutoff.

The generator updates existing rows for the same prediction, odds row, and market when rerun. Each game's writes run in a transaction. A generation failure rolls back that game's changes and is logged with its game ID; later games are still processed. The job then raises with the failed game IDs, using the existing retry policy independently of odds sync, so retries do not repeat the API request. Earlier successful games can be revisited on retry without adding duplicate rows. A newly selected prediction can create new recommendation rows while retaining prior rows as non-current.

To run a recommendation refresh without fetching odds:

```ruby
GenerateBetRecommendationsJob.perform_later
```

The `/games/betting` page only displays current recommendations with valid saved
`BetRecommendation#vegas_odds` and eligible prediction participants; it does not
generate them. Invalid legacy rows remain stored, but their picks, ROI/details,
server EV ordering and client EV sort attributes are suppressed while awaiting
refresh. Valid saved picks remain visible even if their mutable `GameOdd` has
changed: selection, line and price come from the recommendation that produced its
EV. Below-threshold selections remain “No play”; legacy rows without a saved side
show “Not saved” rather than inferring a side from later odds.

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
- sorts by recommendation EV for spread, moneyline, or total; the first click on
  each column sorts highest EV first, repeated clicks toggle direction, and
  switching columns starts highest EV first again
- pairs the recommended (or explicitly labeled no-play evaluated) side with its
  saved line/odds in both the summary and expanded details, so refreshed consensus
  odds do not appear beside an older EV
- labels EV as **Expected ROI**, with a tooltip expressing model-estimated net
  profit per $100 wagered, and labels the selected side's model win/cover/over/under
  probability explicitly; these model probabilities remain uncalibrated
- retains model spread and predicted total as supporting comparison details

The page does not filter to games that have odds despite the empty-state copy saying "No games with odds available for this date." It loads all games for the date and then displays missing recommendations as "No recommendation."

## Bounded post-deploy recovery and verification

Code deployment alone does **not** recalculate stored `GameOdd` or
`BetRecommendation` rows. This implementation performs no production repair or
historical regeneration. Any operational writes below require separate approval
for an explicit game-ID list and schedule-date window.

1. Inventory the affected games before writing: record the reviewed IDs, schedule
   dates, statuses/start times, current odds, recommendation IDs, prediction/model
   IDs, saved prices/lines, EV and current flags. Include current recommendations
   with `vegas_odds BETWEEN -99 AND 99` (the integer column cannot store NaN or
   infinity), and inspect missing/invalid consensus fields. Preserve the relevant
   bookmaker rows, fetched timestamps and the pre-repair export in the approved
   private audit location. Later quotes cannot prove the original input set.
2. Separate upcoming scheduled games from started/final/canceled games. For the
   approved upcoming subset, obtain current quotes once within the approved API
   budget and retain that response. Resolve each payload through the existing
   matching policy and confirm its unique local game is in the reviewed ID list
   and still upcoming **before** passing that payload to `OddsApi::Importer`.
   Import only those confirmed payloads. Stop on ambiguity; do not broaden the ID
   list or substitute historical quotes. An absent payload is unresolved, not a
   successful correction.
3. After verifying each imported consensus, refresh only the approved games still
   scheduled and strictly in the future using
   `BetRecommendationGenerator.call(game: game.reload)`. This uses stored model
   predictions, retires unavailable/invalid markets transactionally and reuses
   same-source rows. Do not enqueue a global sync/refresh for a bounded repair.
   Missing predictions/markets can legitimately leave no current pick; record
   those outcomes. A save failure must leave the game's previous set intact.
4. The ordinary `GenerateBetRecommendationsJob` explicitly excludes started games,
   so it will **not** retire their invalid legacy rows. The display guard hides
   them, but storage can still contain current invalid rows. Handle these in a
   separately authorized, explicit-ID retirement transaction that changes only
   the reviewed recommendations' current flags and retains their saved evidence.
   Do not silently regenerate historical picks using later quotes or delete rows.
5. Reinventory the same IDs/date window: confirm repaired upcoming consensus prices
   are valid integers or unavailable, selected-line prices match retained source
   evidence, current rows use the intended prediction/model/source IDs, and all
   displayed ROI is finite and independently sensible. Count invalid current
   recommendations separately from invalid actionable/displayed ones; the latter
   must be zero, while any remaining started-game rows must be explained. Check
   both EV sort directions and client sort attributes. Compare row IDs/counts,
   preserved historical rows and unrelated games against the export; repeated
   refreshes must not duplicate same-source recommendations.

No broad backfill, database reset, migration, schedule change or production data
write is required to verify this code locally. Use synthetic importer/generator
specs instead of running this procedure during implementation.

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
- `spec/requests/betting_recommendation_details_spec.rb`

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

## Daily simulated results and saved recommendation issues

Run `bin/migrate` to apply `20261108010000` before generating recommendations or
opening Schedule/Betting Recommendations. The additive `bet_recommendation_issues`
table starts empty; there is no backfill or historical quote reconstruction.
Include these append-only evidence rows in database backups.

Each trustworthy pregame refresh captures the complete spread/moneyline/total set
under the game lock, linked to its forecast and model. The issue retains ordered
team/team-season identities and names, selected side, handicap/total, American
price, selected-side model probability, actionable flag, model value, Expected ROI,
quote source/timing and captured tipoff. All markets use one in-memory quote.
Missing markets and unusable quote timestamps are retained as unavailable evidence;
they cannot expose a prior actionable pick. Exact consecutive retries reuse an
issue, while changed evidence appends a revision. Started/final games and unverified
or future-generated forecasts cannot establish pregame issuance. Ordinary model
updates and `destroy!` are blocked for saved issues. Direct `delete` and SQL are
not supported archival-edit paths and are not blocked by Rails read-only protection.
Intentional parent deletion retains existing application deletion behavior through
cascading foreign keys.

`DailyPredictionPerformance` selects the final issue by issuance time and ID for
the exact displayed forecast **before** validating it. Current recommendation flags,
later quotes and eventual outcomes never choose an older issue. Legacy rows remain
visible when no issue exists, explicitly excluded from performance. Participant
corrections suppress old picks; retained source finals and unmatched finals never
grade stale canonical outcomes. Corrected usable canonical final scores recalculate
results without changing the issued recommendation.

`DailyBetResult` and `DailyPerformanceSummary` provide shared read-only settlement
and accounting. Each actionable settled bet risks exactly 1u. Positive American
odds A win A/100u; negative A win 100/abs(A)u; losses return -1u. Pushes return 0u
and count 1u in settled stakes. Pending, void/canceled, No play, unavailable and
excluded records contribute no stakes/profit. Spreads use the saved selected-side
handicap; totals compare the saved over/under line. Realized ROI is total net
profit / total settled stakes, unavailable at zero stakes. Two -110 wins and one
loss produce +0.8181818u / 3u = +27.2727%; calculations are unrounded, with rounding
only for display. Moneyline selections remain independent of the straight-up
favorite. Expected ROI in Details is a pregame model estimate, distinct from
realized returns. This is simulated performance at saved consensus odds.

Daily reads perform no writes. Existing `BetRecommendation#result`/`payout` columns
are not populated by this feature. Automatic post-sync settlement persistence,
retries and correction orchestration belong to the linked population follow-up;
no new cron, sync cadence, model math or recommendation threshold is introduced.
