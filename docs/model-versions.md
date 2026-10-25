# Model configuration versions

`RatingsConfigVersion` is the authority for calculation settings. The
`v1.6-pinned-model` bundle introduces complete configuration contract version 1;
it retains the reviewed coefficients and probability arithmetic. It changes
configuration selection, fallback provenance, and input compatibility, without
claiming improved accuracy or calibration.

## Author, publish, select, activate

Review edits to `config/ratings.yml`, `config/prediction.yml`, and
`config/defaults.yml` in Git. Use a new `bundle_name` for changed settings or
corrected captured prior inputs. Publication copies all three files into one
immutable payload: ratings settings remain at the top level, with
`contract_version: 1`, `prediction`, and `defaults` sections.

```bash
bin/rails ratings_config_version:publish
bin/rails ratings_config_version:activate MODEL_VERSION=v1.6-pinned-model
```

Publication validates and stores the payload; it does not activate it. Reusing a
name with different settings fails. Selection reads an existing row without
publishing or updating `current`. Activation explicitly changes the default
for future runs. `ensure_current!` remains an explicit publish-and-activate
compatibility API; calculation and evaluation paths no longer call it.
`find_or_create_by_current_config` remains a publication compatibility API.
All supported new-row paths enforce the same strict authoring contract:
`publish!`, a factory lookup that must create a row, ordinary Active Record
creation, and RailsAdmin creation reject unknown keys, malformed objects, and
invalid values. For a new row, the model `name` must equal the normalized
`config.bundle_name`; this keeps ordinary/admin creation aligned with the
factory's canonical lookup key. A factory lookup first returns an identical
row by its stored name/config, preserving compatibility with historical payloads. Existing rows
remain readable and replayable under their existing runtime policy; incomplete
legacy contracts still cannot be newly calculated. Updating descriptions or
activation state remains supported, while name and config are immutable.
Direct SQL and validation-bypass writes are unsupported authoring paths.

Defaults select the active row, or the already-published authored bundle when no
row is active. No published default is an error for calculations. Lookup of
current predictions/ranks may return no result. Neither path creates a version.
A selected incomplete legacy active row fails calculation rather than falling
through to a newer bundle.

```ruby
version = RatingsConfigVersion.find_by!(name: 'v1.6-pinned-model')
ProphetRatings::OverallRatingsCalculator.new(season, ratings_config_version: version).call(as_of: date)
ProphetRatings::PreseasonInitializer.new(season, ratings_config_version: version).call
ProphetRatings::GamePredictionBuilder.new(game, ratings_config_version: version).call
ProphetRatings::PredictionEvaluator.new(ratings_config_version: version, date_range: dates).call
UpdateRankingsJob.perform_later(season.id, ratings_config_version_id: version.id)
```

