# CBBD cutover readiness and operator runbook

**Recommendation: NO RELEASE pending the operational gates below.** This change
prepares an opt-in pipeline; it does not deploy, enable production credentials,
replace history, establish live provider parity, or authorize activation.
Zach chose daily ratings using the prior Eastern calendar day. The operational
activation decision remains pending; deployment and historical writes each need
explicit authorization and scope.

## Scheduling and durable evidence

Production cron uses `ScheduledGameSyncJob` at 01:00, 07:00, 13:00 and 19:00
America/New_York. `GAME_SYNC_PROVIDER=cbbd` explicitly selects CBBD; the default
remains `sports_reference`. Each delivery pins its provider, current season,
published default model, Eastern date, six-hour bucket, season bounds and limits
before enqueue (also before lock contention on `perform_now`). Changing provider
configuration affects new deliveries, not retained jobs. There is no automatic
fallback or source blending.

`CbbdSyncRun` is the durable operation record. Past dates are the intersection of
season bounds and today minus three through yesterday; future dates are today
through today plus seven, clipped to the season. Each phase gets its own
`CbbdReviewRun` and PostgreSQL capture bytes, digests, normalized replay, request
ledger and quota headers. Acquisition finishes before canonical date transactions;
held dates roll back canonical writes without losing captures. No shared directory,
JSON editing, or ECS file transfer is required for scheduled evidence. Existing
manual CLI commands retain their explicit filesystem contract.

The browser workflow remains **Season → Review CBBD identities** at
`/admin/cbbd_review_runs`: create a finite fetch, wait for the worker, compare,
review matches, apply selected mappings. Source captures and review decisions are
private database records. Approval records its standard admin decision without a
required typed reason. Review memberships separately before activating a season.

Defaults: `CBBD_SCHEDULED_MAX_REQUESTS=50` **per phase**, and
`CBBD_SCHEDULED_RETRIES=2` (retry attempts count within the cap). Positive integer
caps are limited to 10,000, retries to 0–5; invalid configuration fails before HTTP.
The $10 plan discussed is 75,000 monthly requests shared with CFBD; confirm actual
account entitlement and remaining shared quota before release. Four cycles per day,
two 50-attempt caps, 31 days yields at most 12,400 scheduled attempts in an ordinary
31-day month, excluding DST extra occurrences, manual/review traffic and other
account consumers. The repeated fall 01:00 occurrence shares one pinned bucket,
so it does not mint a second acquisition budget. Six-hour buckets coalesce repeated producers; a new bucket is a
new bounded refresh. An interrupted acquisition never automatically renews its
budget. Unknown coverage and incomplete captures remain failures.

A complete nonempty past phase authorizes the pinned daily analytics job even if
future refresh fails. Source retries never independently authorize ratings.
GoodJob insertion and the enqueue marker share one PostgreSQL transaction.
`analytics_status=queued` means only enqueued. The scoped analytics delivery uses
the same heavy/ratings locks and existing calculators as manual jobs. Ratings and
`ratings_completed` commit together; predictions and `completed` commit together.
A prediction failure retries only that phase. A stale delivery becomes `stale` and
cannot calculate a new day's ratings. Generic/manual job policies are unchanged.

**Analytics completed means processing finished, not universal forecast coverage.**
The existing prediction builder can skip missing or invalid inputs. Compare eligible
scheduled games with model-specific predictions and investigate every missing game.
Retained forecast revisions and frozen calculation contexts are never rewritten.
No model formula, model hash, intraday cutoff, or solver behavior changes here.
An afternoon final may wait until the next Eastern day for ratings; the user
explicitly accepted that daily cutoff. A six-hour poll does not guarantee all finals
reach ratings within 6–12 hours.

## Release gates and monitoring

All gates must pass before a separately authorized activation:

1. Confirm worker CBBD entitlement, key availability (never paste its value),
   remaining shared quota, and selected provider. Perform an explicitly authorized
   finite live validation; synthetic tests do not establish provider completeness.
2. Review all relevant CBBD mappings, division/membership proposals and semantic
   exceptions. Zero unresolved identities, invalid final boxes, held/conflicting
   dates, or incomplete past dates in the release window. TBD/live observations
   remain future evidence and cannot certify finals.
3. Confirm a published/default model, reviewed preseason inputs and season
   activation. Require successful actual ratings and expected model/date snapshot
   lineage, with all missing forecast inputs explained and accepted.
4. Verify database backups and restore procedure include private capture/review
   tables and scheduled runs. Confirm authorized web/worker access after task
   restart/deployment, retention policy and measured storage headroom. There is no
   automatic capture cleanup policy in this change.
5. Apply migrations and **wait for successful migration task completion** before
   switching workers. The existing deployment migration-wait flaw is an unresolved
   release blocker; this ticket does not alter deployment infrastructure.
6. Confirm one intended worker topology, measured memory headroom under realistic
   retained history, and no competing scraper jobs. Small fixtures establish neither
   production memory capacity nor live provider latency.
7. Assign an operator for failed runs and quota warnings. Alert/respond when no
   complete past sync is observed for more than 12 hours during active dates.
   Monitor daily snapshot date/model separately: expected prior-day cutoff lag is
   not a sync failure. Check `analytics_error`, GoodJob retained errors/attempts,
   capture ledgers, phase failed dates and forecast coverage. No paid monitoring
   service is added here.

Inspect recent runs in a Rails console using scalar selections, for example:

