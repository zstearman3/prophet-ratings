# Offline offseason performance benchmarks

`bin/benchmark-offseason` measures the existing application rather than changing
its formulas or production infrastructure. Docker Desktop, the checked-in Ruby
version and enough free VM memory for fixture construction are prerequisites.
No application seeds, provider credentials, production data or development
services are used.

```bash
bin/benchmark-offseason --scale 1 --output tmp/performance-1x.json
bin/benchmark-offseason --scale 2 --output tmp/performance-2x.json
bin/benchmark-offseason --scale 1 --scenario departures --assert --output tmp/departures.json
bin/benchmark-offseason --scale 1 --scenario mixed --assert --output tmp/mixed.json
bin/benchmark-offseason --help
```

Run full checks sequentially. A scenario selection still constructs the complete
fixture. Setup builds dependencies/assets and loads the schema into a new owned
database; it is excluded from request/job timing. Package downloads occur during
image preparation. The application network is internal and contains only this
run's services. CBBD requests have a nonsecret synthetic token and an exact
endpoint/query allowlist; unexpected requests raise. Provider credentials and
`.env` files are not inherited. A fixture guard requires the exact synthetic
database/host and a matching owned scratch marker.

Every invocation uses random `offseason-...` image tags, Compose project, network,
volumes and output directory. No shared development image is rebuilt. Cleanup
removes only that exact project, its disposable volumes and image tags, including
on error/INT/TERM. Failed teardown/image commands are retained in the command log,
reported in the JSON and make the run nonzero. A hard process/machine kill can
leave resources. From this checkout, derive the exact owned values from the
result file and remove only those resources:

```bash
benchmark_result=tmp/performance-1x.json
benchmark_owner="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0))).fetch("owner")' "$benchmark_result")"
benchmark_output="$(ruby -e 'print File.expand_path(File.join(File.dirname(ARGV.fetch(0)), ARGV.fetch(1)))' "$benchmark_result" "$benchmark_owner")"
BENCHMARK_OWNER="$benchmark_owner" BENCHMARK_OUTPUT="$benchmark_output" BENCHMARK_IMAGE="$benchmark_owner:local" \
  docker compose -p "$benchmark_owner" -f compose.performance.yml down --volumes --remove-orphans
docker image rm "$benchmark_owner:local" "$benchmark_owner-base:local"
```

Do not use a global prune. Machine-readable results, telemetry and command logs
remain in the run's output subdirectory. Synthetic admin session cookies are
local test data in that directory.

## Fixture

The fixed 365-team roster has 15 school-player rows per team, 60 reviewed draft
picks, one athlete with two school stints, reviewed recruiting evidence and 20
confirmed coaching changes. Each school has 22 dated final-stat capture
observations at 1×, 44 at 2×. These are repeated retained archival observations,
not additional distinct athletes, teams or stronger ratings. Each capture has
an actual nested roster table, content-addressed bytes, totals and provenance;
there are no padding fields. The generator replays the real legacy HTML parser,
DecisionForm and Preview, then creates the approved revision through normal
model/hash validations. Setup avoids the input-import orchestrator's repeated
full materializations. Measured review/readiness paths retain their real replay.

There are 60,225/120,450 prior-season historical snapshots and 10,000/20,000
normalized CBBD game observations, spread across dates and teams. The fixed target
season is inactive and contains no completed games or snapshots outside its
publication date. Legacy prior inputs live on the target team/model so actual
preview and publication read/reuse them. They combine real calculator inputs and
formula outputs with team-local nested retained source observations. Historical
snapshots remain on the prior season. No synthetic ratings are substituted for
formula output. Setup freezes timestamps to 2025-06-30. Fixture contents are deterministic; manifest
cardinalities, JSON bytes, dataset/legacy-prior digests and PostgreSQL storage
bytes are saved. CBBD evidence/artifact digests and exact stored replay/report
JSONB text bytes are also recorded without loading them into Ruby just to count.
Envelope targets at 1× are approximately 28.2 MB raw evidence, 30.4 MB normalized
dataset, 60.3 MB revision and 65.2 MB across legacy prior inputs (decimal MB;
approximation tolerance ±20%). Actual values must be inspected in `fixture.bytes`.

The manifest records the authored production bundle and canonical configuration
hash. The default `v1.12-probability-precision` executes the legacy preseason
formula and reuses retained legacy captures. It does not enable optional coaching
or `reviewed_efficiency_r3` formula adjustments. Recruiting/departure/coaching
evidence and review paths are populated; these runs do not establish performance
of the disabled optional formula paths. No modeling defaults are changed.

