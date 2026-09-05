# Local development

The app runs in Docker. Git hooks and static analysis use native Ruby; native specs
use a disposable Docker PostgreSQL database. You do not need host Node, PostgreSQL,
Python or Foreman for the normal workflow.

## The weekly workflow

Start Docker Desktop, then:

```bash
bin/dev
```

Open http://localhost:3000. Rails reloads Ruby changes, and JavaScript and Tailwind
watchers rebuild assets. GoodJob runs in a separate worker with two job threads.
Press **Ctrl-C** when finished: the project's containers and network are removed,
while the development database, Node dependency cache and images are kept.

In another terminal, or from an agent:

| Command | Purpose |
| --- | --- |
| `bin/test` | Full Docker specs, fresh database, automatic cleanup |
| `bin/test spec/models/team_spec.rb` | A specific spec file; other RSpec arguments work too |
| `bin/test --local` | Native Ruby specs with the same disposable database lifecycle |
| `bin/check` | Native RuboCop, Reek, Brakeman, then native specs |
| `bin/dev --detach` | Explicitly keep development running in the background |
| `bin/stop` | Stop a detached session; preserve data and images |
| `bin/compose logs -f web worker` | Follow application/job logs |
| `bin/compose ps` | Check this project's containers |
| `bin/compose exec web bin/rails console` | Rails console in the running app |
| `bin/compose exec web bin/rails db:migrate` | Apply a migration and update the tracked schema |
| `bin/compose exec web bash` | Shell in the app container |

Tests do not require `bin/dev` to be running. On this 8 GB laptop, prefer one test
run at a time and stop development while running a large batch of checks.

The Makefile remains as a compatibility layer: `make up` means
`bin/dev --detach`, `make down` means `bin/stop`, and `make test` means
`bin/test`. Use `make help` for the remaining aliases.

## First-time setup

Install Docker Desktop with Compose **2.24.4 or newer**, Xcode Command Line Tools,
Homebrew, and rbenv. The Compose minimum supports the explicit local port overrides.
Start Docker Desktop and use the versions in `.ruby-version` and `Gemfile.lock`:

```bash
rbenv install -s 4.0.5
gem install bundler -v 4.0.10
brew install libpq pkg-config
bundle config set --local build.pg --with-pg-config="$(brew --prefix libpq)/bin/pg_config"
bin/setup
bin/dev
```

`bin/setup` installs the native bundle without the optional `charts` group,
installs Git hooks, accepts this checkout's hook configuration, and builds the
shared development/test image. Read unfamiliar checkout scripts before running
setup. It does not clear logs, import data, or reset a database.

No `.env.docker` is required for basic startup. Compose supplies local-only
development database defaults. If an integration needs a key, put it in the
gitignored `.env.docker`; never commit it. Do not put production database
credentials there. Rails runs in development, GoodJob cron is disabled, and the
web process enqueues jobs for the separate worker instead of running another
background scheduler itself.

Startup creates and migrates the development database without running seeds.
Importing games or backfilling ratings is a separate, explicit operation.
A fresh database has no basketball data; startup success does not imply the
analytics pages have enough data to show results.

## How the Docker setup works

`bin/compose` always selects `docker-compose.yml` plus `compose.dev.yml`, from
the repository root. Use it for local commands instead of plain `docker compose`,
which selects the production-style configuration and can recreate services with
the wrong image or settings. The production Dockerfile and deployment workflow
are separate and unchanged.

All local application services share `Dockerfile.dev` and one
`prophet-ratings-dev` image. It contains development/test gems, Node, PostgreSQL
client tools, and Python with NumPy. It does not compile production assets during
the image build.

`bin/dev` and Docker `bin/test` do a cached build before starting, so a changed
Gemfile.lock or Dockerfile.dev is picked up automatically. Ordinary Ruby changes
are bind-mounted and need no rebuild. Development startup installs from
`yarn.lock` into a named Docker volume, keeping Linux packages separate from host
`node_modules`. Restart development after changing package dependencies.

