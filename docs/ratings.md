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
4. Fill missing core values from stored preseason values or configured baselines, then recalculate aggregate ratings, home boost defaults, volatility defaults, and ranks.
5. Update season-level adjusted averages through `Season#update_adjusted_averages`.
6. Create or update rating snapshots through `TeamRatingSnapshotService`.

The adjusted-ratings step only runs when both are true:

- `as_of.to_date - season.start_date > preseason.adjustment_start_after_days` (currently 14)
- At least two teams have at least two finalized team games as of the cutoff

Ranks, prediction defaults and snapshots are published even if adjusted ratings are skipped.

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

The solver writes only qualified teams. It no longer resets all teams to season
averages: zero/one-game teams retain their published preseason core values. Missing
core values fall back individually to stored preseason values, then configured
105.5 efficiency and 69.5 pace. No new game-count blending or coefficient change
is introduced.

Each raw stat is then processed by `ProphetRatings::AdjustedStatCalculator`.

## Least-squares adjustment model

`AdjustedStatCalculator` builds a weighted least-squares problem for each stat.

Qualified teams are teams with at least two finalized games as of the cutoff. Teams are sorted by `team_id` so the solver input is deterministic.

For each finalized game, the calculator creates two observations:

- Home team offense vs away team defense
- Away team offense vs home team defense

For each observation:

- The observed value comes from the relevant `TeamGame` stat.
- For `possessions`, pace is normalized through `Game#pace` to possessions per 40 minutes. Games with missing possessions or missing/nonpositive minutes are skipped by the existing blank-observation check.
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

### Prior and optional profiles

The `v1.3-preseason-safety` bundle makes prior assumptions explicit under
`preseason` in `config/ratings.yml`. Each stat retains 85% of the previous
season's team adjusted value and 15% of its previous-season baseline. Offense
and defense use their respective stored adjusted season averages, falling back
to the previous season's raw average efficiency, then 105.5. Pace uses the
previous season's average pace, then 69.5. Missing team history for an individual
stat uses that stat's baseline entirely. Only the immediately previous season
is used; multiyear weighting and stronger regression await the linked evaluation
story's comparison rather than assuming accuracy gains.

Optional `TeamOffseasonProfile` effects retain the existing per-side units:
`recruiting_score * 0.1 - 5 * (1 - returning_minutes_pct) + manual_adjustment`.
Recruiting score is an optional non-negative finite score in the existing local
scale, not a class rank or a standardized provider metric. Returning minutes
must be a fraction from 0 to 1 (80% is stored as 0.8). Manual adjustment is a
finite efficiency adjustment in points per 100 possessions **per side**.
Each missing component contributes zero; an empty profile equals no profile.
Unused class rank, coaching change, lost starters and returning BPM are not
model evidence. Legacy non-finite/negative recruiting scores and invalid
returning fractions are ignored during calculation; new invalid values fail
model validation.

The combined profile adjustment is clamped to +/-5 per side, added to offense
and subtracted from defense. Its maximum net-rating effect is therefore +/-10
points per 100 possessions. This cap is a safety bound using the existing full
attrition magnitude, not a fitted coefficient or evidence of predictive skill.
For example, score 40, returning fraction 0.8, and manual adjustment +1 give
`4 - 1 + 1 = 4` per side and +8 net rating. A missing profile gives zero;
a score of one million is bounded to +5 per side. Profile units and signs remain
compatible with existing finite inputs inside the bounds. Partial profiles now
use only their supplied components, replacing the old assumed +3 recruitment
and -3 attrition contributions.

The `v1.4-captured-priors` bundle retains these coefficients and freezes inputs
once per team-season/configuration in `PreseasonPrior`. Captures contain source
identities and timestamps, stored source attributes, per-stat baseline/previous
values, normalized profile components, the full ratings configuration, and
calculated outputs rounded to the published three-decimal precision. Invalid legacy profile components retain their original
representation in source attributes but contribute zero to calculations.
`PreseasonPriorFormula` replays this contract without reading mutable sources.

The calculator locks the target season and captures/updates all its priors in one
transaction; partial failure rolls back the entire publication. Repeated runs
reuse captured outputs even if source history, season averages, or profiles
change. Corrected inputs require a new `bundle_name`; existing captures are
read-only through Active Record, and existing configuration names/values cannot
be edited or silently reused for changed assumptions. This is application-level
immutability, not a database guarantee against direct SQL. Old configuration
versions and snapshots are not rewritten or retroactively labeled reproducible.

New rating snapshots embed the matching capture's identity, inputs, outputs, and
capture time in `stats.preseason_prior`. A snapshot without that metadata is a
legacy/uncaptured output. Publication rejects a mismatch between a matching
capture and live preseason fields, preventing model switches or manual edits
from attaching incorrect provenance. Snapshot publication is atomic across the
season: a failure rolls back earlier inserts and updates for that run, preserving
existing snapshots even when an enclosing caller rescues the error. Rerun the
preseason calculator for the intended bundle to apply its capture before retrying.
In-season adjusted values remain distinct from the
captured preseason outputs. Deployment requires the additive `preseason_priors`
migration before invoking the calculator or snapshot writer; no existing
historical capture is fabricated by the migration.

