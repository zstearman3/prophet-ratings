# Annual drafted-player departure acquisition

This file-only workflow prepares the accepted draft-departure evidence for a target
season. Draft year Y requires prior college season ending Y and target Season.year
Y+1. It does not create players, teams, profiles, seasons, ratings or penalties.
Database persistence/publication is a separate downstream story. No data import,
backfill or activation is part of these commands.

## Prepare and capture sources

Use the complete official NBA **results** article, not an early-entry list, mock
draft, declaration or withdrawal page. The `nba_results` parser supports numbered
selection paragraphs under First Round/Second Round headings, with NBA prospect
URLs and an annual Results: Picks 1-N title. It requires the entire published
pick range and both rounds. An unsupported/partial page is a failure, never zero
selections. Cross-check the actual selection list and rescinded picks before
entering `expected_picks`; do not assume every year has 60 selections.

The `sidearm_totals` parser supports official-school Sidearm HTML with the exact
season Cumulative Statistics heading, Overall Totals table, unique Player/GP/MIN/PTS
columns and an overall team Total Points row. It was checked against the public
[Rutgers overall table](https://scarletknights.com/sports/mens-basketball/stats/2024-25).
Other layouts, PDFs and conference-only tables require a targeted parser/fallback;
there is no universal school scraper. Verify each source's official ownership,
final season scope, postseason inclusion and exhibition exclusion. Record that
verification in `scope_evidence`. The title proves which season the table describes,
not that the season is finished. A final-scope assertion requires operator review.

Prepare a JSON plan with explicit years, actual expected picks, and source locations.
The following **synthetic** example needs real independently verified source URLs,
labels and evidence; list every actual expected pick (the shortened array is only
an illustration):

```json
{
  "draft_year": 2025,
  "prior_season_year": 2025,
  "target_year": 2026,
  "expected_picks": [1, 2, 3],
  "predecessor": null,
  "sources": [
    {
      "id": "draft",
      "type": "nba_results",
      "url": "https://www.nba.com/news/2025-nba-draft-order"
    },
    {
      "id": "school-final",
      "type": "sidearm_totals",
      "url": "https://school.example/sports/mens-basketball/stats/2024-25",
      "team_name_source": "Exact source school label",
      "scope": "overall_season_including_postseason_excluding_exhibitions",
      "scope_evidence": "Official-school final season scope verification and evidence"
    },
    {
      "id": "participation-proof",
      "type": "evidence",
      "url": "https://school.example/sports/mens-basketball/roster/player/123"
    }
  ]
}
```

School URLs and evidence sources are operator-selected. `evidence` captures hold
participation, nonparticipant or cross-provider player identity proof; their prose
is reviewed by the operator, not interpreted automatically. Add source-specific
school aliases separately with `TeamAlias.source` equal to that source URL's host.
The commands never create aliases or guess school URLs from names.

Run in the intended Rails environment, for example through an already running
isolated local stack (`bin/compose exec web` before `bin/rails`):

```bash
bin/rails departures:acquire PLAN_PATH=/artifacts/plan.json OUTPUT_DIR=/artifacts/draft-2025-capture-1
```

The new directory contains exact `<sha256>.html` response bytes, `manifest.json`
and `dataset.json`. Requests have a 30-second timeout and do not follow redirects.
HTTP errors (including 403), network errors, unsupported layouts, malformed totals
and wrong seasons are recorded per source. Successful sources remain available in
a partial bundle. The command prints its immutable dataset hash and failures,
then exits nonzero on partial acquisition. It neither retries with access-control
workarounds nor claims a partial bundle is complete. Choose official sources only;
these are explicit operator requests, never URLs supplied by end users.

An existing OUTPUT_DIR is refused. New captures/changed evidence need a successor
directory and a `predecessor` referencing the previous dataset hash. Keep source
artifacts in durable operator-managed storage; retention does not require adding
annual bundles to Git. Do not store them under an ephemeral container path.

## Saved-source fallback and deterministic replay

NBA requests may return 403. Save the publicly accessible page HTML through an
allowed normal source-access path, retaining its actual URL and capture time. Build
a new capture directory with those unmodified bytes and a manifest using the same
plan fields plus the following metadata on **each** captured source:

- `snapshot_kind`: `raw_html`; `snapshot_location`: `<sha256>.html`.
- `snapshot_sha256`: SHA-256 of the exact file bytes, not extracted/transcribed facts.
- `http_status`: 200 only for a successful original response; preserve blocked
  responses in their original directory instead of relabelling them.
- `captured_at` and `observed_at`: actual ISO-8601 timestamps with timezone.
- `source_as_of`: supported ISO-8601 timestamp, or null with `source_as_of_reason`.
- `failure`: null on usable captures; otherwise the exact access failure.

Use `shasum -a 256 saved.html` to calculate the byte hash. Keep the original capture
manifest intact; saved-source recovery is a successor bundle. Factual transcriptions
are not supported by this raw-HTML parser; never label their hashes as HTML hashes.
Unsupported layouts need a focused adapter with fixtures. A blank/blocked page
must remain a failure. No browser automation platform is needed.

```bash
bin/rails departures:replay CAPTURE_DIR=/artifacts/draft-2025-capture-2 DATASET_PATH=/artifacts/draft-2025-capture-2/dataset.json
```

Replay verifies snapshot locations, byte hashes, capture metadata, annual title,
columns and numeric totals before producing `draft-departures-v1` with extraction
version `nba-results-sidearm-totals-v1`. Same manifest/bytes produce the same JSON
and dataset revision. Identical output files are a no-op; different existing output
files are refused. Capture timestamps change only on a new acquisition; neither
capture time nor a factual source date proves historical pregame availability.

## Review identity and participation separately

```bash
bin/rails departures:preview CAPTURE_DIR=/artifacts/draft-2025-capture-2 DATASET_PATH=/artifacts/draft-2025-capture-2/dataset.json
```

The preview rereads sources and compares the supplied saved dataset to exact replay.
It never fetches live pages. Without a reviewed mapping file, selections remain
unknown_participation, even when affiliation looks collegiate or international.
The report retains provider player URLs, original names/affiliations, round/pick,
source IDs, coverage, failures, subtotals and nullable team loss. This is a read-only
review interface; it does not approve files automatically.

Create a separate reviewed mapping revision referencing the exact `dataset_revision`.
Use immutable files and explicit successor revision IDs for corrected mappings;
never edit an already approved mapping. Example shape (synthetic identities):

```json
{
  "revision_id": "departure-mapping-1",
  "predecessor": null,
  "dataset_revision": "replace-with-exact-dataset-sha256",
  "reviewed_by": "Actual reviewer identity",
  "reviewed_at": "2026-10-13T12:00:00Z",
  "decision": "approved",
  "decisions": [
    {
      "selection_key": "2025/1",
      "status": "eligible_prior_season",
      "reason": "Draft profile and prior-season roster identify the same individual; complete participation reviewed",
      "evidence_source_ids": ["draft", "participation-proof", "school-final"],
      "stints": [
        {
          "source_id": "school-final",
          "team_id": 123,
          "player_source_url": "https://school.example/sports/mens-basketball/roster/player/123",
          "identity_evidence_source_ids": ["draft", "participation-proof"]
        }
      ]
    }
  ]
}
```

Every actual selection needs a final category: `eligible_prior_season`,
`verified_no_college`, `verified_nonparticipant`, `outside_prior_season`,
`unknown_participation`, `unknown_production`, `unresolved_identity` or
`conflicting_evidence`. Require actual captured evidence and a reason, including for
exclusions. International/pro affiliation alone is insufficient exclusion evidence.
A zero-point participant with games played is still eligible; games zero requires
reviewed nonparticipant evidence. Never use prior/career totals for the wrong season.

Only eligible selections have `stints`. Supply one entry per evidenced prior-season
team, using each school's roster identity and full-team denominator. Explicitly
review that the draft and school URLs identify the same person; names alone cannot
resolve ambiguity. For known-team `unknown_production`, supply `team_name_source`
and `team_source` (official-school host), plus participation evidence establishing
all prior-season team identities. Do not use this category when participation or
other possible stints remain unknown. Other unknown/conflicting categories always
block coverage globally.

Canonical school names and source-scoped aliases use unique exact matches after
trimming surrounding whitespace only. All candidate IDs are retained for unknown
rows; eligible mismatches/ambiguities reject the preview with candidate IDs. Resolve
aliases/decisions manually and create a new reviewed mapping file, without automatic
team/player creation. Duplicate picks, player provider identities, reviewed decisions,
reused school players, inconsistent denominators and unexpected/undrafted selection
keys reject validation. Conflicting evidence needs explicit resolution in a successor
review rather than choosing the larger value or first matching name.

```bash
bin/rails departures:preview CAPTURE_DIR=/artifacts/draft-2025-capture-2 DATASET_PATH=/artifacts/draft-2025-capture-2/dataset.json REVIEW_PATH=/artifacts/departure-mapping-1.json > /artifacts/departure-preview-1.json
```

Production points/games are nonnegative integers; participating contributions require
positive team points. Parsed player points must sum to team points. Drafted points
cannot exceed that denominator. Minutes are whole cumulative player-minutes, retained
for audit only, with the full team player-minute sum rather than game-clock minutes.
No per-game extrapolation, minimum games, draft-rank proxy or top-ten cutoff applies.

Team loss is sum of eligible drafted points / total team points. It is known only
after the complete draft and all relevant evidence are resolved. Failed sources or
globally unresolved participation/team identity keep every team's loss null. A known
team's unknown production blocks that team alone. Known subtotals are displayed but
never extrapolated. Complete evidence with no eligible departures gives verified_zero;
unknown/partial coverage stays null. Every stored Team appears, without inferring
Division I eligibility from database presence. The command exits nonzero if any
team loss is null, retaining the report for targeted review. No penalty is computed.

Before downstream import, review complete draft accounting, source ownership/scope,
all player/team identity evidence, zero/excluded cases, denominator discrepancies,
missingness and the mapping hash. Save the actual dataset hash, separate
`reviewed_revision` hash, reviewer/time, manifest and preview together. Preview
hashes are provenance, not proof of human approval or historical availability.

## Saved admin workflow

From **Offseason setup → Review departure batches**, select a prepared target
season. Save explicit draft, prior and target ending years, the actual expected
pick numbers (exclude rescinded picks), and operator-selected supported HTTPS
sources. Add/remove source rows with the form; school totals require the exact
published school label and final overall scope evidence. No JSON, local paths or
manual hashes are needed. At most 200 configured sources are accepted.

Queue acquisition and refresh the batch page. The existing GoodJob worker must
be running. Attempts expose queued/running/completed/incomplete/failed states;
each source's original bytes and metadata are retained privately in PostgreSQL,
including blocked HTTP responses. Duplicate deliveries do not refetch terminal
attempts. A redelivered running attempt is marked interrupted; explicitly queue
its successor. Earlier attempts are never relabelled or erased.

If normal permitted access provides an original saved HTML response, use the
recovery form. Supply its actual configured URL, successful HTTP status, capture
and observation timestamps, and publication timestamp or an explicit unknown
reason. Upload unchanged HTML (maximum 5 MiB); server-side hashing and the same
source-specific parsers apply. Unsupported/wrong-season pages remain explicit
failures. Recovery creates a successor attempt; it does not bypass restrictions.
Original HTML downloads are admin-only attachments, never executed as app HTML.

Every parsed selection from both rounds is listed. Save its accounting category,
reason, captured evidence choices and school player/team mappings. Facts and
production totals are read-only. To record multiple prior-season stints, fill the
blank stint, save, then fill the next blank stint. No teams, aliases or memberships
are created by this screen. Unfinished decisions can be saved and resumed; invalid
identities, conflicting evidence, duplicates and invalid totals block approval.

Review the saved report before explicitly approving it. Unknown/partial losses
remain null; a verified zero requires the existing complete accounting contract.
Allowed partial publication lists actual unresolved selections, missing expected
picks, source failures and unknown target-team losses, and requires an explicit
acknowledgement retained with reviewer/time and those exact gaps. Acknowledgement
never overrides failed sources or other hard validation. Changed drafts/evidence,
aliases, memberships, profiles or latest revisions require fresh review.

Publication uses the existing immutable input revision/import contracts, retains
the authenticated reviewer's email and time, and never calculates or activates
ratings. Exact publication retries return the same revision without rewinding
profile pointers. Start a correction with an explicit reason; its new draft can
reuse the prior immutable capture for decision-only corrections, or acquire/recover
new evidence. It receives fresh approval and gap acknowledgement. CLI/file workflows
remain supported for compatibility.
