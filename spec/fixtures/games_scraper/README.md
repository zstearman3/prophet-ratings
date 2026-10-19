# Games scraper source fixtures

Captured read-only on 2026-10-19 from Sports Reference:

- [2024-11-04 daily schedule](https://www.sports-reference.com/cbb/boxscores/index.cgi?month=11&day=4&year=2024)
- [Howard at Kansas boxscore](https://www.sports-reference.com/cbb/boxscores/2024-11-04-20-kansas.html)

A second [2025-11-03 schedule](https://www.sports-reference.com/cbb/boxscores/index.cgi?month=11&day=3&year=2025)
was inspected to corroborate the `winner`/`loser` classes and `F<span>inal</span>`
label. Neither inspected schedule supplied an authentic unlinked/no-boxscore
example. These fixtures do **not** claim that Howard or Kansas were untracked,
unlinked, canceled or missing boxscores in the source.

Minimal extractions:

- `linked_final.html`: the Howard/Kansas men's summary, wrapped in the original
  `game_summaries` container; retains the descriptor row and Kansas poll rank.
- `detailed_final.html`: the corresponding scorebox and basic/advanced tables.
  Removed logos, navigation, table headers and player bodies; retained original
  team identifiers and footer totals. Advanced footers remain to catch accidental
  selection by global footer offsets. Nokogiri serialization normalizes markup.

Derived variants (all transformations use the same captured names/scores):

- `unlinked_final.html`: unwrap team and gamelink anchors, preserving Final text.
- `scheduled.html`: from unlinked final; clear scores, replace Final with 7:00p ET,
  and use two `loser` rows (the existing scheduled layout convention).
- `score_only.html`: remove tables and unwrap scorebox team anchors.
- `ambiguous_scores.html`: remove Final and replace winner with loser.
- `malformed_final.html`: replace away score with `unknown`.
- `canceled_linked.html`: replace linked Final text with Canceled.

Specs also derive single-unlinked names, removed cells/tables, contradictory
winner classes, invalid/tied/zero scores, and explicit nonfinal states in memory.
Nonfinal variants include minified adjacent status cells and metadata descendants,
and both whitespace and hyphenated in-progress spelling.
Those cases are deliberate parser regressions, not additional source captures.

Supported evidence: explicit schedule Final label, a score-consistent winner/loser
pair, or a dated `/cbb/boxscores/...html` page with two named scorebox teams,
scorebox metadata and valid unequal scores. Nonfinal status contradicts completion.
A date or scores without this context never suffices. A team link supplies an
identifier for its basic stat table; when absent, statistics remain unavailable
rather than being assigned by ambiguous global table position.
