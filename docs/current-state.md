# Current State

Prophet Ratings imports Sports Reference game data, stores team-game stats, calculates adjusted ratings, and generates predictions from rating snapshots.

## Venue Classification

The app now stores explicit venue classification on `games`:

- `venue_type`: `home`, `neutral`, or `unknown`
- `venue_source`: source of the classification
- `venue_confidence`: `confirmed`, `manual`, `inferred`, or `unknown`
- `venue_name`: optional display/source venue name

The default is `unknown`. Missing location data is no longer treated as a confirmed home game.

Normal game ingestion is coordinated by `Ingestion::GamesIngestionService`, which scrapes daily game rows, enriches them with `Ingestion::GameRowEnricher`, and imports the enriched rows. `Importer::GameVenueEnricher` applies manual overrides from `db/data/game_venue_overrides.yml`, then scrapes Sports Reference team schedule rows via `Scraper::TeamScheduleEnrichmentScraper`; it is still available as an opt-in backfill/manual repair path.

Ratings and predictions apply home-court advantage only for confirmed or manual home games. Neutral and unknown venues receive zero home-court adjustment. Unknown venues are also surfaced in prediction metadata as a confidence issue.

Remaining work:

- add manual overrides for known neutral-site events that Sports Reference cannot classify
- monitor `bundle exec rails venue:coverage` after imports
- revisit whether `location` should be renamed once the venue scraper has run against real data
