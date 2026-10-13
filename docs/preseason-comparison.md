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
imports or publication workflows. Sequential comparisons call the real core solver
in memory; Python/NumPy must be available (use Docker). Run against an authorized local database, not production
as routine verification. Keep exported reports with their source revision/date;
underlying game and snapshot records can be changed by later imports/backfills.

## Comparison contract and leakage audit

This isolates **fixed, no-profile preseason priors** for the first 30 Eastern
schedule dates. Candidates fixed before examining results use weights 0.85, 0.70,
and 0.55; they share the same games and input coverage. The previous-season
baseline is the mean of eligible captured snapshot values per stat, rather than
mutable season aggregates. Matchup anchors use configured fallback efficiency
105.5 and pace 69.5. Volatility uses the explicitly selected stored model defaults and its
`GamePredictor` probability arithmetic. Pass `MODEL_VERSION` to pin the comparison
payload; the report includes that full payload. The older evidence below used
the then-current legacy probability formula and is not evidence for v1.7.

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
predictions. The original fixed-weight reports remain under `candidates`. The extended
`sequential` report is also a retrospective reconstruction, not an archive of
live forecasts. Profiles and empirical residual learning are deliberately omitted.
It does not validate profile accuracy or confidence labels.

## Preregistered sequential hypotheses

The objective is game-time performance on the first 30 Eastern schedule dates,
including zero/one-game teams. Three candidates are declared before examining
outcomes; there is no grid search or automatic coefficient publication:

| Candidate | Prior | Transition |
| --- | --- | --- |
| `baseline_calendar` | Configured previous-year weight (currently .85), remainder cohort baseline | Current >14-day gate, 40-day decay, .10 floor; at least two eligible games |
| `multiyear_calendar` | .70 previous + .15 second year + .15 cohort baseline | Same calendar transition |
| `baseline_effective_games` | Same prior as baseline | At least two eligible games; prior weight `8/(8+effective_games)`, no calendar gate or floor |

Missing second-year history substitutes the previous-year cohort baseline for
that component; it never removes games from only one candidate. All second-year
sources obey the same last-31-days, selected-config, finite-value and pre-opening
creation/revision rules, using the season two years before the target. The report
records second-year IDs and teams with that fallback. Prior outputs round to
three decimals; transition weights round to four, matching existing precision.
No profile values, live TeamSeason ratings or mutable season averages are used.

For games on D, state is rebuilt from scratch through D-1, as in #05's deterministic
reconstruction contract. This read-only path builds the core centered offense/
defense and pace least-squares systems in memory instead of invoking the
write-oriented OverallRatingsCalculator/HistoricalRatingsState. The same
recency weights, ridge, offense anchor and configured venue adjustment apply.
Baseline and multiyear candidates keep the two-result qualification and calendar
gate; the evidence candidate removes only the day gate/floor. An absent solve
leaves the team at its candidate prior. No-game dates and postponements do not
advance game-count evidence. Effective count sums the configured recency weight
of each eligible team-game through D-1.

Sequential results must have both cohort teams, paired positive finite prepared
efficiencies, positive normalized pace, untied final scores and known venue.
Game and both TeamGame creation **and last revision** must precede midnight
Eastern on D. Same-day, future, late-created and late-revised results are excluded;
no former values are invented when a row was revised later. These conservative
mutable-row timestamps can show last availability, not a complete revision log.
Venue and identity remain retrospective metadata. The report cannot establish
that an actual forecast was issued. It neither reads archived Prediction rows nor
writes predictions, priors, working state or snapshots.

The core solver uses eligible per-team mean efficiency and normalized game pace
as its centers, while every matchup uses the same configured fallback anchors,
volatility and home boosts. This isolates prior/transition hypotheses; it is not a
full replay of production's evolving anchors, Five Factors or residual learning.
Do not interpret `baseline_calendar` as byte-identical production forecasts.

Reports include common-game counts and exclusions by season and minimum of the
two teams' previous final-game counts (`coverage_by_prior_game_count`). Sequential
metrics use the minimum **eligible** prior-game count; these may differ when raw
inputs/availability are missing. Per-date counts, effective counts, included and
excluded result IDs and unblended core observations allow auditing those gaps.
Each candidate emits one forecast row per common game, margin/total MAE, Brier,
log loss, reliability counts, and efficiency/pace MAE with actual observation
counts. Absent actuals contribute no efficiency/pace observation. Empty metrics
are null. Log loss uses the predictor's reported rounded probability without
clipping; an impossible outcome is the JSON string `Infinity`.

Earlier eligible seasons are the selection cohort; the latest eligible season
is held out. Candidates are fixed and no winner is chosen automatically. Inspect
selection-season tradeoffs between margin, total, Brier, log loss and reliability
before opening the held-out results. Never tune on that held-out season. With
fewer than two eligible seasons the split explicitly reports no independent
selection/evaluation evidence. Retain production coefficients and confidence
labels until a separately reviewed immutable version is justified.

## Coverage gap and required data

The October 8 dataset below remains the only recorded local evidence; it has not
been rerun for the extended candidates. It has zero eligible games in 2024/2025
and only 114/1,572 in 2026, so there is no earlier selection cohort. Its source
coverage does not prove second-year history or timestamp-eligible sequential
inputs. No new accuracy or calibration claim follows from this implementation.
A new comparison run requires an explicitly authorized existing local dataset.

Collect/preserve at least two independently eligible target seasons, each with
pre-opening prior-year snapshots from the chosen source model, second-year
snapshots where available, known result-independent venue evidence and paired
prepared efficiency/normalized pace records available before each D cutoff.
Retain revision/availability history prospectively rather than backdating new
captures. Use the emitted source IDs, missing-second-year teams, per-date excluded
result IDs and game-count coverage to quantify what is absent. Backfills cannot
manufacture archived live issuance. Missing second-year values have a fixed
fallback; missing earlier evaluation history cannot be fixed by a fallback.

A limited future roster contract should capture team/season/player identity,
returning production numerator and denominator (minutes share as a fraction
0..1, explicit prior season), transfer origin/destination and effective date,
and availability status with effective start/end. Every record needs source,
observed-at, captured-at, immutable revision ID and missingness semantics. Only
values available before issuance may enter a forecast; later corrections append
revisions. Unknown components stay unknown, with a preregistered fallback. No
current mutable profile is historical evidence and none enters these candidates.

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

### Coaching-model limitation

This preregistered v1 team-history comparator does not reconstruct coaching inputs.
Selecting a model with `preseason.coaching` raises an explicit error before source
comparison; select a stored model without coaching settings for this benchmark.
A coaching pace/total comparison needs archived reviewed coaching chronology and
common-game evidence, which this command does not provide. Do not strip settings
and label the resulting team-only candidates as an evaluation of the experimental
coaching model. No accuracy gain is established by the synthetic coaching checks.
