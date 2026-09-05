# Local Development Guide

The application can run via Docker, while Git hooks run with native Ruby so they
do not depend on a running application container.

## Native Ruby and Git hooks (macOS / Apple Silicon)

Use the Ruby version in `.ruby-version` (currently 4.0.5) and Bundler 4.0.10 from
`Gemfile.lock`. With rbenv and the Xcode Command Line Tools installed:

```bash
rbenv install -s 4.0.5
gem install bundler -v 4.0.10
brew install libpq pkg-config
bundle config set --local build.pg --with-pg-config="$(brew --prefix libpq)/bin/pg_config"
bundle config set --local without charts
bundle install
bundle check
```

The `charts` group is optional: it contains Gruff/RMagick and requires ImageMagick
and a working C++ compiler. Numeric prediction evaluation and Rails eager loading
work without it; only the diagnostic PNG generation methods load Gruff. To use
those methods, install ImageMagick and include the `charts` group in your bundle.

Sass uses `sassc-embedded`, which preserves the SassC API used by Sprockets and
Rails Admin and ships Dart Sass for Apple Silicon and Linux. The previous SassC
2.4.0 installation failed because this local Ruby's `RbConfig::CONFIG['CXX']` was
`false`; its generated LibSass Makefile therefore invoked `false` as the compiler.
The old `build.sassc --with-cxx=c++` setting did not override that value. No SassC
compiler override is needed with the replacement. Existing overrides can be removed:

```bash
bundle config unset --local build.sassc
```

### Test database

RSpec needs PostgreSQL, but Rails and the checks execute on the host. By default,
tests connect to `prophet_ratings_test` through the local PostgreSQL socket as your
OS user. Start your local PostgreSQL service before preparing the test database.
Alternatively, start the Compose database and point native Rails at its published
port:

```bash
docker compose up -d db
export TEST_DATABASE_URL=postgresql://postgres:password@localhost:5432/prophet_ratings_test
```

Use only one PostgreSQL service on port 5432. If a Homebrew instance already owns
that port, use its local socket/default URL instead of the Compose credentials.
`TEST_DATABASE_URL` is separate from `DATABASE_URL` so exported development or
production connection settings cannot redirect specs into those databases. Any
custom test URL must point to a dedicated, disposable test database.

```bash
RAILS_ENV=test bundle exec rails db:prepare
bundle exec rspec
RAILS_ENV=test bundle exec rails zeitwerk:check
```

Running the actual ratings solver locally additionally requires `python3` with
NumPy. For example, create and activate a virtual environment under `tmp/` and
install NumPy there. The current specs stub the numerical solver and do not verify
that Python dependency.

### Install and verify hooks

```bash
bundle exec overcommit --install
# After reviewing .overcommit.yml and .git-hooks/pre_push/reek.rb:
bundle exec overcommit --sign
bundle exec overcommit --sign pre_push
bundle exec overcommit --run
bundle exec overcommit --run pre_push
```

`--run` checks all tracked files without committing. `--run pre_push` executes the
push checks without contacting a remote or pushing. Normal commits check staged
files. Re-sign after reviewing changes to the hook configuration or plugin.

Pre-commit runs RuboCop, JSON/YAML syntax, whitespace, and merge-conflict checks.
Pre-push runs the full RSpec suite, Reek, and Brakeman. All Ruby tools use the
project's locked bundle. You can also run them directly:

```bash
bundle exec rubocop
bundle exec reek
bundle exec brakeman -q -w2 -x EOLRails,EOLRuby
```

Reek was introduced with a baseline of 709 existing findings in `.reek.yml`.
Detectors remain enabled, with exclusions anchored to the exact existing class
or method context; new contexts and other smell types still fail. An excluded
smell type can still recur within the same context, so remove exclusions as the
affected code is cleaned up. Do not regenerate the baseline merely to pass a
hook. Specs and generated/configuration files are excluded from Reek's application
code analysis.

The suite currently includes 15 pre-existing pending examples (mostly generated
placeholders, plus unsupported double-header ingestion). They are reported by
RSpec and are not treated as failures. Rails Admin's bundled Bootstrap SCSS also
emits Dart Sass deprecation warnings; the stylesheet compilation regression spec
verifies it still builds.

## Prerequisites

- **Docker Desktop** 4.x+ (includes docker compose)
- **make** (included by default on macOS)
- Optional: make sure ports 3000 (web) and 5432 (Postgres) are free

## First-time setup

1. Create a `.env.docker` file in the project root. This file is loaded by `docker-compose.yml` for the `web` and `worker` services.

   Recommended contents:

   ```dotenv
   # Run the app in development mode inside the container
   RAILS_ENV=development

   # Database URL for Rails (Active Record will honor this if present)
   DATABASE_URL=postgresql://postgres:password@db:5432/prophet_ratings_development

   # Puma / Rails binding is already set in docker-compose (0.0.0.0:3000)

   # Optional: API keys and other env
   # ODDS_API_KEY=your_api_key_here
   ```

   Notes:
   - The Postgres credentials/host must match the `db` service in `docker-compose.yml`.
   - If you don’t have an odds API key yet, leave it unset; most of the app should still boot.

2. Build the images:

   ```bash
   make build
   ```

   The first build may take several minutes (Ruby, Node, and asset build steps).

   Local source files are mounted into the `web` and `worker` containers by `compose.dev.yml`, which the Makefile loads explicitly. Ordinary code, spec, and RuboCop changes do not require a rebuild. Rebuild after changing dependencies, native packages, or the Dockerfile.

