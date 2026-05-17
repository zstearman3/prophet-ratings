# Current State

Prophet Ratings imports Sports Reference game data, stores team-game stats, calculates adjusted ratings, and generates predictions from rating snapshots.

## Venue Classification

The app now stores explicit venue classification on `games`:

- `venue_type`: `home`, `neutral`, or `unknown`
- `venue_source`: source of the classification
- `venue_confidence`: `confirmed`, `manual`, or `unknown`
- `venue_name`: optional display/source venue name

The default is `unknown`. Missing venue data is no longer treated as a confirmed home game.

Normal game ingestion is coordinated by `Ingestion::GamesIngestionService`, which scrapes daily game rows, enriches them with `Ingestion::GameRowEnricher`, and imports the enriched rows. `Importer::GameVenueEnricher` scrapes Sports Reference team schedule rows via `Scraper::TeamScheduleEnrichmentScraper`; it is still available as an opt-in backfill/repair path and preserves manual classifications stored directly on `games`.

Game date queries use an Eastern Time schedule date by default. `Game#start_time` remains an actual timestamp, but selected-date pages, import matching, resume windows, and rating snapshot lookups use `Game#schedule_date`/`Game.on_schedule_date` so late Eastern games are not moved to the next basketball date by UTC storage.

Ratings and predictions apply home-court advantage only for confirmed or manual home games. Neutral and unknown venues receive zero home-court adjustment. Unknown venues are also surfaced in prediction metadata as a confidence issue.

Remaining work:

- add Rails admin support for manually correcting known neutral-site events that Sports Reference cannot classify
- monitor `bundle exec rails venue:coverage` after imports
