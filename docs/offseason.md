# Offseason Operations

Use this sequence when preparing a new college basketball season.

## 1. Prepare the season shell

Create the future `Season` and missing `TeamSeason` rows before doing conference realignment:

```bash
bin/rails season:prepare YEAR=2027
```

Optional date overrides:

```bash
bin/rails season:prepare YEAR=2027 START_DATE=2026-11-01 END_DATE=2027-04-10
```

`season:prepare` is intentionally limited. It does not make the season current, sync games, deduplicate games, initialize preseason ratings, create ratings config, or run ratings.

## 2. Update conference memberships

There are two supported paths.

### RailsAdmin operational updates

Use RailsAdmin for ad hoc offseason realignment after the target season exists. Create a new `TeamConference` row with the team, conference, and start season.

When created through RailsAdmin, the app automatically closes the prior membership at the season before the new start season if the prior membership is open or overlaps the new assignment. It does not fill intentional gaps.

### Authoritative CSV updates

Edit:

```text
db/seeds/team_conferences.csv
```

Then run:

```bash
bin/rails db:seed
```

`db:seed` treats the CSV as authoritative. It upserts matching `(team, start season)` rows, updates changed rows, creates missing rows, and deletes database memberships not present in the CSV.

Do not expect RailsAdmin-only rows to survive `db:seed`.

## 3. Bootstrap the season

After season preparation and conference updates:

```bash
bin/rails season:bootstrap YEAR=2027
```

Bootstrap calls the same preparation service first, marks the season current, ensures the ratings config, optionally initializes preseason ratings, syncs games, deduplicates, and runs ratings depending on the task environment flags.

Useful flags:

```bash
bin/rails season:bootstrap YEAR=2027 SYNC_GAMES=false RUN_RATINGS=false
bin/rails season:bootstrap YEAR=2027 SYNC_RESUME=true RATINGS_RESUME=true
```

## Historical corrections

Changing `TeamConference` rows does not automatically recalculate historical games, standings, predictions, or rating snapshots. If you correct historical membership data after games were finalized, rerun the explicit game finalization and ratings workflows needed for the affected season.

## Safety boundaries

- No conference realignment job runs automatically during deploy, boot, nightly sync, or bootstrap.
- `import:base` imports teams, seasons, team seasons, and conferences, but does not reconcile conference memberships.
- `db:seed` is the only authoritative CSV reconciliation entry point.