```ruby
CbbdSyncRun.order(id: :desc).limit(20).pluck(:id, :schedule_date, :past_status, :future_status, :analytics_status, :analytics_job_id)
```

Use acquisition IDs to access the admin review records; do not log raw capture
bodies or credentials. A `completed` run with empty acquisitions is not evidence of
provider coverage; confirm observed schedule counts against independent expectations.

## Recovery and routing rollback

- Queued analytics failure: inspect its stable `analytics_job_id` in GoodJob. Retry
  the retained delivery only while its pinned Eastern date is current. Lock
  contention remains retryable and visible; it is not marked complete.
- Enqueue failure: rerun the retained scheduled job/run on the same date. Completed
  phases consume no new HTTP. The queue row and marker roll back together.
- Interrupted acquisition: preserve it, inspect evidence, and explicitly authorize
  a new finite run/bucket. Do not reset a failed acquisition to queued. Ordinary
  later cron buckets are independent bounded refreshes.
- Failure older than the three-day correction window: identify uncovered dates and
  perform an explicitly scoped historical catchup/review using documented
  `season:sync_games` commands with finite requests and resume checkpoints. Changing
  the rolling lookback is not a substitute for recording missed coverage.
- Pause the scheduled cron and drain/cancel the exact pending CBBD run deliveries
  before changing routing. Record their IDs. Changing `GAME_SYNC_PROVIDER` alone
  does not cancel pinned deliveries.
- To route back, explicitly select `sports_reference`, restart affected processes,
  and confirm the queue contains only the intended provider. Keep all internal
  identities, aliases, external mappings, manual decisions and forecast revisions.
  Inspect cross-provider protected finals before any new write.
- Routing rollback does **not** undo canonical games already applied. Reversal of
  a data correction requires reviewed source evidence and a separate authorized
  correction or restore plan. Do not delete observations, mappings or snapshots
  as a rollback shortcut.

## Sports Reference inventory and cutover disabling

The selected CBBD scheduled path calls Adapter/database replay/canonical import,
not `GamesIngestionService`'s Sports Reference acquisition. Compatibility remains:

- `SyncNightlyGamesJob`, `SyncDailyGamesJob`, `SyncFullSeasonGamesJob` retain explicit provider-aware manual workflows.
- `SyncTeamGamesJob` and `SyncFromLastGamesJob` retain legacy team-game scraping.
- `Ingestion::GamesIngestionService` calls `Scraper::GamesScraper`; legacy venue
  enrichment calls `Scraper::TeamScheduleEnrichmentScraper` via
  `Importer::GameVenueEnricher`. Both must remain absent from CBBD acquisition.
- `season:align_conferences` calls `SeasonConferenceAlignment` /
  `Scraper::ConferenceStandingsScraper`. `season:bootstrap` calls it by default;
  use `ALIGN_CONFERENCES=false` for explicitly authorized CBBD preparation and
  use reviewed CBBD memberships instead. `season:prepare` does not scrape.
- `import:games` defaults to the selected provider and iterates stored seasons;
  do not use it as routine cutover setup. `import:base` reads stored CSV files,
  including `scraped_teams.csv`; it is retained compatibility, not a live HTTP
  path. `Scraper::TeamsScraper` remains callable manually but has no active
  application/task caller found in this inventory.

Before activation, inventory GoodJob queued/retry deliveries for these classes,
stop old cron producers, and cancel or finish explicitly selected legacy deliveries.
Do not run legacy team/conference/game imports during the CBBD validation window.
Retain compatibility through that window. Remove code only after approved rollback
retirement and auditing remaining callers; preserve identity/evidence history.
Unrelated integrations and licensing of retained legacy data remain out of scope.

## Disposable rehearsal and historical disposition

The automated rehearsal uses checked-in synthetic
`spec/fixtures/ingestion/cbbd/final.json`: season2026, final on 2025-11-01, score
65–64, 40 minutes; synthetic future game on 2025-11-03. Before ingestion no games
exist. After ingestion the final and scheduled game retain CBBD identities; daily
publication stores 2025-11-01 snapshots with the pinned model and an operational
pregame forecast for the future game. Duplicate delivery consumes no new requests
and preserves forecast attributes. Failed identity reconciliation leaves zero
canonical games while two capture bodies remain verifiable after reload.

The regression suite separately exercises browser fetch/review/apply, invalid
boxes, TBD/live handling, protected corrections, bounded historical resume,
missing final boxes and repeated acquisition. Exact executed commands/results are
recorded in the implementation handoff; fixtures do not establish live parity.
Historical correction/resume checks are bounded synthetic evidence only. The
new offline resume case starts with both team identities absent: zero Games and
TeamGames survive the failed 2025-11-01 date. After explicit identity repair it
imports the same retained65–64 evidence; compatible resume then skips the date and
preserves IDs and all derived attributes without another request. Existing
canonical importer tests separately apply ordered synthetic corrections100→102
(home offensive efficiency125.307), while unknown-freshness corrections are held
at100. CBBD fixture freshness is unknown: this is not evidence that live CBBD
corrections can be automatically ordered. Existing cross-provider/manual-authority
and mapping tests retain those protected values and forecast histories.

**Disposition: retain existing production history and defer replacement.** Mixed
history keeps its provider provenance and protected finals; cross-provider changes
need review. Evaluation comparisons must state provider/semantic profile and
history coverage. Do not claim prediction improvement from this cutover or mark
the separate ticket08 historical parity/replacement work complete. Any unavailable
live examples and operational gates above remain unverified until authorized.
