# Recruiting review

Recruiting uses database-backed acquisition and approval. Open **RailsAdmin →
Seasons → target season → Review recruiting**. Follow the
[annual recruiting steps](offseason-inputs.md#1-acquire-and-approve-recruiting)
for fetching, mapping and publishing. Keep the background worker running.

## Acquisition

`AcquireRecruitingBatchJob` calls `Recruiting::BatchAcquisition`, reusing the bounded
247 Recruit Composite parser. Source recruiting year Y targets season Y+1; the
admin action supplies the prior year automatically. Transfer, combined and
conference-filtered rankings are rejected.

The fetch follows advertised pagination URLs on the supported host, up to 20 pages,
with a one-second delay and a 30-second request timeout. Partial coverage remains
explicit when another page is advertised at the limit. A missing school is not
proof of zero recruiting production or nonparticipation.

The parser retains source labels, provider identities, URLs, rank, class points,
average rating and commit count. Displayed numeric values are validated as finite,
nonnegative decimals; missing points remain unknown, distinct from a verified zero.
Unrecognized markup and challenge pages fail instead of becoming empty coverage.

`RecruitingBatch` retains exact source captures, timestamps, coverage, errors and a
source fingerprint. `RecruitingEntry` stores normalized values separately from
editable team mapping/exclusion decisions. JSON and base64 are internal encodings
for retained evidence; operators do not prepare or manage files.

## Matching and review

Recruiting and coaching share `Team.matching_school_or_alias(name)`. Canonical school
names and aliases from every source are combined, ignoring case and surrounding
whitespace. Only one distinct team resolves automatically. Conflicting identities
remain for review; no fuzzy matching or automatic team creation occurs.

Matching runs when a batch is fetched. Existing batches retain saved mappings and
exclusions. Fetch a new batch to apply new aliases or improved matching. The admin
review table allows manual mappings or explicit exclusion, with 50 rows per page.
Save changes before switching pages. Approval validates the entire batch.

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
