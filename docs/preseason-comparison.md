# Preseason input capture and bounded comparison

The chosen production defaults remain 85% previous-season weight, bounded optional
profile effects, 40-day calendar decay/10% floor, and existing uncertainty defaults.
The v1.4 bundle adds captured inputs, not fitted coefficients. Older v1.2/v1.3
outputs keep their original meaning. See [Ratings](ratings.md) for the replay
contract and migration requirement.

## Read-only comparison command

With the app/database available, select one to five stored target season years and
the configuration of the **previous-season source snapshots** explicitly:

```bash
bin/compose exec -e YEARS=2024,2025,2026 -e SOURCE_CONFIG=v1.2-default web \
  bundle exec rake ratings:compare_preseason > tmp/preseason-comparison.json
```

This emits numerical JSON without requiring chart gems or writing predictions,
ratings, captures, or configuration versions. It does not call backfill jobs,
imports, or the solver. Run against an authorized local database, not production
as routine verification. Keep exported reports with their source revision/date;
underlying game and snapshot records can be changed by later imports/backfills.

## Comparison contract and leakage audit

This isolates **fixed, no-profile preseason priors** for the first 30 Eastern
schedule dates. Candidates fixed before examining results use weights 0.85, 0.70,
and 0.55; they share the same games and input coverage. The previous-season
baseline is the mean of eligible captured snapshot values per stat, rather than
mutable season aggregates. Matchup anchors use configured fallback efficiency
105.5 and pace 69.5. Volatility uses configured defaults and the current
`GamePredictor` probability formula (including its pace-squared scaling).

Sources must be from the immediately preceding completed season, within its last
31 calendar dates, with snapshot date before target opening and both creation and
last revision strictly before opening midnight Eastern. Latest eligible finite
snapshots are selected per team from the specified source config. A snapshot
backdated after opening is excluded. Earlier unmodified snapshots remain eligible
when a later snapshot was revised after opening. The report includes selected IDs,
coverage/exclusions, margin/total MAE, Brier score, and reliability bins with actual
mean probabilities, observed win rates, and counts (including small bins).

Games need both teams' eligible sources, untied final scores, and neutral or
confirmed/manual home venue evidence. Unknown venues are excluded rather than
assigned invented home-court effects. Historical profiles are omitted because
current mutable profiles cannot establish which components existed pregame.
Venue/team identities and final outcomes use stored game metadata; venue data
may have been imported retrospectively, so this is a retrospective benchmark
using result-independent venue information, not an archived prediction replay.
No current-season ratings, volatility estimates, averages, or residuals enter
predictions. This benchmark does not evaluate multiyear priors or the calendar vs
game-count transition; those require more eligible history and safe sequential
observed ratings. It also does not validate profile accuracy or confidence labels.

`ResumeSeasonRatingsJob` calculates ratings through a schedule date before
predicting that date's games, while `GamePredictionBuilder` permits snapshots on
the game's schedule date. These can incorporate target results. `GamePredictor`
and `VolatilityCalculator` also use mutable season aggregates for some defaults.
`PredictionEvaluator` does not enforce pregame provenance and its existing plots
are not a leakage audit. None of those stored/backfilled predictions or mutable
season fallbacks are used here. Their operational behavior is unchanged.

## Local evidence, October 8, 2026

Read from the existing development database with PostgreSQL
`default_transaction_read_only=on`; no production access, migration of the
development database, imports, or backfills occurred. This database is not claimed
to match production. Season years use the repository's ending-year convention.

| Target year | Opening finals | Eligible previous-season teams | Evaluated games | Excluded games |
| --- | ---: | ---: | ---: | ---: |
| 2024 | 1,535 | 0 | 0 | 1,535 |
| 2025 | 1,561 | 0 | 0 | 1,561 |
| 2026 | 1,572 | 364 | 114 | 1,458 |

The 2026 sample is only 7.25% of opening finals. Most exclusions reflect unavailable
venue evidence; source coverage alone does not establish game coverage. The two
earlier target years lack eligible previous-season snapshots. Empty-sample errors
and Brier scores are **null**, not zero. There is no independent eligible tuning
season, so the single season is exploratory evaluation only.

| Previous-season weight | Margin MAE (points) | Total MAE (points) | Brier score |
| --- | ---: | ---: | ---: |
| 0.85 baseline | 11.4211 | 15.5160 | 0.09609 |
| 0.70 | 12.1325 | 15.2311 | 0.09735 |
| 0.55 | 13.1479 | 15.0760 | 0.10098 |

Baseline reliability (all 114 evaluated games):

| Probability bin | Games | Mean home-win probability | Observed home-win rate |
| --- | ---: | ---: | ---: |
| 0.3–0.4 | 2 | 0.3806 | 1.0000 |
| 0.4–0.5 | 4 | 0.4640 | 0.7500 |
| 0.5–0.6 | 6 | 0.5584 | 0.8333 |
| 0.6–0.7 | 6 | 0.6447 | 0.8333 |
| 0.7–0.8 | 15 | 0.7500 | 0.8667 |
| 0.8–0.9 | 23 | 0.8423 | 0.9130 |
| 0.9–1.0 | 58 | 0.9583 | 0.9483 |

Stronger regression improves total MAE slightly while worsening margin MAE and
Brier score on this sample. Sparse, highly selected bins and a majority of strong
home favorites prevent broad calibration claims. Retain conservative production
defaults; do not tune on this same sample or call these accuracy improvements.
Future evaluation needs additional eligible seasons and frozen pregame profile
inputs, plus safe sequential observations to assess the in-season transition.

## Review and replay

After applying the additive migration in the deployment workflow, initialize a
fresh target season through the existing guarded operation. Inspect
`PreseasonPrior` and `stats.preseason_prior` on newly published snapshots. Replay:

```ruby
prior = PreseasonPrior.find(id)
ProphetRatings::PreseasonPriorFormula.new(prior.inputs, prior.inputs.fetch('configuration')).call == prior.outputs
```

Rerun initialization and check captured values survive subsequent source edits.
To deliberately incorporate corrected inputs, create a new bundle version and
review it through the existing season operations; do not edit/delete captures or
retroactively manufacture historical ones. No deployment or manual publication
was performed as part of the local comparison.
