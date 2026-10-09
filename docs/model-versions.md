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
Season baselines and available snapshot values remain data inputs; configured
fallbacks apply only where those inputs are missing. Confidence thresholds and
all numerical configuration fields must be present; decay denominators and
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

## Legacy and live-input compatibility

Existing immutable versions, priors, snapshots, and predictions are preserved.
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

For fresh seasons, initialize with the selected version before activating the
season. Switching models for established live ratings requires an explicitly
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
retain their existing input/output replay contract. Same-day rating selection,
backfill ordering, mutable season prediction baselines and diagnostic data
remain limits for leakage-safe evaluation. A stored version identifies settings,
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