Some adjusted values can blend with preseason values on `TeamSeason`:

- `preseason_adj_offensive_efficiency`
- `preseason_adj_defensive_efficiency`
- `preseason_adj_pace`

The preseason weight decays linearly from season start using:

- `weighting.preseason_decay_days`
- `weighting.min_preseason_weight`

Formula:

```text
days_since_start = max(as_of_date - start_date, 0)
weight = max(1.0 - days_since_start / preseason_decay_days, min_preseason_weight)
blended = weight * preseason_value + (1 - weight) * observed_adjusted_value
```

If the preseason value is blank, the observed adjusted value is used directly.
Clamping elapsed days to zero prevents a weight above 1 before season start.
With the retained 40-day decay and 10% floor, a prior of 120 and observed value
100 produce 120 at/before opening day, 110 at day 20, and 102 from day 36 onward.
The two-week gate, two-game qualification, calendar decay and permanent floor
remain baseline choices pending comparison with game-count decay. Synthetic
checks establish arithmetic and bounds, not calibration or improved accuracy.

### Opening-period uncertainty assessment

The configured efficiency volatility fallback remains 11.5 and pace fallback
4.5. Aggregation uses the efficiency baseline with fewer than four residuals,
then blends empirical volatility toward it. `VolatilityCalculator` falls back
to mutable season deviations when snapshot volatility is absent. Equal
volatilities yield a `High` confidence label under the existing gap rule even
when both are defaults: this label is not evidence of opening-period
calibration. `GamePredictor` also scales score volatility by pace squared before
combining standard deviations; its dimensional interpretation needs validation
in the comparison before changing probabilities. No calibration improvement or
empirical confidence claim is established by this safety change.

The existing evaluator's win accuracy and plot do not provide a leakage-safe
opening-month Brier score, log loss, or reliability report. The prediction builder
allows snapshots on the game's schedule date, and ratings backfills calculate
that day's ratings before predictions, potentially including the result being
predicted. The separate read-only `ratings:compare_preseason` benchmark avoids these paths;
see [the comparison report](preseason-comparison.md). It retains the current
probability arithmetic and does not establish confidence calibration or justify
changes to the in-season transition. No import or ratings backfill is required.

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

Higher `rating` is better. Ties break by ascending `team_id`; missing adjusted
stats have no rank. Core ranks/defaults are independent of the solver gate.

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

Snapshots are associated with a `RatingsConfigVersion` produced from the active `config/ratings.yml` bundle. The lookup is based on `bundle_name`. Reusing an existing name with different configuration raises an error; changed assumptions or corrected captured prior inputs require a new bundle name.

## Operational safety

Season preparation/bootstrap never resets live ratings or deletes predictions or
snapshots. Activation is a separate atomic operation. Non-deleting
season:resume_ratings is capped at the Eastern schedule date and ignores future
snapshots as resume points. Destructive season:rebuild_ratings requires explicit
YEAR, REBUILD=true and date boundaries; deletion is restricted to that window and
the active config, with the entire rebuild rolled back on failure. Live team
values reflect the final processed date, so follow historical repairs with a
resume to the intended live cutoff. Backfill prediction ordering is unchanged
and is not a leakage-safe evaluation path.

The shared scheduled rankings advisory lock excludes concurrent setup,
activation, resume, rebuild and nightly prediction writes. Scheduled rankings
skip a busy lock; operator operations fail visibly, while async rating/prediction
jobs use the existing bounded retry policy. See [Offseason Operations](offseason.md)
for commands, dependency checks and recovery. Model coefficients, solver inputs,
ranks and preseason snapshot publication are unchanged by these safety defaults.

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

## Preseason publication contract

The `v1.5-preseason-publication` bundle distinguishes the changed publication,
fallback and ranking behavior without changing solver coefficients. The preseason
initializer publishes atomically at `season.start_date - 1`, reusing the captured
prior inputs from v1.4's contract. It refuses implicit replacement of in-season
outputs; see [Offseason Operations](offseason.md) for rerun/reset semantics.

Before results exist, the prediction efficiency baseline is the published teams'
mean preseason offense; pace is the mean published adjusted pace. Missing season
efficiency/deviations during daily updates fall back to the mean stored preseason
offense (then 105.5), 11.5 efficiency volatility and 4.5 pace volatility. Home
boosts retain +/-2.2 and team volatility uses the existing configured defaults.
Unavailable Five Factors are left null. Equal baseline teams yield neutral scores
of `105.5 * 69.5 / 100 = 73.3225` and win probability 0.5. These defaults support
prediction generation; they do not establish calibrated confidence or accuracy.

The prediction builder defaults to the configured bundle rather than a potentially
stale global current flag. It skips and logs missing/incomplete core snapshot or
pace/volatility inputs. Existing same-day snapshot selection and mutable season
prediction baselines remain limitations for leakage-safe historical evaluation.
