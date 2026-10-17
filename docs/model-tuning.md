# Model tuning reference

`RatingsConfigVersion` is the runtime source of truth. YAML authors a candidate;
publishing saves its complete immutable payload. Calculations use that selected
payload, never a mixture of the current YAML and an old model. Existing snapshots
and forecast contexts retain their model identity and inputs.

## Author, validate, publish, activate

The default authoring inputs are `config/ratings.yml`, `config/prediction.yml`,
and `config/defaults.yml`. `RatingsConfigVersion.authored_config` combines them.
An explicit complete payload can also be published from the Rails console without
changing YAML or deploying code. Editing a published record is unsupported.

```ruby
payload = RatingsConfigVersion.current.config.deep_symbolize_keys.deep_dup
payload[:bundle_name] = 'experiment-home-learning-01' # a new, unique name
payload[:learning] = {
  volatility: { minimum_observations: 4, sample_scale: 16.0, maximum_weight: 0.5 },
  home_court: { minimum_observations: 4, sample_scale: 16.0, maximum_weight: 0.25 }
}
candidate = RatingsConfigVersion.publish!(payload)
# Publication validates and stores the candidate; it does not activate it.
# candidate.activate is a separate, deliberate operational decision.
```

Publishing rejects unknown keys (including nested typos), malformed objects,
invalid numeric ranges, inverted confidence thresholds, and home-court stat names
that would apply a points-per-100 adjustment to a rate. Existing saved bundles are
not retroactively subjected to the new authoring key whitelist. Their existing
contract/formula validation still applies. New learning blocks must be complete;
absence preserves the historical rule, not a fallback to current YAML.

The authored default is `v1.11-explicit-learning`; it preserves v1.10 numerical
behavior. Publish/select models and generate snapshots through the existing
provenance-aware workflow in [ratings.md](ratings.md). Do not relabel old live
ratings as a new model. No new model is automatically activated by this change.

## Learning from prior forecast errors

Both `learning.volatility` and `learning.home_court` have the following controls:

| Setting | Default (volatility / home court) | Units and valid range | Effect |
| --- | --- | --- | --- |
| `minimum_observations` | 4 / 1 | Integer count, at least 2 / 1 | Below this count, use the baseline without learning. Volatility requires at least two observations for sample SD. |
| `sample_scale` | 16 / 16 | Positive finite count scale | Larger values increase learning more slowly as observations accumulate. This is not a rolling window. |
| `maximum_weight` | 0.5 / 0.5 | Fraction in [0, 1] | Caps the learned contribution; zero disables it. |

For eligible counts, `weight = min(count / sample_scale, maximum_weight)`, rounded
to four decimals for compatibility. With the defaults the 0.5 cap is reached at
**8 observations**, not 16. Raising the minimum can delay learning until after the
cap would otherwise be reached; that is valid and deliberate.

Volatility blends `weight * sample_sd(errors) + (1-weight) * baseline_sd`, using
separate available samples for offense, defense, and pace. Home-court learning
uses separate offensive and defensive residual counts and subtracts the weighted
mean residual from the appropriate baseline (with the versioned historical
sign convention). It is an additive correction, not a blend of two boost values.
The existing clamps keep home offense nonnegative and home defense nonpositive.
Old models without `learning` use exactly 4/1 observations, scale 16 and cap 0.5.

## Core tuning controls

All numeric values must be finite. Unless stated otherwise, values may be zero
but must not be negative. Defaults below describe the authored default bundle.