Prediction, simulation, and volatility services infer a version from the home
snapshot if none is explicitly supplied, then require both snapshots to match
it. The matchup screen selects its default once. Core ratings, weighting,
preseason blending/profile coefficients, home court, volatility/confidence
fallbacks, and ridge/anchor parameters come from the selected stored payload.
Available snapshot values remain data inputs. New saved forecasts obtain season
anchors and fallback deviations from the selected model/date publication's
`stats.season_forecast_inputs`, rather than mutable live season fields. The writer
captures all four effective values and explicit season/config fallback evidence
atomically with the snapshots; both participants must share compatible model,
season, publication date and cutoff. See the
[publication input contract](ratings.md#frozen-forecast-context-and-revisions).
Confidence thresholds and all numerical configuration fields must be present; decay denominators and
baseline values must be positive and mixture weights must be in 0..1.

Residual aggregation rejects stored predictions whose snapshot versions differ
from the selected output version. Prediction uncertainty diagnostics use stored
snapshot volatility instead of another model's live TeamSeason values. Missing
or invalid snapshot volatility is an explicit diagnostic error; the existing
uncertainty arithmetic is unchanged.

Ratings and prediction jobs attach the version ID before enqueue serialization.
Execution, retries, date loops, and downstream predictions retain that ID even
if YAML or activation changes. Older jobs enqueued before this contract have no
recorded selection: they select once on their first execution and subsequent
retries retain it. Review/drain or replace those jobs during rollout if their
original intended version matters; it cannot be reconstructed from the queue.

## Complete v1.16 early-season candidate

`config/examples/v1_16_coherent_early_season.json` is a complete publishable
payload. It retains the v1.15 departure cap and coefficients, with the new bundle
name and `early_season_policy: coherent_v1`. This bypasses the legacy 14-day
solver gate while retaining two-game eligibility, supported-opponent observations,
and the existing calendar blend. It does not establish predictive improvement.

Publish it explicitly in the target application's Rails console:

```ruby
payload = JSON.parse(Rails.root.join('config/examples/v1_16_coherent_early_season.json').read)
version = RatingsConfigVersion.publish!(payload)
```

Publication preserves existing model versions and does not select a season model,
activate a global default, initialize captures, or replay ratings. Use the
[scoped model-switch and recovery workflow](offseason.md#explicit-ratings-recovery-and-rebuilds)
to initialize the candidate's own priors, anchors and snapshots before using it
for calculations or activating it as the default. Keep existing v1.15 outputs under their original model identity.
Historical reconstructed predictions remain distinct from archived forecasts.

## Legacy and live-input compatibility

Existing immutable versions, priors, snapshots, and predictions are preserved.
Snapshots missing `season_forecast_inputs` are rejected for new saved issuance;
republishing requires the normal authorized selected-model workflow. No automatic
historical rewrite or provenance fabrication occurs. Already frozen contexts
replay their saved values unchanged without requiring this metadata. Recalculated
historical working inputs carry explicit `reconstruction` provenance, never a
claim to an archived publication. No bundle/config hash change accompanies this
input-provenance fix.

Legacy ratings-only payloads lack stored prediction/default settings, so new
calculations, replay, or activation reject them with an explicit error. Stored
legacy predictions can still be listed and evaluated without filling their
missing configuration from current YAML. This is evaluation of published
outputs, not faithful recalculation.

The additive `PinTeamSeasonModelInputs` migration adds nullable live-model and
applied-prior references on `TeamSeason`. It does not fabricate historical
provenance. A preseason capture records its version and becomes the applied
prior; its team, version, and outputs must match before rating publication.
Live values with another version, or legacy core ratings without a version,
are rejected before a rating run writes. Snapshots require the live version to
match; predictions validate both snapshots against their output version.
Applied captures must contain all three expected preseason outputs and match
the live preseason values; a partial or empty payload is insufficient provenance.

For fresh seasons, initialize with the selected version before activating the
season. For an eligible inactive preseason, reviewed source corrections or participant
changes can instead use [deliberate preseason revisions](offseason.md#deliberate-inactive-preseason-revisions)
with a newly published version and an accepted preview. No daily rebuild is required;
prior versions and saved forecasts remain intact. Current seasons, finalized games,
changed adjusted values or later snapshots still require the scoped workflow below.

Switching models for established in-season live ratings requires an explicitly
reviewed reset/rebuild starting at season opening, with `RUN_PRESEASON=true`;
see [Offseason Operations](offseason.md). Reset uses captured priors for that
version and its configured boosts/volatility, clearing old adjusted Five Factors.
It does not activate the model or delete another model's historical outputs.
Do not manually label old live values as the new version. Existing destructive
rebuild confirmation, date-window, dependency, and transaction safeguards apply.

Apply the additive migration before running the new code's calculations. Review
and publish the complete bundle, initialize/reset the intended live inputs with
explicit authority, then activate it when appropriate. Deploying code alone
neither publishes nor activates a model nor repairs existing live values.

## Reproducibility and verification

Pinning settings does not freeze source games, mutable season averages,
previous-season live inputs before capture, or calculation code. Captured priors
retain their existing input/output replay contract. New saved forecasts separately
freeze rating inputs, season anchors/fallbacks and venue evidence under
[calculation context contract 1](ratings.md#frozen-forecast-context-and-revisions),
with strict prior-Eastern-date selection and explicit reconstruction labels.
Legacy forecasts retain their historical selection and replay limits. A stored version identifies settings,
not a full historical data/code environment.

Run the deterministic solver boundary check in Docker's Python/NumPy image:

```bash
bin/compose run --rm --no-deps -T web bundle exec ruby script/check_model_solver.rb
```

It needs no database or domain data and tests `weights: [1, 4]` with explicit
ridge values 0 and 4. The independently derived diagonal solutions are `[10, 20]`
and `[2, 10]`. `StatisticsUtils.solve_least_squares_with_python` now takes explicit
`ridge_alpha:` and optional `weights:` keywords; it never reads configuration.
Targeted model/job specs exercise stored versions with distinct settings,
consecutive calculations, mixed-input rejection, serialization/retries,
publication/lookup/activation separation, and legacy evaluation.

## Prediction arithmetic versions

The authored bundle is now `v1.12-probability-precision`. It retains the v1.7 stored
`prediction.uncertainty_model: shared_pace_v1`, which selects the exact shared-pace
moments and efficiency-difference win probability described in
[Ratings](ratings.md#shared-pace-uncertainty-baseline). Contract version 1 rows
without this key select the legacy numerical behavior. Unknown selector values
are rejected; neither path reads YAML to determine arithmetic. Existing model
rows and predictions are preserved, and no publication/activation happens on
code deployment. Confidence labels are uncalibrated across both paths.

Publish and explicitly select/activate the new bundle using the commands above
with `MODEL_VERSION=v1.12-probability-precision`. New snapshots must belong to that version;
review the existing live-input/reset safeguards before any authorized rollout.
No automatic historical rewrite or calibration claim accompanies this change.

The v1.9 bundle also selects `ratings_formula: corrected_v1` for the in-season
pace, home-defense and three-point corrections described in
[Ratings](ratings.md#corrected-in-season-ratings-v19-ratings-corrections).
Blowout weighting remains off by default. Persisted bundles without this selector
retain legacy ratings arithmetic.

The v1.12 bundle adds `prediction.probability_precision: float64_v1` and retains
the v1.11 learning settings and coefficients. This selector requires
`shared_pace_v1`; unknown precision selectors fail validation. It preserves the
existing CDF Float through frozen replay, double precision storage/reload and
metrics; only display may round. Absence retains historical four-decimal output.
Existing saved forecasts are never recalculated and their lost digits cannot be
recovered. Apply `PreservePredictionProbabilityPrecision` before the new code;
its down migration is intentionally irreversible. Roll back code while keeping
wide storage. See the [precision contract](ratings.md#issued-win-probability-precision)
for deterministic endpoints and floating-point limits. No activation or accuracy
claim accompanies this bundle.

### Season-specific publication selection

The offseason preseason screen selects only persisted published model versions.
Its season-specific selection and generation are independent of the global default
and of retained input approvals. Preview, acknowledgement, job execution and result
pages retain the selected model ID/name. Switching A → B → A invalidates A's old
pending review. Initialization preserves selected-model captures; explicit revision
uses fresh reviewed evidence and existing immutable-version eligibility rules.
Neither operation authors model configuration, activates a model/season or silently
regenerates saved forecasts. Use a newly published eligible version for corrections
that cannot reuse existing captures; the existing CLI preview/revision commands
remain available with their original contracts.

After an explicit season revision, the admin workflow requires explicit revision
when selecting a different model; initialization remains a same-model safe repeat.
Choose an eligible unused published version so the season revision and included
live/prior/snapshot coverage remain aligned for activation. Existing CLI calculation
service contracts are unchanged.

### Reviewed default activation

The target-season **Readiness** screen retains operational evidence and offers a
separate **Make model default** action showing the previous effective default and
persisted selected model. Saving readiness, publishing preseason outputs and
activating a season never change that default. Changes since review require fresh
evidence before either activation action; each successful action result is retained.
Explicit season/model job payloads are unchanged by switching. Jobs omitting a
season ID retain their existing execution-time current-season behavior and need
operator review in GoodJob. See [the retained readiness runbook](offseason.md#retained-readiness-and-explicit-activation).
