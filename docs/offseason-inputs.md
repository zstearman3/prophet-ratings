# Annual offseason inputs

Use this workflow before [preseason publication](offseason.md#4-initialize-and-review-preseason-values)
when the selected model uses recruiting, drafted-player departures or coaching.
`YEAR=2027` uses 2026 recruiting/draft evidence and prior 2025–26 production.
These effects are experimental; review coverage and fallbacks without assuming
an accuracy gain. Missing evidence stays unknown, distinct from verified zero.

Work in the intended dataset with stored teams, prior-season ratings and a prepared
inactive target season. A fresh database lacks that history. Locally use an
[isolated stack](development.md); container `/rails/tmp/` maps to checkout `tmp/`.
Retain captures, reports and approvals durably. Acquisition automates parsing,
hashing, matching and loss arithmetic; operators verify source scope, participation,
identities and approvals. Unsupported source layouts need an adapter, not invented data.

## 1. Acquire and approve recruiting

Open **RailsAdmin → Seasons → target season → Review recruiting**.

1. Click **Fetch recruiting data**. The background worker fetches the prior recruiting
   year's 247 Recruit Composite pages into a database batch and normalized row records.
   Keep the worker running (`bin/dev` starts it); use **Refresh status** while fetching.
2. Review source school, team mapping, class points, average rating, commits and row
   issues (50 rows per page, unresolved rows first). Save changes before switching
   pages. Choose an existing team or explicitly exclude unmatched rows. Source
   numeric values are read-only. Blank points remain unknown; zero stays verified zero.
3. Click **Save mappings** to pause/resume review, or check the review confirmation
   and **Approve and publish recruiting inputs** to save the choices and publish together.
   No JSON files, paths, hashes, reviewer text or version names are required.

Automatic matching checks canonical school names and stored aliases from every
source, ignoring case and surrounding whitespace. Only one distinct team resolves;
conflicting identities require review. Matching runs when the batch is fetched.
Fetch a new batch after adding aliases; saved mappings in existing batches stay intact.

Approval prepares missing target-season rows for mapped schools and stores an
immutable `OffseasonInputRevision`, linking offseason profiles to that revision.
It does not calculate ratings, publish preseason priors or activate the season.
Source pages and exact decimal values are retained in the database. Failed captures
are visible and cannot be approved; new fetches create separate batches. Duplicate
identities, invalid source values and stale reviews block publication. Partial
coverage stays explicit and omitted/excluded teams remain unknown.

Published batches are closed to further edits. Fetch and review a new batch for a
correction; publication retains the previous revision automatically. See
[recruiting internals and recovery](recruiting.md) for source validation and failure handling.

## 2. Acquire and review drafted-player departures

Create a [source plan](departures.md#prepare-and-capture-sources) with
`draft_year=2026`, `prior_season_year=2026`, `target_year=2027`. Verify the actual
draft results URL and every selection in both rounds, accounting for rescinded
picks. Select official final cumulative school-stat URLs plus roster/identity/
participation proof for potential college participants; example URLs are not sources.

```bash
bin/compose exec web bin/rails departures:acquire PLAN_PATH=/rails/tmp/offseason-2027/departure-plan.json OUTPUT_DIR=/rails/tmp/offseason-2027/draft-capture-1
bin/compose exec web bin/rails departures:preview CAPTURE_DIR=/rails/tmp/offseason-2027/draft-capture-1 DATASET_PATH=/rails/tmp/offseason-2027/draft-capture-1/dataset.json
```

Inspect failures in the manifest/dataset and hashed source HTML. Use a new capture
directory for a changed plan; preserve failed captures. For source recovery, see
[saved-source replay](departures.md#saved-source-fallback-and-deterministic-replay).

Save a [decision file](departures.md#review-identity-and-participation-separately)
pinning the dataset hash and actual reviewer/time. For every `2026/<pick>`, verify
prior-season participation, stored Team, school identity and all relevant stints.
The parser supplies player points/team denominators; review supplies identities,
categories, evidence IDs and reasons. International affiliation alone never proves
zero. Include zero-point eligible players and multiple departures from one team.

```bash
bin/compose exec web bin/rails departures:preview CAPTURE_DIR=/rails/tmp/offseason-2027/draft-capture-1 DATASET_PATH=/rails/tmp/offseason-2027/draft-capture-1/dataset.json REVIEW_PATH=/rails/tmp/offseason-2027/departure-review-1.json
```

Retain the report even on nonzero exit. Null loss means incomplete evidence, not
verified zero. Unknown participation/global identity blocks complete accounting;
failed sources and evidence conflicts must be resolved before input publication.

## 3. Import reviewed departure evidence

Recruiting is published directly from the admin review screen. The file import
command supports departures only and requires existing Season/TeamSeasons. It
validates saved files without network requests and publishes input revisions/profile
pointers only. It does not publish ratings, prepare teams or activate anything.

Use the original `CAPTURE_DIR`, `DATASET_PATH`, and approved decisions as `REVIEW_PATH`:

```bash
bin/rails offseason_inputs:import YEAR=2027 KIND=departures CAPTURE_DIR=/path/to/capture DATASET_PATH=/path/to/dataset.json REVIEW_PATH=/path/to/review.json VERSION=review-2027-1 REASON='Initial evidence review' INPUT_HASH=inspect
```

The first validation reports the expected hash. Replace `INPUT_HASH=inspect` with
that exact hash and rerun to obtain coverage and `preview_key`. Inspect source
scope/dates, approval, excluded rows and each team's raw inputs. Apply the identical
command with `APPLY=true PREVIEW_KEY=<reviewed-key>`.
Input and model publication have distinct keys and transactions.

Approved partial coverage remains explicit: missing recruiting points and incomplete
draft loss stay null. Never copy provider class points into legacy `recruiting_score`
or infer returning minutes from draft points. Fatal numeric/identity/denominator
conflicts and unapproved reviews fail validation.

Published OffseasonInputRevisions retain hashes, approvals, normalized evidence,
source bytes and units; profiles point to the current recruiting/departure revisions.
Identical imports are no-ops. Corrections require a new `VERSION`, correction
`REASON`, and `PREDECESSOR_ID=<latest revision ID for season/kind>`, followed by a
fresh hash/preview. Old revisions remain immutable; retrying one never rewinds pointers.
File/mapping/profile changes invalidate the key; failed publication rolls back.
Keep original bundles for replay and resolve missing legacy profile provenance deliberately.

## 4. Review coaching when the model enables it

Open **RailsAdmin → Seasons → target season → Review coaching**, or use
**Coaching changes → Review coaching** to choose an ending year before Season
preparation. The review screen is `/admin/coaching_reviews`.

1. Click **Fetch coaching changes**. The background worker fetches the prior year's
   HoopDirt D1 tracker and stores pending candidates. Use **Refresh status** while
   it runs. Fetch failures show on the page and preserve existing decisions/readiness.
2. Review source incoming/former coach labels and proposed previous teams alongside
   the editable facts. Resolve destination/previous teams with the dropdowns and
   correct coach names as needed. Source conflicts and absences remain visible.
   Use **Add a manual coaching candidate** for a missing move.
3. Verify previous Team/year/role manually. Assert **Verified full season as head
   coach** and **Verified previous-season Division I participation** only with
   evidence; a TeamSeason or membership does not establish either. Assistants,
   first-time hires and partial histories can be confirmed facts while remaining
   ineligible for a pace contribution.
4. Choose **Pending**, **Confirmed** or **Rejected** for each row. Check the review
   confirmation and click **Save review** to resume later. The confirmation also
   explicitly reconfirms edits to confirmed facts. There are 25 rows per page;
   save before switching pages. Stale forms and invalid history fail atomically.
5. When all candidates on every page are confirmed/rejected, check the confirmation
   and click **Save and mark year ready**. An intentionally empty year may be ready;
   a missing review means unready. Pending candidates, running discovery and failed
   discovery block new readiness. New/changed candidates and source absences clear
   readiness; unchanged discovery retries preserve it.

No JSON reports or file imports are required. Source fetches never overwrite
confirmed/rejected decisions. Review on this screen changes stored coaching facts
and readiness only; it does not recalculate ratings or alter published captures.
See [discovery details](data-ingestion.md#coaching-change-discovery) for matching,
conflict handling and recovery. The existing RailsAdmin record forms remain
available for individual maintenance.

To publish the experimental coaching configuration in Rails console:

```ruby
payload = RatingsConfigVersion.authored_config.merge(
  Rails.application.config_for(:ratings, env: :coaching_experiment).to_h.deep_symbolize_keys
)
version = RatingsConfigVersion.publish!(payload)
```

Use a new bundle name if changed settings were already published. Review the
[coaching formula and eligibility](ratings.md#experimental-reviewed-coaching-pace):
initial v2 weight is 0.50 with no cap; older captures retain their own formula.
Fresh captures/revision previews require year readiness even at zero weight;
normal initializer repeats reuse captures. Inspect each team's `coaching` report,
exclusion reason, source facts/numbers and before/after pace. Coaching affects pace
separately from recruiting/departure efficiency effects. The existing preseason
comparator cannot evaluate coaching-enabled models.

## 5. Preview the combined model and review movers

Author a newly named complete model from a stored bundle in Rails console:

```ruby
payload = RatingsConfigVersion.find_by!(name: 'your-source-model').config.deep_dup
payload['bundle_name'] = 'your-experimental-reviewed-r3-model'
payload['preseason'].merge!(YAML.load_file(Rails.root.join('config/examples/reviewed_efficiency_r3.yml')))
version = RatingsConfigVersion.publish!(payload)
```

This stores configuration without activating it. Retain existing blend/baseline/
profile and optional coaching settings. See the [efficiency configuration contract](ratings.md#experimental-combined-reviewed-efficiency)
for units, formulas and initial experimental parameters.

Save a read-only revision preview:

```bash
bin/compose exec web bin/rails season:revise_preseason YEAR=2027 MODEL_VERSION=your-experimental-reviewed-r3-model > tmp/offseason-2027/model-preview.txt
```

The output is JSON followed by an instruction line; keep it as text, or extract
only the JSON object for JSON tooling. Review:

- `teams[].inputs`: evidence/reviewer/revision hashes, scope, coverage, excluded
  selections, baseline provenance and unresolved/excluded season participants.
- `teams[].efficiency`: recruiting/departure contributions, missing-input reasons,
  weights, pre-cap sum, bounds, combined adjustment and offense/defense allocation.
- `outputs_before` / `outputs_after` and season anchors: proposed net is offense
  minus defense. Sort descending net, breaking ties by ascending Team ID; compare
  against unadjusted baseline net and inspect the largest absolute adjustments.
  Review every eligible draft loss, including observed zero-point participants.

Resolve nonzero legacy profile overlap when either new factor is enabled. Missing
inputs retain zero effect with an unknown-coverage reason. Both weights zero
restore legacy calculation; one zero isolates the other factor. Config-only tuning
uses another new bundle name and preview against the same evidence.

Apply only after reviewing the unchanged model key through the
[guarded preseason revision](offseason.md#deliberate-inactive-preseason-revisions),
then inspect ranks/snapshots and a scheduled forecast. Return to the
[readiness checklist](offseason.md#readiness-checklist-and-decision-record) before
activation. Failed model publication rolls back rating writes but leaves earlier
input imports intact. Corrected evidence after capture needs a new model revision;
never edit old captures/configurations or delete forecast history to force a retry.
A real annual effects report requires reviewed files and stored history; synthetic
checks alone do not establish real coverage or predictive improvement.

## Legacy profile maintenance

Before the profile-provenance migration, run `bin/rails season:offseason_profile_duplicates`
and resolve conflicting IDs deliberately. One current profile per TeamSeason is
enforced; historical evidence remains in immutable captures. Editing legacy inputs
requires `source_reference`, `observed_on`, `input_units` and `manual_adjustment_reason`
(including for zero adjustment). Use `TeamOffseasonProfile::INPUT_UNITS`: recruiting
is `local_score`, returning minutes is `fraction`, manual adjustment is
`points_per_100_possessions_per_side`. Nil means missing; zero means observed zero.
Provider class points belong in reviewed input revisions, not these legacy fields.