PostgreSQL must pass its health check before database setup or tests start.
`bin/dev` prepares the schema and builds assets before starting the server and worker.
Detached startup waits for the Rails health endpoint. Startup schema dumps go
to a container temporary file to avoid incidental schema-format churn; when
authoring migrations, run the explicit migration command in the table above and
commit the resulting `db/schema.rb` change.

Local ports bind only to loopback:

- App: `localhost:3000`; override with `DEV_PORT`.
- Development PostgreSQL: `localhost:54320`; override with `DEV_DB_PORT`.
- Test PostgreSQL: a dynamically assigned localhost port for each run.

Port 54320 avoids the Homebrew PostgreSQL instance that may already own 5432.
For a host database client, use:

```bash
psql postgresql://postgres:password@localhost:54320/prophet_ratings_development
```

Existing data stays in the existing `prophet-ratings_pgdata` named volume.
Keep the same Compose project name to keep using that data. Set
`COMPOSE_PROJECT_NAME`, `DEV_PORT` and `DEV_DB_PORT` consistently if you
intentionally run a separate development checkout.

## Reliable tests and hooks

Every `bin/test` invocation creates a uniquely named Compose project with a fresh
PostgreSQL database. It loads the checked-in schema, runs specs, and removes its
containers, network and test volumes on success, failure, Ctrl-C or termination.
It starts no app server, watchers or job worker. Concurrent invocations have
separate databases and ports, although running many in parallel is a poor fit for
this laptop's RAM.

Both modes use the same PostgreSQL image and schema. `--local` runs Ruby on the
host; the default runs Ruby in the development image. Both force test mode and
supply their own `TEST_DATABASE_URL`, ignoring inherited database URLs. They set
`CI=true` for eager loading and to prevent focused examples from silently
narrowing a full run. Shared source files, Rails logs and RSpec status files are
still shared between simultaneous runs.

Tests load the schema instead of running `db:prepare`: on an empty database,
`db:prepare` invokes application seeds, which import domain data and currently
fail in `Importer::Setup::BaseDataImporter#import_teams`. That ingestion issue is
separate from test/environment setup. Tests must use factories, not that seed path.

The normal hooks are:

- **Pre-commit:** RuboCop, JSON/YAML syntax, trailing whitespace and merge conflicts.
- **Pre-push:** Reek, Brakeman and `bin/test --local`.

Docker Desktop must be available for pre-push PostgreSQL, but no persistent
database service or app container needs to be running. Static checks and Ruby
specs still run natively. Verify hook execution without committing or pushing:

```bash
bundle exec overcommit --run
bundle exec overcommit --run pre_push
```

The all-files pre-commit run covers tracked files; lint newly added files directly
or stage them before relying on that run. Signature verification is disabled in
this project's configuration. `bin/setup` signs once to record that setting in
local Git configuration; quality checks remain enabled.

Reek has an explicit baseline of 709 existing findings in `.reek.yml`. Its
exclusions match exact existing class/method contexts. New contexts and other
smell types fail, but the same excluded smell can recur within an existing
context. Remove exclusions as code is cleaned up; do not regenerate the baseline
just to pass checks. Specs and generated/configuration files are outside Reek's
application-code scan.

The suite reports 15 pre-existing pending examples (mostly generated placeholders
plus unsupported double-header ingestion). Rails Admin's bundled SCSS emits Sass
deprecation warnings, with a regression spec covering stylesheet compilation.

## Dependencies and optional tools

After editing `Gemfile`:

```bash
bundle install
bin/test
```

Commit Gemfile and Gemfile.lock together. The cached Docker build uses the lockfile
in frozen mode and fails if they disagree. Do not install gems interactively into
a running app container: those changes disappear at teardown.

After editing `package.json`:

```bash
bin/compose run --rm --no-deps js yarn install
```

