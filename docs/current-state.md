# Current State

Prophet Ratings imports Sports Reference game data, stores team-game stats, calculates adjusted ratings, and generates predictions from rating snapshots.

## Venue Classification

The app now stores explicit venue classification on `games`:

- `venue_type`: `home`, `neutral`, or `unknown`
- `venue_source`: source of the classification
- `venue_confidence`: `confirmed`, `manual`, `inferred`, or `unknown`
- `venue_name`: optional display/source venue name

The default is `unknown`. Missing location data is no longer treated as a confirmed home game.

`Importer::GameVenueEnricher` applies manual overrides from `db/data/game_venue_overrides.yml` before inferred location logic, but it is opt-in and not part of the standard game import pipeline. Manual overrides are the v1 correction path for neutral-site tournaments or unreliable imported locations.

Ratings and predictions apply home-court advantage only for confirmed or manual home games. Neutral and unknown venues receive zero home-court adjustment. Unknown venues are also surfaced in prediction metadata as a confidence issue.

Remaining work:

- add manual overrides for known neutral-site events
- add a separate Sports Reference venue scraper/importer
- monitor `bundle exec rails venue:coverage` after imports
- consider a small isolated schedule venue source only if manual review leaves too many unknown games
