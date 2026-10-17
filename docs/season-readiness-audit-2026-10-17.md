# Prophet Ratings: season-readiness audit — October 17, 2026

## Scope and decision

The efficiency/pace baseline has a substantially testable implementation, but this audit does **not** establish production accuracy or season readiness. Fix the input-coherence, publication-date and data-integrity defects below before relying on new forecasts. The admin evaluation is useful descriptive reporting; it is not yet a complete controlled experiment workflow. Five Factor forecasts are diagnostics, not contributors to score or win-probability predictions.

Audited branch: `codex/solver-efficiency-and-ratings-corrections`, [PR #200](https://github.com/zstearman3/prophet-ratings/pull/200), exact commit [`4eedc36`](https://github.com/zstearman3/prophet-ratings/commit/4eedc366359a94e4cbfec8c516385d8aa620bd2a). Findings refer to the whole relevant system at that commit, not only the PR diff. Source links below are pinned to that commit because line numbers and behavior may change.

The audit read `AGENTS.md`, `docs/ratings.md`, `docs/model-tuning.md`, `docs/model-versions.md`, relevant preseason/replay documentation, ingestion documentation and implementation/tests. It traced finalized games through raw aggregates, adjusted ratings, the real Python solver, snapshots, issued forecasts and evaluation. Previous conclusions were treated as claims to verify.

The export was written in the maintainer checkout on `development` at `2bb65adfa1ce78b806a98c03652321d0dd897f96`, which predates the audited commit. The audited code and synthetic checks used an isolated archive of the specified commit. The checkout was not switched or reset. This is a dated audit, not a claim that the export checkout implements every inspected feature.

No application fixes, production reads, imports, backfills, historical rewrites, deployments or operational model activations were performed. Synthetic tests used disposable databases, including test-only model publication/activation. Repository changes for this follow-up are documentation only.

## Verified defects and implementation tickets

Severity reflects consequences and pre-season urgency, not measured production incidence. Each defect has an independently checked code path and synthetic reproduction. Statistical assumptions and optional features are separated later.

| Finding | Severity | Implementation ticket |
| --- | --- | --- |
| 1. Allow safe early-season updates with coherent prediction anchors | P1 | [Notion ticket](https://app.notion.com/p/3fc17d6b0c2481fa8308d01c2062164f) |
| 2. Bind forecast season anchors to the selected model and rating date | P1 | [Notion ticket](https://app.notion.com/p/3fc17d6b0c24814a9dd3e479ad2a6c64) |
| 3. Publish scheduled ratings through the last completed Eastern day | P2 | [Notion ticket](https://app.notion.com/p/3fc17d6b0c248160afa6fe42d3b0ad36) |
| 4. Reject forecast/outcome participant mismatches after game corrections | P2 | [Notion ticket](https://app.notion.com/p/3fc17d6b0c24815d9623c7d7efa4ae6a) |
| 5. Validate finite derived statistics before finalizing games | P2 | [Notion ticket](https://app.notion.com/p/3fc17d6b0c2481c09851eeba3398659e) |
| 6. Preserve issued win-probability precision for evaluation | P2 | [Notion ticket](https://app.notion.com/p/3fc17d6b0c24817aaf7cc44f1d6b4b00) |
| 7. Enforce strict validation on every new model authoring path | P2 | [Notion ticket](https://app.notion.com/p/3fc17d6b0c248163aa7ae1fa9bc2bc70) |

Tickets were created using the repository's `prophet-plan-ticket` workflow, checked against existing board work and read back. They are Bugs / Not started, with Ratings as the feature area except finding 5 (Import). No sprint, assignee, due date or board priority was invented. Related implemented tickets are linked in each new ticket; the existing statistical preseason-comparison story retains its broader tuning scope.

### 1. Allow safe early-season updates with coherent prediction anchors (P1)

**Observed defect.** Early calculations update the league efficiency anchor while retaining preseason team ratings behind a 14-day gate. Predictions combine quantities from different baselines. The user prefers removing the blanket early-season freeze where safe, rather than merely freezing the anchor.

**Evidence.** [app/services/prophet_ratings/overall_ratings_calculator.rb:32](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/services/prophet_ratings/overall_ratings_calculator.rb#L32) aggregates and updates the anchor before the solver gate at line 82. [app/models/season.rb:82](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/models/season.rb#L82) updates raw averages. [app/services/prophet_ratings/game_predictor.rb:122](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/services/prophet_ratings/game_predictor.rb#L122) subtracts the season anchor from the two adjusted efficiencies. [app/services/prophet_ratings/adjusted_stat_calculator.rb:21](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/services/prophet_ratings/adjusted_stat_calculator.rb#L21) qualifies teams individually after two games and only includes observations between qualified teams.

**Reproduction and consequence.** Initialize two teams at efficiency 105.5 and pace 69.5. Supply early finalized observations averaging efficiency 120 and calculate on season day 1. Both adjusted efficiencies remain 105.5, but the anchor becomes 120. A neutral expected score becomes (105.5 + 105.5 - 120) × 69.5 / 100 = 63.25 instead of the prior 73.32. The common anchor cancels in the margin, so this does not directly change win probability.

**Suggested smallest fix.** Remove the blanket calendar delay for a newly authored model only when usable observations and a numerically supported solve exist. Preserve priors for thin-data teams, and publish efficiency/pace anchors coherent with the actual blended ratings. If no usable data exist, retain a coherent prior state. Do not merely change the gate setting and call the anchor problem fixed.

**User preference and feasibility result.** A new synthetic probe used the existing public configuration with adjustment_start_after_days=0 (no application edits), two neutral A/B games by day 1, and an unplayed C. The real full Rails/Python pipeline returned ratings [0.125, -0.125, 0] and ranks [1, 3, 2]; C retained 105.5/105.5/69.5. This establishes feasibility, not statistical calibration or anchor correctness. Positive ridge also solved one-game and disconnected matrices. The current > comparison means zero still waits until after day zero. Check usable per-stat rows, not only finalized-game counts. Coordinate the anchor storage contract with finding 2 without requiring a general shadow-model runner.

This is not an all-teams-played numerical requirement. With nonnegative observation weights and positive ridge alpha, `A'WA + alpha I` is positive definite even with unobserved columns or disconnected schedule components. A unique numerical solution does not imply enough information to separate team strengths reliably. Preserve priors and shrink conservatively; do not assign league-average values to unplayed teams merely because their fitted coefficients are zero.

The recommended first slice removes the blanket calendar delay for already-qualified teams, preserves zero/one-game priors, and explicitly handles cases with no usable matchup rows. First-game updates are mathematically possible with regularization but require a deliberate eligibility/prior policy; they are not necessary to satisfy updating rankings before every team has played. Merely setting the delay to zero leaves the anchor-coherence defect unresolved.

**Handoff.** [Ticket 1](https://app.notion.com/p/3fc17d6b0c2481fa8308d01c2062164f). Add calculator/snapshot/predictor regressions for early participation, no usable rows, irregular schedules, blend transitions and failed-solve rollback. Run a real deterministic Docker/NumPy solver and Rails boundary check with independently reasoned values, including unplayed and disconnected teams.

### 2. Bind forecast season anchors to the selected model and rating date (P1)

**Observed defect.** Freezing a forecast preserves the values it used, but new forecasts can still capture season anchors produced by another model. Snapshot identity alone does not isolate candidate inputs.

**Evidence.** [app/services/prophet_ratings/forecast_context.rb:12](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/services/prophet_ratings/forecast_context.rb#L12) captures selected-version snapshots alongside mutable, unversioned game.season values (lines 30–35). [app/models/season.rb:92](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/models/season.rb#L92) overwrites average pace from live adjusted ratings. [app/models/team_season.rb:110](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/models/team_season.rb#L110) protects live model ownership, so ordinary concurrent rating jobs are not a shadow-model implementation.

**Reproduction and consequence.** Publish model A preseason snapshots with pace 69.5. Publish an inactive model B with fallback pace 80 for the same season in a disposable database. Build a new A forecast using unchanged A snapshots. It predicts pace 69.5 + 69.5 - 80 = 59. The frozen context faithfully preserves this wrong-model mixture.

**Suggested smallest fix.** Persist and select the efficiency/pace anchors and required fallback deviations with the model/date rating publication; validate compatible context before issuance. Reuse the existing snapshot provenance approach where practical. Define explicit handling for legacy snapshots without this metadata.

**Handoff.** [Ticket 2](https://app.notion.com/p/3fc17d6b0c24814a9dd3e479ad2a6c64). Use actual preseason publication for two inactive model configurations, not only a mocked season mutation. Test new A issuance after B publication, frozen replay, missing metadata and rollback.

### 3. Publish scheduled ratings through the last completed Eastern day (P2)

**Observed defect.** The scheduled ratings job labels morning results with today's date, but today's forecasts only accept earlier-date snapshots. The freshest scheduled publication is therefore unusable for its intended same-day forecasts.

**Evidence.** [app/jobs/update_rankings_job.rb:24](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/jobs/update_rankings_job.rb#L24) calls the calculator without an explicit cutoff; [app/services/prophet_ratings/overall_ratings_calculator.rb:111](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/services/prophet_ratings/overall_ratings_calculator.rb#L111) defaults to the current Eastern schedule day. [app/services/prophet_ratings/game_prediction_builder.rb:98](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/services/prophet_ratings/game_prediction_builder.rb#L98) limits inputs to the prior game day; latest_snapshot at line 152 applies that cutoff and issuance timestamps.

**Reproduction and consequence.** Provide yesterday's and today's snapshots for a scheduled game today. The builder correctly selects yesterday's snapshot. The scheduled morning job's new today-labeled snapshot is excluded; yesterday's snapshot can itself omit yesterday's games. If no earlier snapshot exists, prediction is skipped.

**Suggested smallest fix.** Give the scheduled job an explicit last-completed-Eastern-day cutoff and label snapshots with that data cutoff. Keep strict prior-day selection and source creation/update timestamps; do not weaken the leakage safeguard.

**Handoff.** [Ticket 3](https://app.notion.com/p/3fc17d6b0c248160afa6fe42d3b0ad36). Test the real scheduled-job-to-builder chain with games on adjacent Eastern dates, not only builder filtering.

### 4. Reject forecast/outcome participant mismatches after game corrections (P2)

**Observed defect.** Saved forecast eligibility checks time and date but does not verify that captured home/away team identities still match the game's current participants. A corrected side assignment can contaminate evaluation and learned residuals.

**Evidence.** [app/models/concerns/frozen_forecast.rb:19](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/models/concerns/frozen_forecast.rb#L19) selects eligible forecasts without comparing participants. [app/services/prophet_ratings/evaluation_observation.rb:42](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/services/prophet_ratings/evaluation_observation.rb#L42) compares saved home/away values to current sides. [app/services/prophet_ratings/game_finalizer.rb:106](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/services/prophet_ratings/game_finalizer.rb#L106) computes residuals the same way.

**Reproduction and consequence.** Save a forecast A-home 77, B-away 70. Apply a persisted home/away identity reversal as the importer can do, then finalize B-home 70, A-away 77. The forecast remains selected and reports margin error 14 instead of the team-aligned 0.

**Suggested smallest fix.** Initially exclude participant/side mismatches with a clear reason from current display, verified evaluation and residual learning. Preserve the immutable forecast. Automatic remapping is unnecessary for the smallest safe fix.

**Handoff.** [Ticket 4](https://app.notion.com/p/3fc17d6b0c24815d9623c7d7efa4ae6a). Regression tests for actual persisted remove/recreate-side correction, evaluator output/exclusions, GameFinalizer and aggregator learning selection.

### 5. Validate finite derived statistics before finalizing games (P2)

**Observed defect.** Presence of game pace is insufficient to establish a valid finalized box score. Zero denominators can produce NaN rates that reach finalized records and later calculations.

**Evidence.** [app/services/prophet_ratings/game_finalizer.rb:32](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/services/prophet_ratings/game_finalizer.rb#L32) accepts any present pace and calculates team stats afterward. [lib/basketball_calculations/stat_formulae.rb:26](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/lib/basketball_calculations/stat_formulae.rb#L26) and subsequent rate methods divide by opportunity counts without consistent zero-denominator handling. Inspect TeamGame#calculate_game_stats for non-bang persistence.

**Reproduction and consequence.** In a disposable database, create both team boxes with importer-required stat keys all zero except minutes=200 and turnovers=10, and game scores 1–0. Finalization succeeds and persists NaN effective field-goal percentage. This is a synthetic malformed input, not evidence of how often production imports contain it.

**Suggested smallest fix.** Use null for legitimately undefined rates and reject/quarantine incomplete or inconsistent core box scores and nonfinite/nonpositive required quantities before final status. Make failed derived-stat persistence abort finalization. Never substitute fabricated zero rates.

**Handoff.** [Ticket 5](https://app.notion.com/p/3fc17d6b0c2481c09851eeba3398659e). Run focused stat-formula, TeamGame, GameFinalizer and importer specs using synthetic fixtures. Reproduce the reported NaN case and demonstrate rollback and explicit missing-value behavior.

### 6. Preserve issued win-probability precision for evaluation (P2)

**Observed defect.** Rounding a nondegenerate win probability to four decimals can turn a possible upset into a stored impossible event and produce infinite log loss.

**Evidence.** [app/services/prophet_ratings/game_predictor.rb:181](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/services/prophet_ratings/game_predictor.rb#L181) rounds the shared-pace probability to four decimals. [db/schema.rb:295](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/db/schema.rb#L295) stores decimal(5,4). [app/services/prophet_ratings/preseason_comparison_metrics.rb:23](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/services/prophet_ratings/preseason_comparison_metrics.rb#L23) correctly returns infinite log loss when the observed winner has stored probability zero.

**Reproduction and consequence.** Use matchup efficiency means 140 and 100, four component efficiency SDs of 5, and upset modifier 1. Difference SD is 10, z=4 and raw home probability is 0.9999683287581669. It is stored as 1.0. An away win then has infinite log loss rather than approximately 10.3601014865.

**Suggested smallest fix.** Preserve adequate probability precision through calculation, issued forecast persistence and evaluation; round only for display. Version changed output behavior and preserve old saved forecasts. Do not silently clamp evaluator probabilities to hide the defect.

**Handoff.** [Ticket 6](https://app.notion.com/p/3fc17d6b0c24817aaf7cc44f1d6b4b00). Test predictor-to-builder-to-database-to-evaluator round trips, symmetric tail cases, equal means, deterministic cases and legacy output behavior.

### 7. Enforce strict validation on every new model authoring path (P2)

**Observed defect.** Strict configuration checks run through publish!, but public creation paths can persist malformed new configurations that runtime compatibility accepts. A typo can activate successfully while its intended setting has no effect.

**Evidence.** [app/models/ratings_config_version.rb:48](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/models/ratings_config_version.rb#L48) validates authored payloads in publish!. The public find_or_create_by_config at line 95 directly creates records; model validations at lines 25–27 only enforce identity/presence. Activation at line 78 uses runtime settings, whose legacy tolerance is intentional.

**Reproduction and consequence.** Copy a complete authored payload, give it a fresh bundle name and add home_cort_advantage: 20. publish! rejects the unknown key. find_or_create_by_config accepts it; the resulting model activates in the disposable test database while the misspelled setting is ignored.

**Suggested smallest fix.** Apply strict schema/semantic checks to all supported creation paths, including the public factory and generic admin creation. Keep legacy read/replay compatibility explicit and separate from new authoring; do not retroactively invalidate stored models.

**Handoff.** [Ticket 7](https://app.notion.com/p/3fc17d6b0c248163aa7ae1fa9bc2bc70). Use the exact typo reproduction through each supported entry point plus representative legacy configurations and immutability tests.

## Mathematical and logical checks that held up

### Aggregation, solver and rating direction

- Lower defensive efficiency is better. The current adjusted offense/defense interpretation and ranking direction follow that convention. The home-defense learning correction uses the appropriate sign: starting at a -2.2 defensive boost, a positive allowed-efficiency residual of 4 with the tested learning settings moved the boost to -4.2, not toward worse defense.
- The intentional three-point proficiency definition is `((2 * 3P%) + 3PA/FGA) / 3`. Corrected game observations, season aggregates and factor actuals use it consistently; the solver recomputes it from stored counts to avoid historical imported-formula ambiguity. This definition is not a bug. Its incremental predictive value is unproven.
- Weighted ridge solves `min sum(w_i * (A_i x - b_i)^2) + alpha * sum(x_j^2)`. The row-scaled implementation matches the dense diagonal-weight reference, including zero observation weights. The offense anchor is a soft weighted zero-sum constraint; ridge shrinks deviations toward zero, hence toward the chosen league baseline after conversion. These are modeling assumptions, not hard identities.
- The Python boundary checks matrix/vector shapes, finiteness and nonnegative weights/regularization; Rails checks the returned coefficient vector. Singular systems can fail explicitly. Do not rely on zero ridge for an underdetermined sparse schedule: floating-point normal equations may either fail or return unstable coefficients.
- Overtime possessions are normalized to pace per 40 minutes. Efficiency remains points per 100 possessions. These unit conversions are correct.

Key implementation: [lib/python/adjusted_stat_solver.py:10](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/lib/python/adjusted_stat_solver.py#L10), [app/services/prophet_ratings/adjusted_stat_calculator.rb:168](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/app/services/prophet_ratings/adjusted_stat_calculator.rb#L168), [lib/basketball_calculations/stat_formulae.rb:1](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/lib/basketball_calculations/stat_formulae.rb#L1) and `TeamSeasonStatsAggregator`.

### Score uncertainty and probability

For matchup efficiencies H and A, and a single shared game pace P, the implemented shared-pace model uses scores `PH/100` and `PA/100`. Assuming independent H, A and P:

```text
Var(home score) = ((muP² + vP) vH + vP muH²) / 10000
Cov(home score, away score) = vP muH muA / 10000
Var(margin) = ((muP² + vP)(vH + vA) + vP(muH - muA)²) / 10000
Var(total)  = ((muP² + vP)(vH + vA) + vP(muH + muA)²) / 10000
P(home wins | positive pace) = Phi((muH - muA) / sqrt(vH + vA))
```

The shared-pace moment calculations include the product-of-variance terms and induced score covariance. Fixed-pace scaling is dimensionally correct. The win formula appropriately depends on the efficiency difference rather than treating the product-distributed margin as normal. Equal means give 0.5; greater efficiency uncertainty moves non-tied probabilities toward 0.5. Explicit zero-variance cases are handled.

The normal pace approximation has a nonpositive tail; the probability formula assumes physically positive pace. That documented approximation is a statistical limitation, not a new arithmetic defect. Finding 6 concerns output rounding after these calculations.

Key implementation: `app/services/prophet_ratings/score_moments.rb`, `game_predictor.rb`, `game_simulator.rb` and `volatility_calculator.rb`.

### Provenance and temporal protections

Model IDs propagate through the main calculation and queued-job paths. New forecasts freeze effective numerical inputs, configuration, venue context, source identities/cutoffs and issuance time. Revisions append; deterministic selection picks one latest eligible issuance per game/model. Sources must have eligible dates and creation/update timestamps. Strict prior-Eastern-day selection avoids same-day result leakage. Rating publication is transactional.

Legacy forecasts without adequate provenance and postgame reconstructions are distinguishable from verified pregame forecasts. Complete older configurations retain explicit compatibility behavior; incomplete historical configurations can support saved-output evaluation without being faithfully recalculated.

These protections do not eliminate findings 2–4. They also do not archive every executable or historical source box score. Rating snapshots can be republished/upserted, and source games can be corrected. Frozen forecasts preserve issued inputs, while rerunning historical ratings is not necessarily a reconstruction of what was known at the time. Do not relabel reconstructed predictions as archived live forecasts.

## Configuration audit

The main settings examined reach their intended calculations: global ridge/anchor parameters, factor-specific overrides, recency and blowout weighting, preseason blending, home-court and volatility learning bounds, and the selected prediction uncertainty model. Published configuration identity is immutable; new authored payloads are strictly checked through `publish!`. Finding 7 covers the alternate creation bypass.

| Category | Assessment |
| --- | --- |
| Tunable modeling assumptions | Prior persistence (current 0.85), 14-day gate, calendar decay (40 days with 10% floor), recency weighting, ridge, soft anchor weight, home advantage, learning rates/caps and volatility fallbacks. They need evidence, not arbitrary tuning. |
| Hardcoded modeling choices | Two finalized games for qualification; both opponents must qualify for a solver row; equal per-game observations apart from explicit weighting; possession estimator coefficient 0.475; league averages over teams; independent additive variance components; residual learning without a separate recency scheme. |
| Unit conversions/stat definitions | 40-minute pace, per-100 efficiency, rebound complements and the intentional custom three-point definition are not ordinary tuning knobs. |
| Compatibility rules | Historical formula dispatch and legacy learning fallbacks preserve published meaning. Do not replace them with today's defaults during historical replay. |
| Apparent controls without current game-prediction effect | Confidence thresholds do not provide a calibrated label; confidence is explicitly uncalibrated. The `defensive_efficiency` home-court list entry does not trigger a separate defensive fit: the offense rows already estimate both sides. Factor settings affect factor forecasts/diagnostics, not score/win means. Recruiting/departure fields without the supported efficiency-adjustment integration can be preview inputs rather than active rating effects. |

Defaults appear in authoring files and historical fallback paths. Their duplication is not by itself a defect: some preserve compatibility intentionally. New settings should have one explicit authored meaning, a frozen payload and tests proving their consumer. Unsupported combinations should fail at authoring; historical reads should retain their documented policy.

Key implementation: `RatingsConfigVersion`, `ConfigurationSchema`, `ModelConfiguration`, `LearningSettings`, `FactorForecast`, `GameWeightingService` and `config/ratings.yml`. See the audited [model tuning guide](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/docs/model-tuning.md) and [model version guide](https://github.com/zstearman3/prophet-ratings/blob/4eedc366359a94e4cbfec8c516385d8aa620bd2a/docs/model-versions.md).

## Statistical assumptions needing evidence, not verified defects

1. **Residual variance attribution.** Offense and opponent-defense volatility estimates are derived from scoring residuals that may describe overlapping uncertainty. Summing them as independent components could double count variance. Similar concerns apply to team pace contributions. The moment algebra is correct conditional on these inputs; whether the inputs are calibrated remains unproven. Inspect standardized residuals and empirical coverage before fitting extra complexity.
2. **Early-season shrinkage.** Calendar decay and a permanent prior floor are pragmatic choices. A sparse schedule can make elapsed days a poor proxy for evidence. Test effective-game-count alternatives later on chronological data; numerical feasibility of earlier updates is not proof of better predictions.
3. **Weighting and anchors.** Team-averaged league baselines, per-game solver observations and opportunity-weighted shooting aggregates answer different statistical questions. Unequal schedules can affect their relationship. Reconcile units/centering first, then assess predictive consequences.
4. **Home-court learning.** The corrected sign is verified. Learning from selected home-game residuals, with caps and shrinkage, still needs sufficient samples and schedule/venue diagnostics.
5. **Factor bounds and interpretation.** Additive adjusted rates can leave physical ranges. Evaluate bias and range behavior; do not introduce arbitrary clipping without an explicit versioned assumption.
6. **Overtime target mismatch.** Regulation-normalized pace is compared with actual pace, while score/margin/total evaluation uses full-game final scores, including overtime. That can create total bias even with sound regulation expectations. Report overtime separately before deciding whether to model extra periods.
7. **Data corrections.** Recomputed outcomes from corrected box scores can change historical evaluation. Record the evaluation extraction time/data revision where practical. Forecast inputs should remain frozen.

## Evaluation quality

The admin evaluation calculations checked out on independently reasoned synthetic observations:

- MAE is the mean absolute error; RMSE is the square root of mean squared error; bias uses predicted minus actual. Empty or missing observations do not become zeros.
- Brier score uses `(p - y)^2`; log loss uses the probability assigned to the observed winner. Infinite loss for a truly impossible outcome is mathematically correct. Finding 6 explains artificial infinities from rounding.
- Calibration bins use the actual mean predicted probability and observed win fraction, with sample counts. Charts should be read with those counts, particularly in the tails.
- Sample residual standard deviation uses the sample denominator and requires enough observations.
- Five Factor diagnostics compare eligible side-level factor predictions against observed factors and a league baseline on matching available observations. They measure factor forecast quality, not incremental score or probability improvement.

The primary paths inspected were `EvaluationReport`, `EvaluationObservation`, `PredictionEvaluator`, `PreseasonComparisonMetrics`, `FactorForecast`, the admin prediction-evaluation controller/view and their specs.

Practical limitations:

- Coverage summaries start from stored prediction records; games with no forecast need a separate expected-game denominator and explicit skip reasons. A favorable average can coexist with poor coverage.
- Common-game comparison exists, but each model can contribute its latest eligible forecast from a different horizon. A week-old baseline versus a near-tipoff candidate is not a controlled paired comparison.
- The current CSV does not provide a complete paired game-loss dataset with both issuance times, model inputs and coverage exclusions.
- Two sides of a game, repeated appearances by a team and adjacent schedule periods are correlated. Treating them as independent observations understates uncertainty.
- Small samples, changing opponent quality and schedule phases can hide systematic errors. Add compact splits for home/neutral, early/late season, overtime, forecast age and predicted-margin/probability ranges before adding elaborate charts.
- Legacy/reconstructed results must remain separate from verified live forecasts. Descriptive historical performance is not evidence of a prospective improvement.

## Concrete experiment: what works and what is missing

Example: keep baseline A's efficiency/pace model, clone its complete stored configuration into B under a new bundle name, and change one supported assumption.

| Step | Current state at audited commit |
| --- | --- |
| Clone complete payload, change one assumption, publish B without activation | Supported through strict `publish!`; finding 7 concerns alternate paths. Preserve A and use explicit IDs. |
| Produce daily A and B rating states | Not a general safe shadow workflow. Live TeamSeason ownership rejects mixed models, and shared season anchors can contaminate new forecasts (finding 2). |
| Generate forecasts for both model IDs | Supported when suitable model-specific snapshots already exist, subject to the anchor defect and publication-date mismatch. Model B need not become active. |
| Freeze issuance and collect final outcomes | Largely supported; revisions and captured inputs exist. Identity corrections and invalid finalized data need findings 4–5. |
| Compare common games | Descriptive common-game metrics work. Equal forecast horizons, full paired export and uncertainty intervals are missing. |
| Attribute each result to its inputs | Frozen forecast configuration/numerical inputs are available. This does not imply immutable historical raw data or archived executable code. |
| Test style's incremental effect | Missing: current factor forecasts do not alter score or win predictions. Changing factor weights alone cannot establish game-prediction value. |

The existing bounded preseason comparison is a specialized retrospective tool, not a general concurrent candidate runner. Do not simulate a shadow experiment by repeatedly activating models or overwriting the active model's working state.

### Small practical protocol

1. After the correctness fixes, use November–December for exploratory development. Choose a small candidate set and primary objectives before comparing January results. Freeze the selected candidate before a February-through-postseason chronological holdout. If the schedule/data budget is too small, use an earlier chronological split and explicitly call the result preliminary.
2. Freeze algorithm, settings, forecast horizon and selection rule. Normal daily updates from already-final games remain allowed, but both models receive the same available data and cutoff. This is a sequential forecasting holdout, not frozen team ratings.
3. At one scheduled pregame issuance time, generate A and B for the same eligible games; preserve skipped games and reasons. Never generate replacement live forecasts after outcomes are known. Historical reconstruction stays separately labeled.
4. Export one row per game containing both prediction IDs/model IDs, issuance times, cutoffs, predicted scores/probabilities, actual outcome, overtime flag and losses. Report individual coverage, intersection coverage and all exclusions.
5. On the common games, calculate paired differences `loss(B) - loss(A)`: negative favors B. Report absolute margin/total error, squared error (and aggregate RMSE), Brier and log loss. Preselect one or two primary objectives; do not promote on whichever metric happens to improve.
6. Report uncertainty on the **paired** mean differences. A practical first approximation resamples chronological week blocks, retaining both models and both sides of each game together; show sensitivity to one- versus two-week blocks. It is approximate because teams recur across blocks. With few blocks, show the raw range/season splits and say uncertainty is large instead of presenting narrow confidence intervals.
7. Limit candidate count and keep a record of attempted models. Repeated tuning on the same evaluation sample consumes its value as a holdout. Choose a fixed decision date; preserve a final untouched chronological period or season for confirmation.

Chronological splitting is consistent with the [scikit-learn guidance on time-series validation](https://scikit-learn.org/stable/modules/cross_validation.html#time-series-split); block resampling addresses dependence more plausibly than independent-row resampling, as discussed in [Forecasting: Principles and Practice](https://otexts.com/fpp2/bootstrap.html). Neither source establishes a particular block length or accuracy claim for this application.

### Five Factors versus incremental game-prediction value

First test whether factor forecasts outperform a simple factor baseline on the same games and sides. Then, as a separate model change, define a small explicit style contribution to score or efficiency expectations, with coefficients and all inputs frozen. Compare that candidate to the unchanged efficiency/pace baseline under the paired chronological protocol. Include a zero-style-coefficient ablation.

Good factor predictions alone do not imply improved game predictions; factors may duplicate information already captured in efficiency. Conversely, a proposed style term must not use observed factors from the target game. No current style effect on score/win probability was assumed in this audit.

## Smallest pre-season changes and later work

**Before relying on season forecasts:** fix findings 1–3 together at their interfaces (coherent early updates, model/date anchors and completed-day publication); fix the narrow integrity defects 4–7. Add a modest operational coverage report for scheduled games versus issued verified forecasts and skip reasons. This coverage report is a recommended improvement, not an eighth verified defect.

**Before running an A/B claim:** supply isolated candidate calculation state, matched pregame timing and paired export. A simple explicit shadow-run command and a small offline comparison script may be sufficient; no broad framework rewrite is justified.

**Later:** empirical volatility calibration, game-count preseason decay, richer priors, style integration/ablation, additional schedule/venue diagnostics and more rigorous uncertainty estimation. Existing multiyear/game-count comparison work remains in its current Notion story.

## Checks performed and uncertainty

On the audited archive:

- 133 focused existing RSpec examples passed across adjusted-stat calculations/corrections, aggregation, prediction building, score moments, model configuration/schema, evaluation report/evaluator, factor forecasts and the admin evaluation request.
- Four real Python/NumPy solver tests passed: independently known weighted-ridge solution (14/6), dense-reference equivalence, invalid/singular-input rejection examples, and the real Ruby/Python boundary.
- Nine independent synthetic RSpec probes passed, reproducing the seven defects (including both direct and actual candidate-publication anchor checks) and checking metric arithmetic.
- Follow-up issue-1 feasibility: four direct real-solver scenarios completed (one game plus an unplayed team, disconnected components, an exactly singular zero-ridge control, and anchor-only zero coefficients). One full Rails/Python synthetic pipeline example passed with two played teams and one unplayed participant on day 1, using a test-only zero-day gate configuration.
- The first zero-ridge control used a theoretically singular disconnected matrix that NumPy numerically solved instead of rejecting. An exact zero-column control did reject. This reinforces requiring positive ridge or explicit conditioning policy; it is not evidence that unregularized disconnected fits are reliable.

Reproduction commands used the repository's disposable Docker workflow:

```bash
bin/test spec/services/prophet_ratings/adjusted_stat_calculator_spec.rb \
  spec/services/prophet_ratings/adjusted_stat_calculator_corrections_spec.rb \
  spec/services/prophet_ratings/team_season_stats_aggregator_spec.rb \
  spec/services/prophet_ratings/game_prediction_builder_spec.rb \
  spec/services/prophet_ratings/score_moments_spec.rb \
  spec/services/prophet_ratings/model_configuration_spec.rb \
  spec/services/prophet_ratings/configuration_schema_spec.rb \
  spec/services/prophet_ratings/evaluation_report_spec.rb \
  spec/services/prophet_ratings/prediction_evaluator_spec.rb \
  spec/services/prophet_ratings/factor_forecast_spec.rb \
  spec/requests/admin/prediction_evaluations_spec.rb
docker run --rm --network none -v "$AUDIT_CHECKOUT:/rails:ro" -w /rails \
  --entrypoint python3 prophet-ratings-dev:latest test/python/test_adjusted_stat_solver.py
```

Here `AUDIT_CHECKOUT` denotes an isolated checkout/archive of the pinned commit. Independent audit probes were temporary, not committed regression tests; their fixtures, expected numbers and implementation acceptance criteria are recorded above and in the tickets. Implementing agents should turn those cases into permanent targeted tests.

The original read-only audit did not require hooks. This documentation export is subject to both repository hook suites; their outcome is reported in the task handoff. Hook success on the export checkout would not substitute for the numerical checks on the audited commit.

Remaining uncertainty: no production model/configuration inventory, forecast coverage, imported-data incidence, scheduler execution history, runtime deployment state or predictive calibration was inspected. Passing synthetic tests demonstrates behavior on controlled inputs; it does not establish that a candidate improves out-of-sample predictions.