Commit package.json and yarn.lock together, then restart `bin/dev`. Dependency
installation uses `--frozen-lockfile` during routine startup.

The optional `charts` group contains Gruff/RMagick for diagnostic PNG exports.
It requires ImageMagick and a working C++ compiler and is excluded from native
hook setup and the development image. Rails boot, numeric evaluation and current
specs work without it. Chart export setup is an explicit dependency change, not
a requirement for normal development.

Sass uses `sassc-embedded`, preserving Sprockets' API without compiling retired
LibSass. An old native `build.sassc` override can be removed with
`bundle config unset --local build.sassc`.

Python/NumPy are present in Docker. Current specs stub the numerical solver, so
a passing suite alone does not verify a full ratings calculation.

## Memory, disk space and cleanup

**Running containers and Docker's VM use RAM. Images and build cache use disk.**
Deleting images after each session makes the next build slower and is not the
normal remedy for memory pressure.

For this 8 GB laptop, start with Docker Desktop capped at about **4 GB RAM and
2 CPUs**, and keep Resource Saver enabled. This is a starting point, not a
performance guarantee; adjust after measuring your workload. Local containers
also have explicit memory ceilings and rotated Docker logs. A ceiling can stop
a particularly large ratings job, so check for OOM kills before increasing limits
in `compose.dev.yml`.

Useful read-only diagnostics:

```bash
docker stats --no-stream
docker system df
bin/compose ps -a
```

Use `bin/stop` after detached development. Resource Saver can stop the idle Docker
VM once **all** containers are stopped, including containers from other projects.
A crashed terminal or laptop shutdown can prevent script traps from running.
Use `bin/stop` for development; inspect `docker compose ls --all` for leftover
`prophet-ratings-test-...` projects. Only after confirming a particular test run
is no longer active, remove that exact test project with:

```bash
docker compose -p <exact-test-project-name> -f compose.test.yml down --volumes
```

For occasional **disk** cleanup, inspect `docker system df` first. Docker Desktop
can remove selected unused images. `docker builder prune` removes unused build
cache and asks for confirmation; it affects the selected builder across projects,
and subsequent builds will take longer. No routine script runs a global prune,
removes application images, or deletes the development database.

Avoid `docker system prune --volumes` as routine cleanup. If you intentionally
want a completely empty development database, back up anything needed, stop the
stack, and then explicitly run `bin/compose down --volumes`. That deletes this
project's database and Node dependency volume. It is irreversible without a backup.
`make reset-db` no longer performs this deletion automatically.

Docker references: [startup readiness](https://docs.docker.com/compose/how-tos/startup-order/),
[Compose teardown](https://docs.docker.com/reference/cli/docker/compose/down/),
[Resource Saver](https://docs.docker.com/desktop/use-desktop/resource-saver/), and
[rotating local logs](https://docs.docker.com/engine/logging/drivers/local/).

## Data import and production copies

Do not import data or backfill ratings as part of routine startup or testing.
For season/bootstrap operations, see [Offseason Operations](offseason.md) and
[Data Ingestion](data-ingestion.md). `make setup-data` explicitly invokes the
existing imports/backfill; it can be slow and depends on the ingestion code being
healthy. It is not a fix for a failing test environment.

The existing `bin/pull-production-db` is an explicit, destructive development
database replacement, separate from setup:

```bash
bin/dev --detach
bin/pull-production-db --help
```

It defaults to an ECS-based dump and requires AWS credentials/ECS Exec access.
The script prompts before replacing local data. Production users and GoodJob
runtime rows are excluded by default. Put optional `LOCAL_ADMIN_EMAIL` and
`LOCAL_ADMIN_PASSWORD` in the gitignored `.env`; the script can create a local
admin after restore. Read its help for source overrides and `--include-users`.
It uses `bin/compose` for local operations so it selects the same development
image/settings. Run `bin/stop` when finished. Production access is not part of
environment verification or the test suite.