The legacy-prior content digest streams rows ordered by team-season ID, one at a
time: canonical SHA256 of `[team_season_id, inputs, outputs]`, folded as lowercase
hex plus newline into SHA256 initialized with `offseason-legacy-priors-v1\n`.
Setup explicitly collects garbage between heavy construction phases and records
phase timing/current/peak memory. Those collections occur only in the separate
fixture process, never in measured web/worker windows.

CBBD setup uses fresh processes for base evidence/history, normalized replay,
comparison construction, normal verification and final manifest. Comparison setup
uses the real comparison algorithm with the existing streaming canonical digest
for byte-identical fingerprints. Only a new synthetic comparison is staged, in
one transaction: separately write replay/report, verify canonical content after
the JSONB round trip, then assign the active pointer last. Existing comparisons
are rejected. A fresh process fully reloads the artifact and runs the unchanged
application `verify_artifact` before measurements. Measured review/comparison
operations retain their original application implementation and may exceed caps.

## Measurement protocol

Web and external GoodJob worker each receive **0.5 CPU, 512 MiB memory, no extra
swap**. PostgreSQL is fixed at **0.5 CPU, 3 GiB, shared_buffers=64MB,
work_mem=4MB, max_connections=30** at both scales. PostgreSQL is a separately
reported cost, not free work. Driver/fixture construction has 1 CPU/3 GiB and
runs outside application caps. No development server or asset watcher runs.

Three clients authenticate using real Devise forms, CSRF and session cookies
before measurement. At each route/phase boundary, fresh web/worker containers
start with the same synthetic secret/database. TCP-only readiness makes no HTTP
request. The route's first GET is the first application HTTP request after this
boot; authentication and boot are reported separately and excluded from its
3-second budget. There are no restarts or forced garbage collections within a
warmup/measured sequence.

Every GET has 10 warmups and 30 serial measured requests, plus a separate fresh
boot with 10 warmups and 30 requests across three independent clients. Status and
queue routes use 10 warmups and 30 measured serial requests. p95 is nearest rank
(the 29th sorted value for 30 requests). Limits are:

- Web/worker container peak ≤400 MiB, including Python children.
- First GET ≤3 seconds excluding boot.
- Warmed GET p95 ≤1 second serial, ≤2 seconds at concurrency 3.
- Status/queue request p95 ≤1 second.
- Absolute difference between first-ten and last-ten measured current-memory
  medians ≤20 MiB, for both web and worker.

SQL query caching remains enabled; cache hits are counted separately from SQL
count/time. Server-Timing is disabled and normal large-bind filters remain.
Request telemetry records monotonic elapsed time, response bytes, SQL count/time,
GC count/time deltas, cgroup current/peak and process RSS. GC deltas are process-wide
and overlap during concurrent requests: never sum them as exclusive request GC.
The worker memory JSON is published by temp-file rename. A two-container macOS
bind-mount stress check observed transient ENOENT reads despite an existing target
and no deletions. Only that memory-file read retries ENOENT: five total attempts,
four 50 ms sleeps (at most 200 ms configured delay). Each successful raw
`worker_current` records `sampler_read_retries` (0–4) alongside the actual memory.
Persistent absence, malformed JSON and other filesystem failures still fail the
scenario. The delay can affect post-response request pacing; recorded HTTP elapsed
time is unchanged and requests are never reissued. It is not a strict wall-clock
cap on operating-system scheduling or file I/O.

The worker samples its own current cgroup/RSS every 100 ms for stability; the host
also samples each container's counters and CPU usage. Cgroup v2 peak is preferred
and covers the whole container since boot, including publication setup between
HTTP samples and child processes. Missing peak counters are explicitly labeled
sampled-only; missing measurements cannot establish a pass. Host memory, CPUs,
Docker/Compose/Ruby/Bundler/Rails/GoodJob/PostgreSQL/Python/NumPy versions,
contention, dependency and source file hashes are recorded. Each window retains
actual Docker HostConfig memory/swap/CPU limits. Fixture runtime records effective
eager loading and Server-Timing settings; request SQL telemetry observes query
cache state inside the executor, without changing it.

## Scenarios and terminal checks

