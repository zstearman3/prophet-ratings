# Durable departure validation

Ticket: https://app.notion.com/p/40417d6b0c24818097c9ebb63dca2315
PR: https://github.com/zstearman3/prophet-ratings/pull/257

Implementation started independently from development
`3e8163134c6861241f0430ae77198bbe00d36fa2` and incorporated development
`508a42135f81bef617a9456c64f995e529a7074f`.
The old checkpoint `e9ec894` was reference material, not the implementation base.

## Design and behavior

Three additive validation/proposal/approval tables and scalar-ID jobs retain
validated annual facts, exact per-team inputs, review choices and approval.
Review/status requests read compact persisted projections. They do not replay
sources, parse annual JSON or enqueue work. Acquisition completion queues
validation; an authenticated admin explicitly approves the exact saved proposal
before publication is queued. Approval records the actor, timestamp and exact
choices with a standard message.

Preparation uses a coherent snapshot and compares its exact report/choices/
proposal proof and actual retained content under locks before signing. Publication
checks the signature, raw retained bytes, consumed annual facts and current
mapping/roster/decision/version/profile identity under the existing ratings lock,
season transaction and fixed-order table locks. Revision, profile pointers, batch
state and signed publication receipt commit atomically. Duplicate publication
returns its original result, including after a later correction.

`schema.rb` and the original revision payload/formulas remain in use. No
PostgreSQL triggers, global dependency-generation table, schema-format conversion,
new managed service, ratings backfill or season activation was introduced.

Fresh authenticated worker rows remain separate from reusable normalizer caches.
Pending HTML successors retain the full legacy dataset through SQL. Pending
provider coverage successors retain the normal canonical cache reference, built
outside the long snapshot; actual retained identity is rechecked before sealing.
Existing offline replay/file APIs keep their original provenance checks.

## Recovery and history

Interrupted unsealed preparation can recover under its operation advisory lock;
a live duplicate cannot claim the same work. Stale, corrupt or superseded evidence
requires explicit revalidation. Unexpected publication errors expose a failed
state and preserve the same signed approval for retry; stale and already-published
states are not overwritten.

Unsigned historical publications remain readable and downloadable offline. To
establish current signed inputs, the one-click correction action copies retained
evidence, preserves lineage and supplies its standard reason automatically.
Fresh validation and explicit approval are still required. Failed manual choices
remain editable from captured facts; editing never certifies them.

## Verification record

Focused implementation checks on the integrated base covered 28 core cases
(seed17424) and 57 browser/acquisition/progress cases (seed12696), all passing.
They include true SQL sealing/mapping races, duplicate/interrupted workers,
tampering with preserved timestamps or recomputed supplied hashes, exact actor
approval, rollback, all-pick/missing-versus-zero behavior, provider coverage offline
compatibility, source-free requests, recovery, corrections and legacy APIs.

Before publishing executable changes, run both required suites with new files
covered:

```sh
bundle exec overcommit --run
bundle exec overcommit --run pre_push
```

The PR and ticket carry final hook, independent review and QA outcomes; targeted
results here do not replace those gates.

## Early worker measurements and limits

See [portable evidence](evidence/departure-validation-workers.json).

| Whole worker peak | 1x | 2x | Growth |
| --- | ---: | ---: | ---: |
| Validation | 265.02 MiB | 277.13 MiB | 12.12 MiB |
| Publication | 232.34 MiB | 241.10 MiB | 8.76 MiB |

Both early worker runs completed actual first publication with 365 profile
pointers and exact original full-payload/canonical-hash oracles. The complete
ticket01 fixture was preserved: 365 teams, 60 picks and doubled unrelated
evidence/history at 2x. Normal query caching and 512 MiB application caps remained.

The initial validation failed at 480.14 MiB. Diagnostics traced this to capture
and normalization objects enrolled across nested savepoints. Validation-only
non-enrolling writes repaired the retention without changing ordinary writers,
forcing GC or shrinking the workload.

These are early worker observations, not final integrated performance proof.
Source edits during the bind-mounted 2x run are disclosed in the portable JSON.
Final browser cold/warm/concurrency, queue latency and memory-drift windows were
not measured. The maintainer explicitly made performance compliance nonblocking
for this PR and requested no further expensive benchmark cycle before publication.
AC5 remains unverified for the final integrated source.

## Operational requirements

Apply additive migration `20261027020000` before using this release's departure
screens. Deploy web and GoodJob workers with the same stable Rails application
secret: signed proposals and receipts depend on it. Secret changes invalidate
existing signatures; retain historical data and revalidate/correct as needed.

The existing heavy worker must be running for validation and publication.
Web-only startup leaves work queued. No live provider import, production
migration, merge, deployment or activation is performed by the implementation
checks. Follow the repository's existing release process.