## Using the Makefile

The root `Makefile` provides short commands for common Docker Compose workflows. These commands load both `docker-compose.yml` and `compose.dev.yml`, so local containers see your working tree immediately.

Use plain `docker compose -f docker-compose.yml ...` when you want the production-like image behavior without local development overrides.

List available commands:

```bash
make help
```

Common commands:

- **Build images**: `make build`
- **Start the stack**: `make up`
- **Stop the stack**: `make down`
- **Restart the stack**: `make restart`
- **View all logs**: `make logs`
- **View web logs**: `make logs-web`
- **Open Rails console**: `make console`
- **Open a shell in the web container**: `make shell`
- **Run migrations**: `make migrate`
- **Bootstrap project data**: `make setup-data`
- **Run tests**: `make test`
- **Reset the database volume**: `make reset-db`

## Start the stack

```bash
make up
```

This starts:
- `db` (Postgres 15)
- `web` (Rails server on http://localhost:3000)
- `worker` (GoodJob background jobs)

The `web` container runs `./bin/rails server -b 0.0.0.0`. The entrypoint auto-runs `db:prepare` when starting the server.

View logs:

```bash
make logs-web
make logs-worker
```

## Seed and bootstrap data

There is a helper script to set up baseline data and backfill ratings:

```bash
make setup-data
```

What it does:
- Ensures DB is prepared (migrate/create)
- Imports base models and games/stats
- Runs a ratings backfill

If you only need migrations or a Rails task:

```bash
make migrate
```

For offseason season creation, conference realignment, and bootstrap order, see [Offseason Operations](offseason.md).

To run a one-off Rails task that does not have a Makefile shortcut:

```bash
make shell
bin/rails <task:name>
```

## Common development workflows

- **Rails console**

  ```bash
  make console
  ```

- **Run tests (RSpec)**

  ```bash
  make test
  ```

- **Open an interactive shell in the web container**

  ```bash
  make shell
  ```

- **Install a new Ruby gem**

  1) Update `Gemfile` and run inside the container:
  ```bash
  make bundle-install
  ```
  2) Rebuild if native extensions or image layers require it:
  ```bash
  make build && make up
  ```

- **Install/update JavaScript packages**

  ```bash
  make yarn-install
  ```

## Database access

Connect with a local Postgres client to `localhost:5432` using:

- User: `postgres`
- Password: `password`
- Database (dev): `prophet_ratings_development`

From the host:

```bash
psql postgresql://postgres:password@localhost:5432/prophet_ratings_development
```

From the container:

```bash
docker compose exec web psql "$DATABASE_URL"
```

## Pull production data locally

Use `bin/pull-production-db` to replace the local development database with a dump of production:

```bash
make up
bin/pull-production-db
```

The default source is the running ECS web task. This avoids requiring direct laptop access to private RDS. The ECS task runs `pg_dump` against its production `DATABASE_URL`, streams the dump down, and the script restores it into your local Docker Postgres database.

Prerequisites:

```bash
aws sts get-caller-identity
make up
```

Put the local admin credentials in the gitignored `.env` file:

```dotenv
LOCAL_ADMIN_EMAIL=you@example.com
LOCAL_ADMIN_PASSWORD=change-me-locally
```

Keep local Docker runtime configuration in `.env.docker`:

```dotenv
RAILS_ENV=development
DATABASE_URL=postgresql://postgres:password@db:5432/prophet_ratings_development
```

The script asks for confirmation before replacing the local database and then runs migrations. When the Docker `db` service is running, it restores into the database configured by `.env.docker`'s `DATABASE_URL`, uses the containerized PostgreSQL tools, and temporarily stops/restarts the local `web` and `worker` services around the restore. It does not store production credentials in the repo.

Production user rows are excluded from the dump by default, so user data never lands locally. GoodJob runtime rows are also excluded so production jobs do not run in local development after restore. To include users anyway:

```bash
bin/pull-production-db --include-users
```

After restore, the script creates or updates a local admin user when `LOCAL_ADMIN_EMAIL` and `LOCAL_ADMIN_PASSWORD` are set. This keeps Rails Admin usable locally without importing production users.

The ECS defaults match `bin/prod-console`:

```bash
ECS_CLUSTER=prophet-cluster
ECS_SERVICE=prophet-ratings-web
ECS_CONTAINER=web
AWS_REGION=us-east-1
```

Override any of those only if the deployment changes.

Direct RDS access is still available when needed:

```bash
PRODUCTION_DATABASE_URL="postgresql://..." bin/pull-production-db --source direct
```

## Troubleshooting

- Ensure `.env.docker` exists and has `RAILS_ENV=development` and a valid `DATABASE_URL` pointing at `db`.
- If migrations fail on boot, run `make prepare` and check logs.
- If assets or Node modules change significantly, rebuild: `make build`.
- To reset the database completely:
  ```bash
  make reset-db
  ```
  Warning: `-v` removes the Postgres volume and erases all data.

## Stop and teardown

- Stop containers (preserve data):
  ```bash
  make down
  ```

- Stop containers and remove DB volume (destroys data):
  ```bash
  docker compose down -v
  ```

## Notes

- The `worker` service runs GoodJob for async jobs; it reads the same env as the web service.
- API integrations (e.g., `ODDS_API_KEY`) must be provided in `.env.docker` if you need those features locally.