| Scenario | Existing application path/work |
| --- | --- |
| dashboard | GET `/admin/offseason_setup?season_id=S` |
| readiness | GET `/admin/offseason_readiness_reviews?season_id=S` |
| departures | GET `/admin/departure_batches/D`, actual 60-pick retained legacy review |
| preseason | GET `/admin/preseason_publications/P?season_id=S`, completed real preview |
| status | GET `/admin/preseason_publications/P/progress?season_id=S`, status/timestamp JSON |
| preview | POST `/admin/preseason_publications?season_id=S`, real PreviewPreseasonJob and 365-team review |
| publish | POST `/admin/preseason_publications/P/publish?season_id=S`, fresh reviewed fingerprint and acknowledgement each sample; real PublishPreseasonJob and 365 captured priors/snapshots |
| cbbd | GET `/admin/cbbd_review_runs/C`, full retained comparison |
| compare | POST `/admin/cbbd_review_runs/C/compare`, waits for the matching pinned CompareCbbdReviewJob and new active immutable artifact; POST timing excludes worker calculation |
| schedule | POST `/admin/schedule_refresh_runs?season_id=S`, bounded historical CBBD RefreshScheduleJob, successful terminal state, stable synthetic game identity and a new audit observation per acquisition |
| mixed | authenticated status JSON during two serial heavy real-solver deliveries and one overlapping ordinary delivery; complete 10 warmups + 30 measured samples |
| solver | benchmark-only queued external job, real StatisticsUtils/Python boundary with 1,460×730 repeated identity matrix, alternating known coefficients 2/−3, ridge zero, maximum error ≤1e−8 |

Every phase has an owner/phase ActiveJob prefix and an exact matching GoodJob
selectors for only that phase’s heavy/default queues, one thread each in a single
worker process with zero subprocesses. Prior interrupted jobs and audit rows remain retained but cannot
execute in later phases.

Queue samples record actual job IDs, worker telemetry and terminal state. Job
output size means terminal publication report+result JSONB text bytes, schedule
report JSONB text bytes, or exact solver result-file bytes. SQL `octet_length`
returns scalars without loading full outputs into Ruby. Its cost is included in
job elapsed/SQL counters and worker/database memory measurements. Missing output
byte telemetry fails closed. Fresh
publish review preparation occurs outside HTTP timing but inside worker memory
headroom. Already-published shortcuts do not qualify. Schedule imports run after
publication and use the prior season, preserving repeat initialization semantics.
Only benchmark bootstrap loads the test solver job/instrumentation; normal app
boot has no benchmark hooks.

### Mixed worker coexistence

`--scenario mixed` constructs the unchanged full 365-team scale-one fixture. Two
distinct `MixedHeavyJob` deliveries receive the same operation token, fixture
season ID and published model ID. Each uses the existing real 1,460×730 solver
probe (alternating coefficients 2/−3, ridge zero) and retains its matrix/input
state after solving. Readiness is signaled only after the solve. The driver then
enqueues an ordinary job, makes 10 warmup + 30 measured authenticated status GETs
paced by 300 ms, and releases held work after the window. Each heavy delivery
holds operands at least 10 seconds with a bounded driver/readiness timeout. No
forced GC, fixture reduction, query-cache change or cap increase is used.

The result records actual retained GoodJob execution start/end timestamps,
process IDs, job IDs and serialized pinned arguments. It rejects overlapping
heavy intervals, ordinary start more than 10 seconds after enqueue, ordinary work
outside the first heavy interval, HTTP samples outside that interval, mismatched
operation/process identity, missing execution evidence and failed jobs. Real
solver coefficients are checked independently against the known solution. Normal
status latency, SQL/GC/RSS/current-memory, 30-sample stability and child-inclusive
web/worker peak checks all still apply. Worker pool/DB size/PID and thread settings
are recorded with solver results. A missing or failed stability window is not a
pass; solving/retention transitions can affect it and require honest reporting.

This measures sharing one Rails heap with two execution threads. A second heavy
process would add another Rails heap and database pool, while the shared advisory
lock still serializes its heavy body. Prefer the measured single-process topology
only when this assertion passes. This synthetic solver coexistence result does
not certify every heavy algorithm: the previously recorded preview/comparison
memory failures below remain separate work.

## Results and regression gate

Results JSON contains raw samples, warmups, first GET, telemetry, fixture manifest,
container windows/CPU/RSS/current/peak, terminal outputs, coverage and explicit
failures. Every GET phase requires a valid first response with nonempty telemetry
and finite, nonnegative elapsed time and current memory. Missing or invalid cold
evidence is a harness error; a complete cold response above 3 seconds is a budget
breach. Status and queue phases do not require a cold sample. The HTTP client
disables automatic retries before dispatch, so broken connections propagate
without silently repeating a measured request. Baseline mode permits measured latency/memory budget breaches to exit
zero; `--assert` exits 1 for breaches. Harness errors, missing results, failed jobs,
HTTP mismatches, timeouts, incomplete coverage and OOM exit 2, including in
baseline mode. A false `pass` remains machine-readable in either mode. A baseline
failure is evidence to preserve, not an instruction to raise application caps or
change the model. Subsequent performance tickets must pass their relevant routes.

