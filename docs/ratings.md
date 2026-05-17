# Ratings System

This document explains how Prophet Ratings currently computes team ratings. It is intended for agents and contributors working on ratings, predictions, snapshots, or model evaluation.

## High-level entry point

The main orchestrator is `ProphetRatings::OverallRatingsCalculator` in `app/services/prophet_ratings/overall_ratings_calculator.rb`.

It is invoked by `UpdateRankingsJob`, which defaults to `Season.current` and then optionally enqueues `GenerateNightlyPredictionsJob` after ratings are updated.

Typical call:

```ruby
ProphetRatings::OverallRatingsCalculator.new(season).call
```

The calculator accepts an `as_of:` cutoff. By default, it uses the earlier of `Time.current` and `Season.current.end_date`.

## Pipeline overview

`OverallRatingsCalculator#call` performs the ratings workflow in this order:

1. Aggregate raw team-season stats through `TeamSeasonStatsAggregator`.
2. Update season-level raw averages through `Season#update_average_ratings`.
3. If the season is far enough along and has enough finalized games, run least-squares adjustments.
4. Recalculate aggregate ratings, home boost defaults, volatility defaults, and ranks.
5. Create or update rating snapshots through `TeamRatingSnapshotService`.
6. Update season-level adjusted averages through `Season#update_adjusted_averages`.

The adjusted-ratings step only runs when both are true:

- `as_of.to_date - season.start_date > 14`
- At least two teams have at least two finalized team games as of the cutoff

Snapshots are still written even if adjusted ratings are skipped.

## Raw stat aggregation

`ProphetRatings::TeamSeasonStatsAggregator` updates each `TeamSeason` from finalized games up to `as_of`.

It calculates direct averages from `TeamGame` values for:

- `turnover_rate`
- `offensive_rebound_rate`
- `free_throw_rate`
- `three_pt_attempt_rate`
- `offensive_efficiency`
- `defensive_efficiency`

It calculates `pace` from game possessions.

It also derives:

- `effective_fg_percentage = (FGM + 0.5 * 3PM) / FGA`
- `three_pt_proficiency = ((2 * 3P%) + 3PA rate) / 3`

The aggregator also updates:

- Offensive and defensive efficiency standard deviations
- Efficiency and pace volatility estimates
- Home offense and defense boosts
- Overall and conference wins/losses

Volatility and home-court values use previous prediction errors when available. If sample size is too small, the code falls back toward configured baselines from `config/ratings.yml`.

## Season averages

After raw aggregation, `Season#update_average_ratings` stores season-level baselines:

- `average_efficiency` from average `TeamSeason#offensive_efficiency`
- `average_pace` from average `TeamSeason#pace`
- `efficiency_std_deviation` from average team offensive-efficiency standard deviation
- `pace_std_deviation` from finalized game paces

These averages become anchors/defaults for the adjustment step.

## Adjusted stats

`OverallRatingsCalculator` defines the adjusted stat bundle:

| Raw stat | Adjusted team stat | Adjusted allowed/opponent stat |
| --- | --- | --- |
| `offensive_efficiency` | `adj_offensive_efficiency` | `adj_defensive_efficiency` |
| `possessions` | `adj_pace` | `adj_pace_allowed` |
| `effective_fg_percentage` | `adj_effective_fg_percentage` | `adj_effective_fg_percentage_allowed` |
| `turnover_rate` | `adj_turnover_rate` | `adj_turnover_rate_forced` |
| `offensive_rebound_rate` | `adj_offensive_rebound_rate` | `adj_defensive_rebound_rate` |
| `free_throw_rate` | `adj_free_throw_rate` | `adj_free_throw_rate_allowed` |
| `three_pt_proficiency` | `adj_three_pt_proficiency` | `adj_three_pt_proficiency_allowed` |

Before solving, the calculator initializes all team seasons in the season with defaults:

- `adj_offensive_efficiency = season.average_efficiency`
- `adj_defensive_efficiency = season.average_efficiency`
- `adj_pace = season.average_pace`

Each raw stat is then processed by `ProphetRatings::AdjustedStatCalculator`.

## Least-squares adjustment model

`AdjustedStatCalculator` builds a weighted least-squares problem for each stat.

Qualified teams are teams with at least two finalized games as of the cutoff. Teams are sorted by `team_id` so the solver input is deterministic.

For each finalized game, the calculator creates two observations:

- Home team offense vs away team defense
- Away team offense vs home team defense

For each observation:

- The observed value comes from the relevant `TeamGame` stat.
- For `possessions`, pace is normalized as `(game.possessions * 40.0) / game.minutes`.
- Home-court adjustment is applied only for stats listed in `ratings.yml` under `home_court_adjusted_stats`, and only for non-neutral games.
- The target value is `observed - home_court - season_average`.
- The matrix row has one coefficient for the offensive team and one for the defensive/opponent team.

Conceptually, each row says:

```text
offensive_team_strength + defensive_team_allowed_effect = observed_stat - home_court - season_average
```

An anchor row is added to keep the offensive side centered around the season average. Its weight comes from `ratings.yml` at `anchor.weight`.

The matrix is solved by `StatisticsUtils.solve_least_squares_with_python`, which invokes `python3 lib/python/adjusted_stat_solver.py` and passes:

- Matrix rows (`a`)
- Target vector (`b`)
- Observation weights (`w`)
- Ridge regularization alpha from `ratings.yml`

The Python solver returns the solution vector. The first half represents team offensive effects; the second half represents defensive/allowed effects. The adjusted values are reconstructed by adding the season average back to each effect.

## Weighting

Observation weights currently come from `ProphetRatings::GameWeightingService`.

The service currently applies recency weighting only:

```text
weight = max(1.0 - ((days_ago / recency_decay_days) * (1 - min_recency_weight)), min_recency_weight)
```

The default config currently uses:

- `recency_decay_days: 60.0`
- `min_recency_weight: 0.75`

Newer games receive more weight, while older games decay toward the minimum.

## Preseason blending

Some adjusted values can blend with preseason values on `TeamSeason`:

- `preseason_adj_offensive_efficiency`
- `preseason_adj_defensive_efficiency`
- `preseason_adj_pace`

The preseason weight decays linearly from season start using:

- `weighting.preseason_decay_days`
- `weighting.min_preseason_weight`

Formula:

```text
weight = max(1.0 - days_since_start / preseason_decay_days, min_preseason_weight)
blended = weight * preseason_value + (1 - weight) * observed_adjusted_value
```

If the preseason value is blank, the observed adjusted value is used directly.

## Home court adjustment

The baseline home-court advantage is configured in `ratings.yml` as `home_court_advantage`.

During matrix construction:

- Confirmed home games receive `+home_court_advantage` for configured home-court-adjusted stats.
- The away observation in confirmed home games receives `-home_court_advantage`.
- Neutral-site games receive no home-court adjustment.
- Unknown-venue games also receive no home-court adjustment.

The adjustment now uses `Game#venue_type` and `Game#venue_confidence` instead of treating a blank `neutral` flag as a normal home game. Only `venue_type = home` with confirmed or manual confidence is considered a confirmed home venue. This keeps missing Sports Reference venue data from silently entering the solver as home-court data.

`TeamSeasonStatsAggregator` also estimates team-specific home boosts from historical prediction errors:

- `home_offense_boost` is non-negative.
- `home_defense_boost` is non-positive.
- Empty or thin samples fall back toward the configured baseline.

`OverallRatingsCalculator#recalculate_all_aggregate_ratings` ensures missing boosts are filled with defaults before totals are computed.

## Volatility

Volatility is used later by predictions and confidence/evaluation logic.

`TeamSeasonStatsAggregator` calculates:

- `offensive_efficiency_volatility`
- `defensive_efficiency_volatility`
- `pace_volatility`

These are based on prediction errors where enough historical prediction data exists. With fewer than four relevant errors, the configured baseline is used.

`OverallRatingsCalculator#recalculate_all_aggregate_ratings` fills missing efficiency volatility values from `baseline_volatility.efficiency_volatility` and computes:

```text
total_volatility = (offensive_efficiency_volatility + defensive_efficiency_volatility) / 2.0
```

## Aggregate rating and ranks

After adjusted stats are solved, `OverallRatingsCalculator#recalculate_all_aggregate_ratings` computes:

```text
rating = adj_offensive_efficiency - adj_defensive_efficiency
total_home_boost = home_offense_boost - home_defense_boost
```

Higher `rating` is better.

Ranks are then assigned across all `TeamSeason` records for the season:

- `overall_rank`: higher `rating` is better
- `adj_offensive_efficiency_rank`: higher is better
- `adj_defensive_efficiency_rank`: lower is better
- `adj_pace_rank`: higher is faster
- `adj_free_throw_rate_rank`: higher is better
- `adj_free_throw_rate_allowed_rank`: lower is better
- `adj_turnover_rate_rank`: lower is better
- `adj_turnover_rate_forced_rank`: higher is better
- `adj_offensive_rebound_rate_rank`: higher is better
- `adj_defensive_rebound_rate_rank`: higher is better
- `adj_effective_fg_percentage_rank`: higher is better
- `adj_effective_fg_percentage_allowed_rank`: lower is better
- `adj_three_pt_proficiency_rank`: higher is better
- `adj_three_pt_proficiency_allowed_rank`: lower is better

The recalculation uses bulk imports to persist computed values and ranks.

## Rating snapshots

`ProphetRatings::TeamRatingSnapshotService` persists daily/as-of rating state.

For each team season, it writes a `TeamRatingSnapshot` keyed by:

- `team_id`
- `season_id`
- `team_season_id`
- `snapshot_date`
- `ratings_config_version`

The snapshot stores top-level columns for:

- `rating`
- `adj_offensive_efficiency`
- `adj_defensive_efficiency`
- `adj_pace`

Other adjusted stats, volatility fields, home-court fields, and ranks are copied into the snapshot `stats` JSONB column.

Snapshots are associated with a `RatingsConfigVersion` produced from the active `config/ratings.yml` bundle. The lookup is based on `bundle_name`, so changing rating assumptions should generally include a new bundle name.

## Configuration

Ratings configuration lives in `config/ratings.yml`.

Important settings:

- `bundle_name`: human-readable/config-version key used by snapshots and predictions
- `weighting.recency_decay_days`: controls how quickly old games lose weight
- `weighting.min_recency_weight`: lower bound for game weights
- `weighting.preseason_decay_days`: controls preseason blend decay
- `weighting.min_preseason_weight`: lower bound for preseason influence
- `blowout.max_margin`: intended blowout cap threshold
- `blowout.cap_multiplier`: intended blowout dampening multiplier
- `baseline_volatility.efficiency_volatility`: fallback offensive/defensive volatility
- `baseline_volatility.pace_volatility`: fallback pace volatility
- `home_court_advantage`: baseline home-court efficiency adjustment
- `home_court_adjusted_stats`: raw stats that receive home-court adjustment in the solver
- `ridge.alpha`: ridge regularization passed to the Python solver
- `anchor.weight`: weight of the centering anchor row

If an agent changes any rating assumption, verify whether `bundle_name` should change so new snapshots remain distinguishable from older outputs.

## Guardrails for agents

When changing ratings code:

- Read `OverallRatingsCalculator`, `AdjustedStatCalculator`, `TeamSeasonStatsAggregator`, `TeamRatingSnapshotService`, and `config/ratings.yml` first.
- Preserve reproducibility for a given ratings config bundle.
- Do not silently change model assumptions without updating tests and considering the config bundle name.
- Keep the Rails/Python boundary simple: Ruby assembles matrices and metadata; Python solves the weighted least-squares system.
- Be careful with `TeamSeason` and `TeamRatingSnapshot` schema changes; predictions depend on stored rating snapshots.
- Keep the `as_of` cutoff behavior intact for backfills and historical validation.
- Add or update tests for behavior changes, especially around missing data, early-season gating, snapshots, and config-version behavior.
- Avoid inventing unsupported matchup or rating narratives. Ratings should remain grounded in stored games, team games, config, and snapshots.

## Current implementation notes

- The adjusted-stat solver only includes teams with at least two finalized games as of the cutoff.
- The top-level adjusted pace snapshot field is stored as `adj_pace`; `adj_pace_allowed` is part of the adjusted stat mapping but is not a visible `TeamSeason` schema field in the current annotation.
- `TeamRatingSnapshot::STORED_STATS` includes `home_total_boost`, while `OverallRatingsCalculator` writes `total_home_boost` on `TeamSeason`. Check naming carefully before relying on that snapshot JSON key.
- `AdjustedStatCalculator#blowout_dampening` currently checks for `offensive_rating` and `defensive_rating`, while the configured adjusted efficiency raw stat is `offensive_efficiency`. Do not assume blowout dampening is active for efficiency without verifying this behavior.
- `GameWeightingService` is initialized with a `TeamGame` object in the adjustment loop, despite the parameter name `game:`. Its recency calculation uses `@game.game.start_time`.
