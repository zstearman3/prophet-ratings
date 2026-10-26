# Recruiting review

Recruiting uses database-backed acquisition and approval. Open **RailsAdmin →
Seasons → target season → Review recruiting**. Follow the
[annual recruiting steps](offseason-inputs.md#1-acquire-and-approve-recruiting)
for fetching, mapping and publishing. Keep the background worker running.

## Acquisition

`AcquireRecruitingBatchJob` calls `Recruiting::BatchAcquisition` and the bounded
CBBD client. Selecting target season Y+1 explicitly selects recruiting class Y;
for example target 2027 requests `/recruiting/teams?year=2026`, with no team or
conference filter. Configure `CBBD_API_KEY` for the web/worker runtime. New fetches
never request 247 or fall back to it. Legacy queued 247 batches fail with guidance
to fetch a new CBBD batch; ready/published/failed historical captures remain readable.

The shared CBBD client allows at most three HTTP attempts, including two retries,
with 10-second connection and 30-second read timeouts. Timeout, transport and quota
failures may retry; authentication failures do not. Retry-After delays above 30
seconds stop retries. Every response attempt is checkpointed in the batch with its
annual request, timestamp, status, safe headers, exact sanitized bytes and SHA256.
The bearer key never enters retained evidence. Failed captures remain inspectable
through the admin-only **Download response** links, including each retry, and
cannot be approved; successful `[]` is empty coverage, not an acquisition failure.

Extraction `cbbd-team-recruiting-json-v1` parses the retained selected response with
decimal-aware JSON, not the transport's Float rows. `teamId` must be a positive
integer, `year` must equal the selected class, `team` supplies the original label,
`ranking` is source rank, and `rating` is class points. Missing rank/points stay
unknown; an explicit numeric zero stays zero. Supplied invalid identities, years,
ranks, negative/nonfinite or nonnumeric points fail closed with the raw capture
retained. Average rating and commit count are unavailable and remain null. There
are no invented team URLs, player aggregates, transfer or combined inputs.

Review and publication reproduce normalized values from the retained successful
raw response and verify hashes as well as stored entries. Coverage is always
partial (or empty); an array response does not establish annual completeness.
Upstream publication time is unavailable and retained as null with a reason.
Neither retrieval time nor a successful request certifies source freshness.

`RecruitingBatch` retains exact source captures, timestamps, coverage, errors and a
source fingerprint. `RecruitingEntry` stores normalized values separately from
editable team mapping/exclusion decisions. JSON and base64 are internal encodings
for retained evidence; operators do not prepare or manage files.

## Matching and review

For CBBD, an existing `TeamExternalIdentity(provider: 'cbbd', external_id: teamId)`
wins even when the provider label changes or matches another school's alias.
Otherwise `Team.matching_school_or_alias(name)` proposes a unique exact canonical
name/alias match, ignoring case and surrounding whitespace. These are draft
proposals, never automatic team creation. Manual assignments cannot override a
durable provider identity.

Matching runs when a batch is fetched. The admin table retains editable mappings
or explicit exclusions, with 50 rows per page. Save before changing pages; approval
validates the whole batch. Draft saves do not create provider identities. Approval
atomically associates included CBBD IDs with their reviewed canonical teams using
`TeamExternalIdentity.associate!`, alongside TeamSeason preparation, immutable
revision publication and profile updates. Excluded previously unmapped IDs stay
unassigned. Existing correct IDs are reused by subsequent batches. Preview tokens
pin present and absent identity ownership; stale/concurrent conflicting ownership
blocks approval and rolls back the submission. No operator explanation is required:
approval records the admin, time and standard `Approved by admin` reason.

The following source-specific exceptions continue to apply only to historical 247
captures under `247-recruit-json-v1`:

A missing external 247Sports school identifier is a warning, not a publication
blocker. The reviewer must approve the internal team assignment or explicitly
exclude the row. Approval uses that internal assignment; it never fabricates an
external identifier. Blank identifiers do not count as duplicate identities.
Original source bytes, identifiers and validation errors remain retained alongside
the review warning and approval audit. This also applies to existing ready batches;
reload the review page to use the updated rule without fetching again.

Duplicate source identities or mapped teams, invalid numeric values, unresolved
rows, missing school names or source URLs, malformed identifiers, modified source
evidence and stale previews block publication. Manual exclusions do not bypass
these fatal source errors. Approval prepares missing target
TeamSeasons and retains the signed-in reviewer and approval time automatically.

The exception is an explicitly excluded, unlinked entry displayed at rank zero:
247 sometimes lists these with a plain-text school name and no school URL or ID.
The parser preserves that text and displayed points on new captures. Existing
ready batches can also exclude these entries without refetching. Their original
source values and validation errors stay in the approval evidence; they contribute
no team inputs. Other invalid numeric values and duplicate identities still block
publication, even on excluded rows. An unranked entry cannot be mapped and imported.

Failed approval keeps the batch unpublished and rolls back that submission's
mapping changes. The error page preserves submitted choices and refreshes its
review token from stored data, so **Save mappings** can retain those choices for
another attempt. A genuinely stale page still requires reloading.

## Publication and recovery

`Recruiting::DatabaseBundle` validates retained captures against normalized rows,
then `OffseasonInputs::Import` publishes an immutable `OffseasonInputRevision` and
links the season's offseason profiles. The revision retains source bytes, hashes,
review decisions, exact class points and units. It does not populate legacy
`recruiting_score`, calculate ratings or activate the season.

Published batches are closed to editing. Fetch a new batch for a correction;
approval links its predecessor automatically. Exact retries do not rewind newer
revisions. Existing revisions and frozen ratings evidence remain readable.

Failed captures remain visible in the batch and cannot be approved. Start a new
fetch after source access recovers. For background errors use
`bin/compose logs --tail=100 worker`; see [local development](development.md).

## Source semantics evidence (2026-10-26)

The [CBBD recruiting schema](https://api.collegebasketballdata.com/api/recruiting)
and [provider implementation](https://github.com/CFBD/cbb-api/blob/main/src/app/recruiting/service.ts)
identify the annual team ranking. `getTeamRankings` selects `teamRecruiting.points`
and returns that field as `rating`; it does not return an ordinal rank as points.
A genuine retained response for `year=2025` captured at **2026-10-26T21:27:50Z** is
`spec/fixtures/recruiting/cbbd-2025.json` (SHA256
`1b550e759b78cba16f2c8a9de38183dcd81849f1237a83c81240b4f963ced196`).

The same-day [247 class 2025 Recruit Composite page](https://247sports.com/Season/2025-Basketball/CompositeTeamRankings/)
had the canonical class-2025 URL and heading. Selected factual HTML fields are
retained in `spec/fixtures/recruiting/247-2025-parity-excerpt.html` as a
whitespace-normalized serialized excerpt, not exact raw source bytes. Heading and
update fields contain only their direct source text; the eight factual row values
are preserved. Factual comparisons/source hashes are in `cbbd-2025-comparison.json`.
The original full HTML SHA256 was
`1163342ee813bfc79fc0e8b444560896b21a68145709d4e28da897ca81caa058`.
Its displayed update text was `08/22/26 at 9:30 PM CST`; that is retained text,
not an independently verified upstream timestamp. Both sources agree exactly:

| 2025 class rank | School | Composite class points (both) |
| --- | --- | --- |
| 1 | Duke | 70.04 |
| 2 | Arizona | 69.52 |
| 3 | Houston | 68.54 |
| 4 | Arkansas | 68.27 |
| 5 | North Carolina | 66.63 |
| 6 | SMU | 66.19 |
| 7 | Kentucky | 66.04 |
| 8 | Tennessee | 66.02 |

This representative same-class evidence establishes compatible men's high-school
Recruit Composite class-point semantics: class 2025 supplies target season 2026,
not a game-season filter. It does **not** prove current freshness or completeness.
The observed class-2026 discrepancy remains unresolved: CBBD Duke 69.16 / Arkansas
65.45 versus the current 247 page's 70.15 / 70.43. No upstream-as-of time or
freshness guarantee is inferred, and no calibration/curve changes are introduced.

New approved inputs carry `cbbd_recruit_composite_class_points`; historical
`247_recruit_composite_class_points` retains its meaning. Both use the same
numerical formula and configuration hashes. Equivalent approved points reproduce
the same quality fraction, attenuation, contribution and combined preseason outputs.
Historical evidence/approvals/ratings are never converted or backfilled.