Initial fixture setup probes failed before measuring application traffic: a
384 MiB PostgreSQL cap closed the connection during the large JSON insert, and
the complete input-import orchestrator exited 137 in the 3 GiB setup driver
(possible memory exhaustion; that early removed container has no retained OOM proof). These are setup failures, not web/worker peak measurements.
Direct validated fixture construction got past departure publication and history.
The next 1× attempt still lost its PostgreSQL connection while inserting the full
normalized CBBD replay at 1 GiB. Bounded 100-observation JSONB appends also failed:
PostgreSQL must still materialize the growing annual value. Real-normalizer
experiments measured 6,876 bytes per final row versus 7,994 per scheduled/no-box
row, so a scheduled mix would not reduce this setup cost. The reviewed final
configuration uses a fixed 3 GiB local PostgreSQL cap at both scales, preserves
all-final observations and restores normal model persistence for annual CBBD
artifacts. Ten actual prior-season local finals provide representative statistical
shadow comparisons. Schedule imports use dedicated source ID 900001 and teams
21/22, outside the retained comparison IDs and ten seeded participant pairs. The
first import creates a genuine final; repeats retain that game identity and scores,
while every acquisition retains a new source observation (40 schedule jobs produce
40 observations at either scale).
This larger local database cap is not certification of production `db.t3.micro`
capacity. Host contention and actual PostgreSQL cost must be considered alongside
application measurements. Qualifying runtime observations are recorded below only
after execution; prior failed setup attempts are not web/worker baselines.

## Recorded evidence

The historical-source full protocols ran on 2026-10-25: 1× baseline owner
`offseason-3e5a87d432acaa05` and 2× assertion owner
`offseason-4fc6964156705a1e`. Both attempted all 16 phases and returned exit 2,
`pass: false`, with no top-level harness errors. Application OOMs/timeouts prevented
complete measurements. These retained failures satisfy the ticket's baseline
recording provision (AC4); they do not establish performance budget compliance.
These runs precede the recovery refactors of application helpers and benchmark SQL.
Their recorded source hashes identify the measured code; they are historical
measurements, not measurements of the final repaired source. The repairs preserve
model formulas, RNG ordering and persisted artifact content. Focused SQL equivalence
and affected application regression checks validate those contracts; final-source
runtime evidence must be identified separately and must not inherit these hashes.

All earlier setup probes, pre-review baselines and bounded feasibility runs are
superseded by these recorded baseline runs.

| Scenario | Historical 1× | Historical 2× |
| --- | --- | --- |
| Dashboard/readiness GET | Web OOM in both phases; no complete windows | Four 180s read timeouts; containers remained running, no OOM; web peaks exceeded 400 MiB |
| Departures GET | Web OOM in both phases | Web OOM in both phases |
| Preseason GET | Serial/concurrent p95 0.391/0.947s; memory drift 30.03/28.60 MiB fails | Serial/concurrent p95 0.367/1.097s; memory drift 26.03/28.83 MiB fails |
| Status | p95 0.0228s; no phase failures | p95 0.0191s; no phase failures |
| Preview | 10 warmups + 17 measured requests, then worker OOM; no qualifying p95 | 2 warmups + 0 measured requests, then worker OOM; no qualifying p95 |
| Publish | Fresh preview completed; first POST returned 302, then worker OOM while waiting for publish job | Fresh preview completed; first POST returned 302, then worker OOM while waiting for publish job |
| CBBD GET | Web OOM in both phases | Web OOM in both phases |
| Comparison POST | Web OOM | Web OOM |
| Schedule | p95 0.0319s; no phase failures | p95 0.0184s; no phase failures |
| Real solver | Maximum coefficient error 0; worker peak 254,980,096 bytes | Maximum coefficient error 0; worker peak 237,498,368 bytes |

