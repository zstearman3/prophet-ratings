# Ratings System

This document explains how Prophet Ratings currently computes team ratings. It is intended for agents and contributors working on ratings, predictions, snapshots, or model evaluation.

## High-level entry point

The main orchestrator is `ProphetRatings::OverallRatingsCalculator` in `app/services/prophet_ratings/overall_ratings_calculator.rb`.

It is invoked by `UpdateRankingsJob`, which defaults to `Season.current` and then optionally enqueues `GenerateNightlyPredictionsJob` after rating publication and the enclosing transaction commit.

Typical call:

```ruby
ProphetRatings::OverallRatingsCalculator.new(season).call
```

The calculator resolves its target season at initialization and requires a persisted
season with ordered start/end dates. It accepts a Date, a time object, or an exact
`YYYY-MM-DD` string as `as_of:`. Time objects use the Eastern schedule date;
dates retain their calendar meaning. Timestamp strings are rejected instead of
discarding their time/offset. Only an omitted or nil cutoff defaults to today's
Eastern date; invalid values such as false fail before writing. The date is capped at the **target**
season's end. Explicit cutoffs are also capped at that end. The calculator does
not consult another current season or require a current season when given a target.
It permits pre-opening dates for existing callers; preseason publication retains
its separate initializer contract.

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

The entire daily pipeline runs in one transaction with a savepoint, including raw
aggregates, baselines, every stat adjustment, ranks, config creation and snapshots.
A solver or snapshot failure rolls back all daily writes and propagates to the
caller, even if that caller rescues inside its own transaction. Existing snapshots
are restored; a retry reuses the date/config identities. Prediction enqueueing is
deferred until all enclosing transactions commit and is discarded on rollback.
The shared advisory lock and scheduled skip-on-contention behavior are unchanged.
These changes do not alter coefficients or the config bundle and do not repair
existing historical outputs. Direct `publish` remains the preseason initializer's
publication step inside its existing atomic transaction.

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

This records the earlier audit baseline. Shared-pace uncertainty and the frozen
forecast contract below supersede its confidence/arithmetic and new-forecast
input-selection limitations; they do not establish empirical calibration.

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

Snapshots are associated with the `RatingsConfigVersion` selected for the calculation run, including stored ratings, prediction and defaults settings. The lookup is based on `bundle_name`. Reusing an existing name with different configuration raises an error; changed assumptions or corrected captured prior inputs require a new bundle name.

## Operational safety

