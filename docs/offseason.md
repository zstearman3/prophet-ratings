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

## 2. Align conference memberships

Run the standings comparison after preparing the season:

```bash
bin/rails season:align_conferences YEAR=2027
```

Without `YEAR`, this task uses the greatest stored `Season#year` (not the current
season). It fails clearly if there are no seasons or the requested year is missing.
It requests `https://www.sports-reference.com/cbb/seasons/men/<YEAR>-standings.html`.

Recognized teams and conferences are aligned automatically. Unchanged ranges are
not saved, so reruns preserve their timestamps. A switch creates a membership at
the target season and closes an open or overlapping prior range at `YEAR - 1`
through `TeamConferenceAssignment`; that preceding season must already exist.
All membership writes roll back if an assignment fails. Source request, structure,
and duplicate/invalid membership errors stop alignment before membership writes.

The report lists created, changed, and unchanged memberships, plus **review-required
suggestions** for unmatched or ambiguous identities and absent teams/conferences.
Safe changes are saved even when suggestions remain, but the task exits nonzero.
No team or conference is automatically created, deleted, retired, or deactivated.
A different membership already starting in the target year requires manual
correction; future membership conflicts fail validation rather than overwrite data.

Identity and roster assumptions:

- Team identity comes from the stored Sports Reference school URL, including legacy
  URLs. An exact school name or alias is a fallback only when the stored source URL
  cannot supply an identity. Nicknames and fuzzy matches are not used.
- Conferences match exact stored slug, name, or abbreviation. Conflicting matches
  require review. Source naming changes can require correcting stored identities.
- Expected teams and conferences come from membership ranges active in the target
  year. `TeamSeason` alone does not imply Division I participation: preparation
  creates those rows for historical teams as well. Absence is not evidence of a
  move to another division, and historical memberships are preserved.

Review the printed identities and candidate IDs in RailsAdmin or the Rails console,
make only independently verified corrections, then rerun the same command. Absent
teams/conferences may need verified range end dates. A future season with incomplete
standings may need a later rerun when the source is complete. There is no persisted
approval queue or ignore flag. Resolve every suggestion before bootstrap can proceed.

Manual correction paths follow below.

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

Bootstrap prepares the season shell, runs the same conference alignment, and only
after successful alignment marks the season current, ensures the ratings config,
optionally initializes preseason ratings, syncs games, deduplicates, and runs ratings.
An alignment error or review-required result stops all those downstream steps.
The prepared shell and any safe alignment changes remain available for review and
an idempotent rerun. Alignment still runs when game and ratings flags are disabled.

Useful flags:

```bash
bin/rails season:bootstrap YEAR=2027 SYNC_GAMES=false RUN_RATINGS=false
bin/rails season:bootstrap YEAR=2027 SYNC_RESUME=true RATINGS_RESUME=true
```

## Historical corrections

Changing `TeamConference` rows does not automatically recalculate historical games, standings, predictions, or rating snapshots. If you correct historical membership data after games were finalized, rerun the explicit game finalization and ratings workflows needed for the affected season.

## Safety boundaries

- Conference alignment runs during explicit `season:bootstrap` and
  `season:align_conferences` calls, not deploy, application boot, or nightly sync.
- `import:base` imports teams, seasons, team seasons, and conferences, but does not reconcile conference memberships.
- `db:seed` is the only authoritative CSV reconciliation entry point.

## Source smoke verification

On September 10, 2026, the standalone scraper was run against the 2026 standings
URL without loading Rails or connecting to a database. It parsed 365 unique team
memberships across 31 conferences from the live page's commented tables.
Automated specs use a reduced synthetic
HTML fixture reflecting that structure and do not access Sports Reference.