Preseason, status and schedule p95 values use complete 10-warmup/30-measured
windows; preseason has separate serial/concurrency-3 windows. Its latency limits
pass, but memory drift exceeds 20 MiB at both scales. Each schedule phase completed
40 acquisitions, retaining 40 source observations of one stable game identity.
The first import creates the final game; unchanged repeat observations are
retained with `accepted: false`. Both real solver runs
verified all 730 finite coefficients of the 1,460×730 system and recorded exactly
100 output bytes. In each publish phase, a fresh prerequisite
`PreviewPreseasonJob` completed, then the first publish POST returned 302
(request IDs `98f3e8836447777b155189e0` / `021a39848b392c9d8c826e77`).
The driver verified the queued job class as `PublishPreseasonJob` before waiting;
job IDs `9b8091d8-f1ed-448d-9644-38af0aebdf33` /
`18ddf414-271e-4049-b8fa-654fc1b289fa` then timed out with worker OOM.
There is no completed publication terminal result or publish-job terminal
telemetry. Zero retained warmups/samples reflect collection appending only after
job completion; they do not mean the publish POST was unreached.

OOM-terminated cgroup samples are retained pre-death readings, not final peak
measurements. In particular, 1× CBBD readings of 379,969,536/378,961,920 bytes do
not demonstrate a peak below 400 MiB: Docker recorded `OOMKilled: true`.
The 2× dashboard/readiness failures were timeouts, with no Docker OOM; QA observed
the fixed 0.5-CPU database saturated during those requests. Shared-host contention
remains uncontrolled. PostgreSQL cost, including setup, is reported separately:

| PostgreSQL counter | 1× | 2× |
| --- | ---: | ---: |
| Peak bytes | 1,610,629,120 | 2,781,818,880 |
| Final current bytes | 339,042,304 | 258,195,456 |
| CPU microseconds | 91,629,841 | 432,068,481 |
| `oom_kill` | 0 | 0 |

Both scales completed all five fixture setup stages, including the unchanged
fresh-process artifact verifier, with exit 0 and no setup OOM. Exact manifests:

| Synthetic fixture | 1× | 2× |
| --- | ---: | ---: |
| Target teams / distinct school players / draft picks | 365 / 5,474 / 60 | 365 / 5,474 / 60 |
| School captures / player observations | 8,030 / 120,450 | 16,060 / 240,900 |
| Historical snapshots / normalized CBBD finals | 60,225 / 10,000 | 120,450 / 20,000 |
| Raw evidence JSON bytes | 25,048,256 | 50,090,614 |
| Normalized dataset JSON bytes | 29,672,259 | 59,331,097 |
| Published revision JSON bytes | 54,953,629 | 109,654,825 |
| Legacy prior input JSON bytes | 58,595,991 | 114,806,827 |
| CBBD normalized replay JSONB text bytes | 75,469,811 | 150,983,885 |
| CBBD report JSONB text bytes | 77,315,707 | 154,610,147 |
| CBBD comparison replay JSONB text bytes | 75,469,811 | 150,983,885 |

Content-envelope bytes differ from PostgreSQL JSONB text and physical storage;
the manifest records each definition separately. Content SHA256 digests:

Dataset:

```text
1x db165b07d5b1163364660c3e68a192925d51b6ef34e1cd2a4e9cfad23e0c4ea3
2x 4c1891622a9fe93b67a0dedae7d8b07b6d975e7bfe62a740875b22515954f08e
```

Legacy priors:

```text
1x 889755c192f6b86740b1ba1e7ca46479dce13818e3df2c336b347e2d69fc1d4a
2x ebad1ae22c06091fcae8f7d5163882840604f3007ee52610b914c6713485943b
```

CBBD evidence:

```text
1x b411f61b612bbea81a05e581b69d4466bbce388621490336c26bce6302caf4e3
2x e348036c4e81f93e861e2bc51315ae4a02720bf50efe58cfa515a40bb54c53f1
```

Comparison artifact:

```text
1x 58a84ad60e50ae3e887c181a1545f1382ae488db024789c9ddfb645555346b60
2x 90567a058e587be86666bf64fae4d1141dc58b6e15054af396d9c5b5155e2358
```

The 2× dataset/legacy digests and content-envelope bytes match the independent
fresh-database feasibility fixture. Both scales use the authored production
bundle `v1.12-probability-precision`, config SHA256
`e68b5a3a82c91fb04ceffd9eac8363b3111c03c45bb6c6e5d7d0b304a06b04b9`.
Optional coaching and reviewed-efficiency formulas are disabled by that bundle;
retained source/legacy inputs remain reachable without claiming those optional
formula paths executed.

Reproduce serially from the repository root:

```bash
bin/benchmark-offseason --scale 1 --output tmp/performance-ticket/final-baseline-1x.json
bin/benchmark-offseason --scale 2 --assert --output tmp/performance-ticket/final-baseline-2x.json
```

