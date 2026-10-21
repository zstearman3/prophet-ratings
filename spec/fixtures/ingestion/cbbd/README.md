# Synthetic CBBD fixtures

`final.json` is hand-authored synthetic provider-shaped data for adapter tests.
It contains invented labelled teams and IDs, never downloaded games, credentials
or bulk provider data. Shape follows public OpenAPI 1.30.1 inspected October 20,
2026; it is a deliberately minimal basic-total subset, excluding vendor ratings.
Home: 20 two-pointers + 5 threes + 10 free throws = 65; away uses 9 free throws = 64.
Both: 25/55 FG, 10 offensive + 20 defensive = 30 official rebounds, 40 game
minutes = 200 player minutes, 10 total turnovers including 2 team turnovers.
Specs mutate copies for OT, missingness, corrections and failure evidence.