| Path | Default | Units / bounds | Interpretation |
| --- | --- | --- | --- |
| `preseason.previous_season_weight` | 0.85 | Fraction [0, 1] | Retain more prior-season adjusted strength as it increases. |
| `preseason.fallback_efficiency` | 105.5 | Positive points per 100 possessions | Prior initialization when previous-season efficiency is unavailable. |
| `preseason.fallback_pace` | 69.5 | Positive possessions per 40 minutes | Prior initialization when previous-season pace is unavailable. |
| `preseason.adjustment_start_after_days` | 14 | Nonnegative elapsed days | Solver starts strictly after this threshold, subject to minimum data. |
| `preseason.profile.recruiting_score_multiplier` | 0.1 | Nonnegative efficiency per profile score | Legacy profile recruiting effect. |
| `preseason.profile.attrition_multiplier` | 5 | Nonnegative efficiency scale | Legacy profile attrition effect. |
| `preseason.profile.max_efficiency_adjustment` | 5 | Nonnegative efficiency | Caps legacy profile adjustments. Reviewed components have their own bounds. |
| `weighting.recency_decay_days` | 60 | Positive days | Time to reach the minimum observation weight. |
| `weighting.min_recency_weight` | 0.75 | Fraction [0, 1] | Floor for old game weights; 1 removes recency decay. |
| `weighting.preseason_decay_days` | 40 | Positive days | Controls decay of preseason blending as calendar days pass. |
| `weighting.min_preseason_weight` | 0.1 | Fraction [0, 1] | Prior contribution retained after decay. Applies to efficiency/pace, not factors. |
| `blowout.enabled` | false | Boolean | Enable efficiency-only observation downweighting. |
| `blowout.max_margin` | 15 | Positive final-score points | Margins through this threshold retain full weight. |
| `blowout.cap_multiplier` | 1.25 | Nonnegative exponent | Above threshold, multiply weight by `(max_margin / margin)^exponent`; zero removes dampening. |
| `baseline_volatility.efficiency_volatility` | 11.5 | Positive efficiency SD | Fallback SD and anchor for learned efficiency volatility. |
| `baseline_volatility.pace_volatility` | 4.5 | Positive pace SD | Fallback SD and anchor for learned pace volatility. |
| `home_court_advantage` | 2.2 | Nonnegative efficiency | Baseline boost for confirmed home venues. |
| `home_court_adjusted_stats` | offensive_efficiency, defensive_efficiency | Unique efficiency names | Offensive-efficiency fitting applies the symmetric home/away correction. The defensive name is retained for compatibility; it is not a separate fit. Empty disables solver home adjustment. |
| `ridge.alpha` | 0.001 | Nonnegative penalty | Regularizes efficiency/pace coefficients toward zero deviations. Zero can make a solve singular. |
| `anchor.weight` | 0.05 | Nonnegative observation weight | Strength of the sum-of-offense-deviations anchor row. |
| `prediction.confidence_levels.high_max` | 2 | Nonnegative legacy threshold | Inactive compatibility field; must not exceed medium_max. |
| `prediction.confidence_levels.medium_max` | 5 | Nonnegative legacy threshold | Inactive compatibility field; current confidence is always Uncalibrated. |
| `defaults.season_defaults.average_efficiency` | 105 | Positive efficiency | Prediction fallback when the season anchor is absent; distinct from preseason initialization. |
| `defaults.season_defaults.average_pace` | 70 | Positive pace | Prediction fallback when the season anchor is absent. |

The confidence thresholds are retained for stored-contract compatibility and are
not effective tuning controls. Neither changes current predictions or labels.

### Five Factors

Each entry under `factors` names one existing statistic: `effective_fg_percentage`,
`turnover_rate`, `offensive_rebound_rate`, `free_throw_rate`, `three_pt_proficiency`.
Every entry requires all four settings:

| Setting | Default | Bounds | Effect |
| --- | --- | --- | --- |
| `ridge_alpha` | 0.001 | Nonnegative | Replaces global ridge for this factor's fit. |
| `anchor_weight` | 0.05 | Nonnegative | Replaces global anchor weight for this factor's fit. |
| `offense_weight` | 1 | [0, 1] | Dampens the offensive deviation in the saved factor forecast. Zero uses no offensive deviation. |
| `defense_weight` | 1 | [0, 1] | Dampens the opponent's allowed-rate deviation in the saved factor forecast. |

These are distinct stages: ridge/anchor affect fitted ratings; forecast weights
affect only factor forecasts. Factors still have no score/probability contribution.
See [the forecast equations](ratings.md#versioned-five-factor-forecasts). The
rebounding complement and the existing three-point proficiency definition remain
fixed definitions, not silently adjustable formula coefficients.

### Optional preseason experiments

These blocks are opt-in, with no default activation. Existing component sections
in [ratings.md](ratings.md) describe their exact formulas and provenance rules.

| Block | Controls and bounds | Meaning |
| --- | --- | --- |
| `preseason.coaching` | `formula`: relative_pace_v1 or relative_pace_v2; `weight`: [0,1]; v1 requires nonnegative `max_adjustment`, v2 rejects it | Scales coach pace contribution; v1 caps it in pace units, v2 is uncapped. |
| `preseason.recruiting` | `formula`: class_points_baseline_v1; `weight`, `attenuation_floor`: [0,1]; `class_points_lower/upper` ordered, lower >=0; `baseline_net_lower/upper` ordered; `max_net_efficiency` >=0 | Class-strength response, attenuation by prior net efficiency, and maximum net-efficiency contribution. |
| `preseason.departures` | `formula`: points_share_v1; `weight`: [0,1]; `slope`, `max_net_efficiency` >=0 | Departure share response and maximum net-efficiency loss. |
| `preseason.efficiency_adjustment` | `formula`: reviewed_net_v1; finite `lower_bound` <=0 and `upper_bound` >=0; requires recruiting and departures blocks | Opts into reviewed component integration and bounds the combined net-efficiency adjustment. |

Formula selectors (`ratings_formula`, `prediction.uncertainty_model`, and optional
component formulas) select algorithms, rather than continuous tuning parameters.
`contract_version` is a compatibility marker; do not tune it. Unit conversions
(40 minutes, 100 possessions), minimum data needed to calculate sample SD, and
stat definitions remain code contracts.

## Evaluate before choosing a value

Use distinct model names and frozen pregame forecasts. Compare candidates on
common games and keep an untouched chronological evaluation period. Factor MAE
improvement alone does not establish improvement in score or win predictions.
No defaults above are claimed to be empirically optimal. The admin evaluation
page provides evidence; it does not automatically search or activate parameters.