The ignored JSON/log outputs and per-owner directories retain exact raw samples,
job/output bytes, SQL/cache/GC telemetry, runtime versions, source hashes, actual
container limits and cleanup evidence. No passing full protocol is claimed.


## Final-source focused recovery evidence

After the telemetry-file repair, four scenarios ran in order on one complete fresh
fixture per scale: preseason (serial and concurrency 3), status, preview, schedule.
These are five phases, not a repeat of the full historical protocol. Both runs
completed all five fixture stages, including fresh-process verification, with no
setup OOM; all canonical fixture counts, content/persisted bytes and dataset,
legacy-prior, CBBD evidence/comparison digests exactly match the historical
manifests above. Physical PostgreSQL storage bytes can differ.

The 2026-10-25 runs were 1× owner `offseason-4bf3bfce05f1fee4` (12:22–12:26 UTC)
and 2× owner `offseason-6a579f7f041af60a` (12:27–12:34 UTC). Both report
`pass: false`, `errors: []`. Baseline 1× exited 0 with complete measurements and
budget breaches; assertion 2× exited 2 with an incomplete OOM phase. Every phase
except 2× preview retained 10 warmups and 30 measured requests.

| Phase | Final-source 1× | Final-source 2× |
| --- | --- | --- |
| Preseason serial | p95 0.3884s; drift 46,641,152 bytes fails | p95 0.3941s; drift 32,464,896 bytes fails |
| Preseason concurrency 3 | p95 1.0221s; drift 39,526,400 bytes fails | p95 1.1145s; drift 17,571,840 bytes passes |
| Status | p95 0.0308s; phase passes | p95 0.0426s; phase passes |
| Preview | POST p95 0.0678s; worker peak 458,739,712 bytes exceeds 400 MiB | 2 warmups, 0 measured; worker exit 137, OOM, awaiting-job timeout; no qualifying p95 |
| Schedule | p95 0.0226s; phase passes | p95 0.0199s; phase passes |

Preseason cold GETs were 0.5397/0.4913s at 1× and 0.4609/0.4851s at 2×
(serial/concurrent); all satisfy the 3s cold limit. All recorded successful worker
memory reads report `sampler_read_retries: 0`. The 2× preview worker's last retained
peak reading, 496,074,752 bytes, precedes OOM and does not establish the true final
peak. PostgreSQL peaks were 1,597,546,496 / 2,786,045,952 bytes, with CPU usage
28,937,695 / 47,719,202 microseconds and no database OOM. These costs include setup.
Shared-host contention remains uncontrolled; these runs support no numerical
improvement claim or passing full-protocol claim.

Raw evidence: `tmp/performance-recovery/final-selected-{1x,2x}.json` and matching
logs. Measured source provenance is base
`1c566cdfa038fb916c1e50f092ee7c8404e3ec10` plus recorded diff SHA256
`bc2de154f4ffae8aa7150789a162af76c45ea0264b94d2df9a5560a5f6ada292`;
both files retain per-file source hashes. This identifies the repaired executable
source before this documentation-only evidence update. The archived selection
wrapper SHA256 is
`d142ca449bd3217dca88ca2d015b44887d6249ad6aee53944b8ebd014d2c0b0e`.
The initial selected run before the sampler fix is retained separately as
`selected-1x-before-sampler-fix.json`; its missing-file interruption is not a
qualifying final-source window.

To reconstruct the focused selection, create this ignored wrapper from the
repository root, then run its two commands serially. Only the scenario list is
overridden; fixture construction, phase order, resource limits, protocol, signal
handling and cleanup use the original runner. Individual `--scenario` invocations
create separate fixtures and are not numerically equivalent to this shared-fixture
sequence.

```bash
mkdir -p tmp/performance-recovery
cat > tmp/performance-recovery/selected_benchmarks.rb <<'RUBY'
# frozen_string_literal: true

Dir.chdir(File.expand_path('../..', __dir__))
require_relative '../../script/performance/runner'

class RecoveryBenchmarkSelection < OffseasonPerformance::Runner
  private

  def scenarios
    %w[preseason status preview schedule]
  end
end

runner = RecoveryBenchmarkSelection.new(ARGV)
%w[INT TERM].each { |signal| Signal.trap(signal) { raise Interrupt, signal } }
runner.call
exit runner.exit_code
RUBY
ruby tmp/performance-recovery/selected_benchmarks.rb --scale 1 --output tmp/performance-recovery/final-selected-1x.json
ruby tmp/performance-recovery/selected_benchmarks.rb --scale 2 --assert --output tmp/performance-recovery/final-selected-2x.json
```

