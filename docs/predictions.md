# Predictions

This document captures prediction behavior that is important for model interpretation.

## Venue handling

Predictions use explicit game venue classification from `Game#venue_type`:

- `home`: apply the home team's stored home offense/defense boost, or the configured default home boost when missing
- `neutral`: apply zero home-court adjustment
- `unknown`: apply zero home-court adjustment and expose a venue confidence issue in prediction metadata

`GamePredictionBuilder` passes `venue_type` and `venue_confidence` from the game into `ProphetRatings::GamePredictor`. The predictor includes these metadata keys:

- `venue_type`
- `venue_confidence`
- `home_court_adjustment_applied`
- `venue_confidence_issue`

For unknown venues, `venue_confidence_issue` is `venue_unknown_home_court_not_applied`.

This is a conservative v1 choice. It prevents the model from confidently applying home-court advantage to games where Sports Reference did not provide trustworthy location data. Venue coverage can be corrected via `Importer::GameVenueEnricher` and manual `Game` updates through Rails admin or the console. Further coverage improvements should be handled by improving the scraper/enricher or marking individual game records with `venue_confidence: manual`.