Preseason initialization publishes prior/live offense, defense, pace, ratings,
core ranks, home boosts, volatility defaults and snapshots dated one day before
season start. Review those outputs and captured prior provenance with the
[offseason readiness checklist](offseason.md#readiness-checklist-and-decision-record)
before declaring a season prediction-ready. Safe repeats reuse captures and
snapshot identities; established in-season outputs are protected. Zero/one-game
teams retain captured core priors while qualified teams receive observed adjustments.
The bounded comparison and its coverage/calibration limits are documented in
[Preseason comparison](preseason-comparison.md); it does not justify an accuracy gain.

This runbook change introduces no additional model or config changes. Record the
bundle name and compare the persisted `RatingsConfigVersion#config` with deployed
YAML. Lookup uses bundle name, with changed configuration under an existing name
rejected. Corrected prior inputs or assumptions require a new bundle name; do not
edit or delete existing captures. Missing history falls back to configured baselines;
fallback confidence and unknown venues are not evidence of calibration.

Season preparation/bootstrap never resets live ratings or deletes predictions or
snapshots. Activation is a separate atomic operation. Non-deleting
season:resume_ratings is capped at the Eastern schedule date and ignores future
snapshots as resume points. Destructive season:rebuild_ratings requires explicit
YEAR, REBUILD=true and date boundaries; deletion is restricted to that window and
the active config, with the entire rebuild rolled back on failure. Live team
values reflect the final processed date, so follow historical repairs with a
resume to the intended live cutoff. Historical resume/rebuild now reconstruct prior-day working inputs before
creating explicitly labeled reconstructions, then publish that day's ratings.
They remain reconstruction tools, not a live forecast archive.

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

The prediction builder defaults to the explicitly active stored model, or an
already-published authored bundle when none is active. It skips and logs missing/incomplete core snapshot or
pace/volatility inputs. Legacy rows retain their same-day selection and mutable-baseline replay limits.
New saved forecasts follow the frozen context contract below.

## Explicit model configuration

The `v1.6-pinned-model` bundle introduces complete stored configuration contract
version 1 without coefficient tuning. All calculation services and solver
parameters use the selected immutable payload. Jobs pin the version ID at
enqueueing and propagate it through retries and downstream predictions.
Publication, read-only selection, and explicit activation are separate operations.
Incomplete legacy payloads remain readable/evaluable as published outputs but
cannot be used for new calculations or faithful replay. Live/prior provenance
must match before snapshot publication; the additive migration fabricates no
historical identity. See [Model configuration versions](model-versions.md) for
the contract, author/publish/select/activate commands, rollout and real-solver
verification. Source-data and calculation-code changes remain rating replay limits;
new saved forecast inputs are captured by the context contract below.

## Shared-pace uncertainty baseline

The authored `v1.7-shared-pace` model selects `prediction.uncertainty_model:
shared_pace_v1`. Independent matchup efficiencies H and A (points per 100
possessions) and one independent normal pace P (possessions per 40 minutes)
produce scores P*H/100 and P*A/100. Offensive performance is the opponent's
defensive performance; no extra defensive outcome is sampled. Each efficiency
variance remains the sum of offense/opponent-defense component variances times
the upset modifier squared. Pace variance remains the sum of both team pace
variances. Residual-derived components are a baseline assumption, not proven
isolated sources of variance; coefficients are unchanged.

With means h, a, p and variances vh, va, vp, score variances are
`((p² + vp)*vh + vp*h²)/10000` and
`((p² + vp)*va + vp*a²)/10000`. Shared pace induces score covariance
`vp*h*a/10000`. Margin and total variances are respectively
`((p² + vp)*(vh + va) + vp*(h-a)²)/10000` and
`((p² + vp)*(vh + va) + vp*(h+a)²)/10000`. SDs are square roots;
product-of-variances terms are retained. At fixed pace SD scales by p/100 once.

Home win probability uses `Phi((h-a)/sqrt(vh+va))`, independently of pace.
With zero efficiency-difference variance it is 1/0 for positive/negative
mean difference, or 0.5 for tied means. This assumes physical positive pace.
The unchanged raw normal pace simulation has a possible nonpositive tail;
its win-frequency agreement is approximate to that tail. There is no clamping,
truncation or distribution change. Score products are not themselves normal.

Finite nonnegative SDs are required; explicit zero is valid. Missing snapshot
SDs in predictor/simulator calculations retain the season deviation, then stored
model baseline fallback. Invalid supplied SDs do not fall back. Missing/nonfinite
core ratings or nonpositive expected pace raise explicit errors. Persisted
uncertainty diagnostics require stored snapshot efficiency and pace SDs, and
use stored prediction means and pace with modifier 1 (the builder's modifier).
The shared-pace builder skips snapshots missing any of these SDs before saving
a prediction, so downstream diagnostics never require mutable fallbacks for
new persisted outputs. Interactive predictor/simulator fallbacks and legacy
builder behavior remain available. Spread recommendations with zero SD are
skipped, matching the existing total-market policy; the recommendation EV model
does not represent push outcomes. For the active model, skipping a deterministic
spread also retires prior current spread recommendations for that game, retaining
their historical records. Inactive-model evaluations leave current recommendations
unchanged. Moneyline recommendations remain available.
Legacy rows retain rounded-mean and mutable-fallback replay limits. New forecasts
use the frozen context contract below, including unrounded intermediate inputs.

The API and matchup UI report confidence as **Uncalibrated**, for every model
and volatility magnitude. Old confidence thresholds remain in the contract for
legacy payload compatibility but do not establish confidence. Correct arithmetic
is not evidence of calibration. Legacy payloads without the uncertainty selector
retain their prior probability and margin/total diagnostic arithmetic; their
stored predictions and immutable payloads are not rewritten.

## Frozen forecast context and revisions

New saved predictions have calculation context contract 1: both snapshots' exact
core ratings and optional volatility/home boosts, source IDs/dates/timestamps,
season efficiency/pace anchors and resolved deviation fallbacks, venue evidence,
modifier 1, and a copy of the selected immutable model payload. Generation and
`Prediction#replay` use these captured values, including unrounded intermediate
means and deviations. Margin/total diagnostics use the same context. Editing a
source snapshot, TeamSeason, season or venue cannot change a saved forecast's
calculation. Replay still depends on the implementation of that model's arithmetic;
this is an input contract, not an archive of historical executable code.

Snapshots must be dated strictly before the game's Eastern schedule date, no
later than the actual generation date, and created/updated by generation time.
There is no same-day intraday exception. Missing eligible or complete inputs skip
with a warning directing the operator to publish complete prior-day snapshots.
No later source is substituted. Anchors/fallbacks are the values available at
actual issuance; they are frozen, not retrospectively reconstructed as-of values.

Each change from the latest issuance appends a revision, including an A → B → A
input correction. Only consecutive identical inputs reuse the latest issuance.
Timestamp-only source touches also reuse it; captured source identities, dates,
values and venue evidence must still match. The original provenance stays frozen.
A SHA-256 key over context, forecast kind, cutoff, captured tipoff and predecessor
ID identifies the revision; per-game locking serializes writes and duplicate retries.
The generation timestamp is actual wall-clock
time and is excluded from the retry key. Rails validations reject changes to
saved context, provenance, source identities or numerical outputs; outcome error
columns remain editable. The database enforces unique game/model/revision keys.
Direct SQL bypasses Rails validations and is not a supported forecast-edit path.

A `pregame` forecast requires a scheduled game, issuance before tipoff, and no
stored game scores. `Prediction.selected_pregame` chooses the latest eligible
issuance for each game/model, ordered by generation time then ID. A corrected earlier tipoff or Eastern date
can disqualify an issuance; both its timestamp and prior-date cutoff must remain
eligible for the current schedule. Display uses
that selection, falling back only to a labeled unverified legacy row when none
exists. Evaluation uses only selected pregame rows for final games. Finalization
attaches outcome errors to the selected pregame row per model, falling back to
legacy error attachment only for game/model pairs without verified issuance.
Residual aggregation uses that same cohort and captured venue, boosts and team
identity for frozen rows; legacy residual behavior remains explicitly compatible.
Neither path replaces inputs.

Legacy rows retain empty context and null generation time and display as
**Unverified legacy forecast**. They remain directly accessible but cannot be
faithfully replayed and are excluded from the pregame evaluator. Building a game
that has started, has scores or is no longer scheduled produces an explicit
**Postgame reconstruction**, with its real generation time. Reconstructions are
accessible through `game.predictions`, but never substitute for a pregame forecast
in display/evaluation. Late-created backdated sources cannot prove live issuance.
Historical ratings workflows may create reconstructions; they are not a live
forecast archive. Nightly prediction jobs now select only scheduled upcoming games.
This contract adds no fitted coefficients or confidence/calibration claims.

## Bounded historical ratings reconstruction

Resume/rebuild restores every team from the selected immutable `PreseasonPrior`
on each calculation date. It validates all three outputs against the captured
formula/config, applies the captured preseason fields/model identity, clears
adjusted Five Factors and core values, then restores captured core values.
Zero/one-game teams and pre-gate dates therefore use captured priors rather than
later live values. Missing, incomplete or inconsistent captures fail visibly;
there is no implicit legacy snapshot/live fallback or new capture from mutable
source history. An explicit preseason initialization/reset is a separate operator
decision and does not prove the prior was available historically.

Raw aggregates, empirical volatility, home boosts, season averages, ranks and
snapshots are recalculated with finalized results bounded by the Eastern cutoff.
Pace deviation now respects that cutoff for ordinary daily calculations too;
zero/one pace observation falls back to the stored model baseline instead of NaN.
No-game raw pace is cleared so an earlier calculation cannot leak into the solve.
Replay residuals use `selected_pregame` for the target season/model, one latest
eligible issuance per game/model, excluding legacy rows, reconstructions and late
revisions. Errors are recomputed in memory from saved means and bounded finalized
results, so prior execution order or outcome-error attachment does not change the
sample. An eligible forecast whose finalized game lacks either team-game record
fails replay visibly and rolls back the date instead of retaining stored errors.
Regular live aggregation retains the explicit legacy compatibility cohort.

For games on D, replay first reconstructs working ratings/baselines through D-1
without publishing snapshots. Frozen forecast context contains those numeric
inputs, each captured prior ID and result cutoff; snapshot source IDs/timestamps
are null because the working inputs are reconstructed, not archived snapshots.
Predictions are always labeled `reconstruction`, even for a future tipoff today,
and retain actual wall-clock generation time. Identical repeats reuse the latest
revision. Then ratings through D are published at D. The whole day's working
state, predictions and snapshots share a savepoint; failed days roll back while
completed resume dates survive. Explicit rebuild retains its complete rollback
and scoped deletion/dependency guards. No snapshots are created outside its window.

Live state remains at the final processed date. Use an explicit resume date window
to restore the desired live cutoff; preserved later snapshots never seed replay.
The solver, prior weights and authored bundle coefficients are unchanged. Replay
can reconstruct from identical stored inputs deterministically but does not archive
source-data availability or old executable code. Captures made after opening are
usable for a labeled hypothetical reconstruction, not evidence of live issuance.