## Bound-worker mixed evidence (2026-10-25)

The initial `--scale 1 --scenario mixed --assert` run passed, owner
`offseason-84093dfb40fe5ea7`, 13:53:03–13:55:31 UTC. Ignored evidence:
`tmp/worker-ticket/mixed.json`, `tmp/worker-ticket/mixed.log` and its per-owner
`commands.log`/telemetry directory. All fixture stages completed without OOM;
365 target teams, 5,474 distinct school players, 8,030 school captures, 120,450
player observations, 60,225 historical snapshots and 10,000 CBBD game observations
match the original scale-one fixture. Content/persisted bytes and canonical
digests are retained in the result; model hash remains
`e68b5a3a82c91fb04ceffd9eac8363b3111c03c45bb6c6e5d7d0b304a06b04b9`.

| Check | Observed |
| --- | --- |
| Status window | 10 warmups + 30 measured, all HTTP 200 with valid JSON |
| Status p95 | 0.057786 seconds |
| Web child-inclusive container peak | 184,401,920 bytes (175.86 MiB) |
| Worker child-inclusive container peak | 262,246,400 bytes (250.10 MiB) |
| Web first/last-ten median drift | 6,746,112 bytes |
| Worker first/last-ten median drift | 567,296 bytes |
| Ordinary enqueue-to-start | 0.011198 seconds, overlapping first heavy execution |
| Gap between heavy executions | 0.027182 seconds, no overlap |
| Real solver | Both 1,460×730 probes, maximum coefficient error 0 |
| Live-state hold | 13.0604 and 10.0493 seconds |
| Worker runtime | PID 1, same durable process ID for all three executions, zero subprocesses, two one-thread phase pools, DB pool 6 |

All measured HTTP timestamps fall within the first persisted heavy interval;
all three jobs completed successfully. Web/worker each retained the 512 MiB cap
and passed the 400 MiB peak budget and the complete stability checks. PostgreSQL
peak was 1,604,374,528 bytes, separately budgeted at 3 GiB/30 connections. The
result records other running local containers as host contention. Only this mixed
scenario was rerun; historical preview/comparison limitations above still apply.
This supports one shared worker process for the measured coexistence workload; it
does not claim every heavy algorithm now fits the worker budget.

### Final runtime after required static-check repair

The final-source rerun also passed, owner `offseason-91c6cf1338847cee`,
2026-10-25 14:18:16–14:20:41 UTC. Evidence is retained in
`tmp/worker-ticket/mixed-final.json`, `tmp/worker-ticket/mixed-final.log` and its
per-owner directory. The fixture counts, content/persisted bytes, dataset,
legacy-prior, CBBD evidence/comparison and model digests exactly match the initial
run. All 1,050 recorded source-file hashes matched the checkout before this
documentation update; no runtime source changed after benchmark launch.

The repair split benchmark orchestration, output counting and interval validation
into local helpers without changing the measured work or limits. The complete
matrix and expected/actual solver vectors remain reachable throughout the live
hold. A deterministic rehearsal matched 439 original/final validator outcomes,
including exact nil-only error acceptance, nonfinite/missing timestamps, the
10-second boundary, process/operation identity and HTTP interval mutations.

| Final check | Observed |
| --- | --- |
| Status window | 10 warmups + 30 measured, all HTTP 200/valid JSON |
| Status p95 | 0.042955 seconds |
| Web container peak | 184,438,784 bytes |
| Worker container peak including children | 260,444,160 bytes |
| Web/worker median drift | 6,301,696 / 204,800 bytes |
| Ordinary enqueue-to-start | 0.016882 seconds, overlaps first heavy execution |
| Gap between heavy executions | 0.019428 seconds, no overlap |
| Real solver | Both 1,460×730 probes, maximum coefficient error 0 |
| Live-state holds | 12.9172 and 10.0930 seconds |
| Worker runtime | Same retained process ID for all three jobs; PID 1, zero subprocesses, two one-thread phase pools, DB pool 6 |

Both application containers passed their unchanged 400 MiB peak budgets at
512 MiB caps; PostgreSQL peak was separately 1,592,422,400 bytes at its 3 GiB cap.
All measured HTTP intervals were inside the first heavy execution, all three jobs
finished successfully, and complete stability checks passed. This final rerun
supersedes the initial run for runtime provenance; the earlier heavy-algorithm
limitations still apply.

## Departure normalization scenario (ticket03)

Run explicitly, sequentially at each scale:

```bash
bin/benchmark-offseason --scale 1 --scenario departure_normalization --assert --output tmp/departure-ticket/normalization-1x.json
bin/benchmark-offseason --scale 2 --scenario departure_normalization --assert --output tmp/departure-ticket/normalization-2x.json
```

The default scenario list is unchanged. Setup preserves the complete original
fixture, including history and CBBD game archives. Two fresh web/external-worker
phases retain the normal production/eager-load, 0.5 CPU/512 MiB cap, cgroup sampler,
SQL/GC telemetry and separate PostgreSQL accounting. Neither phase forces GC or
restarts its worker during measured work. Each queued HeavyJob receives one scalar
record ID; the result records serialized argument values.

`legacy` consumes `Content.each_source` verbatim in the measured worker. It retains
exact bodies and immutable observations, parses each HTML source with the existing
SourceSnapshot adapter, persists normalized records, and streams the complete
logical dataset digest. Both the exact original digest and processed school/player
observation cardinalities must match the original fixture (8,030/120,450 at 1×;
16,060/240,900 at 2×). This offline adapter does not enable HTML network acquisition
or rewrite existing historical attempts. The benchmark clones the persisted
legacy manifest inside PostgreSQL and loads a fresh acquisition, preserving its
exact metadata while avoiding a Ruby JSON roundtrip solely to create the measured
attempt. Raw source tempfiles are removed after each observation is retained;
normalized source batches remain fixed at 250. Scalar legacy worker stage counters
mark cloning, capture completion, annual dataset completion and the final
checkpoint; these diagnostics neither force GC nor change query caching.

`cbbd` separately measures normal acquisition/checkpoints, PostgreSQL cursor source
normalization and annual team combination for five nonempty JSON responses:
365 teams × 15 stints in each scope,60 distinct draft picks, regular/postseason totals,
zero-point participants and one athlete with two team stints. Its scope stays 365 at
both scales and its actual response/record counts and bytes are reported
separately. The driver verifies its digest against the unchanged file replay.
The exact original legacy corpus supplies the growth proof; this representative
annual CBBD path supplies coverage of large single-source JSON and current rules.

Both subpaths require a real performed terminal job and worker peak ≤400 MiB at
both scales. Compare the corresponding 2× minus 1× worker peak: growth must be ≤50 MiB
with row batches fixed at 250. Missing telemetry/OOM never establishes a pass.
A stopped worker whose sampler remains stale for 60 seconds fails explicitly
rather than waiting the full two-hour normalization deadline. Results include
per-subpath body bytes/counts, immutable observation counts,
normalized source rows, actual player observations, annual output bytes and
PostgreSQL database bytes. Existing whole-container peak/current/RSS, elapsed,
SQL/GC, Docker/runtime versions, host contention and database counters remain in
the run artifacts. Synchronous review/publication performance is outside this
scenario; it must not be inferred from normalization results.

### Resumed departure normalization evidence (2026-10-25)

The final source-matched pair is
`tmp/departure-ticket/resume-measured-normalization-{1x,2x}.json`, owners
`offseason-fcfc20afdc68ce9a` / `offseason-d27299acc1f11b95`. All 1,077 source
hashes match between scales. Both full-corpus legacy jobs and separate five-response
CBBD jobs reached performed terminals with normal query caching; original legacy
counts and replay digests matched exactly.

| Worker whole-container peak | 1x bytes | 2x bytes | Growth bytes |
| --- | ---: | ---: | ---: |
| Legacy | 319,356,928 | 433,881,088 | 114,524,160 |
| CBBD | 231,456,768 | 231,694,336 | 237,568 |

Legacy still fails AC2: 2x exceeds 400 MiB and growth exceeds 50 MiB. CBBD passes.
At 2x, the legacy cumulative peak was 404,918,272 bytes at checkpoint completion,
then 433,881,088 after terminal accounting/output; the latter remains the acceptance
measurement. Stage timing identifies an interval, not an individual allocation.
No GC forcing, cache disabling, smaller corpus, batch change or cap increase was
used. PostgreSQL peaks were separately 1,586,356,224/2,770,911,232 bytes with no
OOM in the completed pair. Existing local stacks remained running.

A preceding fixture-only attempt lost its database to OOM; an unchanged retry
produced this completed pair. Another fixture-only run was intentionally interrupted
before the final correctness fix. Neither supplies worker acceptance evidence.
See [the implementation handoff](departure-capture-handoff.md) for exact commands,
source provenance, intermediate attempts, remaining failure and verification gates.
