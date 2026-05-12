# Local Development Guide (Docker)

This project is set up to run entirely via Docker for local development.

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

## Using the Makefile

The root `Makefile` provides short commands for common Docker Compose workflows. These commands are just convenience wrappers around `docker compose`.

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

To run a one-off Rails task that does not have a Makefile shortcut:

```bash
docker compose exec web bin/rails <task:name>
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

