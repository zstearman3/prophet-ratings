# Notion workflow

Prophet Ratings uses Notion for planning and this repository for implementation evidence. The repository skills are `prophet-plan-ticket` and `prophet-implement-ticket` in `.agents/skills/`. Both read this shared map so board conventions have one maintained source.

`prophet-plan-ticket` is the collaborative product and technical discovery phase:
inspect code, compare approaches and relative effort/maintenance costs, and refine
behavior and scope with the user. The saved ticket preserves the problem/outcome,
numbered observable acceptance criteria, agreed approach and consequential
constraints, plus useful code starting points and actual dependencies. Conversation
can be exploratory; the ticket summarizes its decisions concisely. Batch planning
reuses shared investigation and decisions while keeping each ticket understandable.
`prophet-implement-ticket` revalidates code observations and owns the detailed
execution plan, risk scoring, tests/commands, independent reviews, and QA. Preserve
agreed product/architecture decisions when adding implementation evidence.

Ticket implementation requires installed, readable Superpowers `writing-plans` and
`using-git-worktrees` skills and their resources for the selected workflow. Resolve
them from the current skill catalog or installed package; online source alone does
not satisfy preflight. If absent, install/repair Superpowers through the user's
chosen skill/plugin setup before invoking implementation; ticket runs do not
silently install or update dependencies. The upstream source is
[obra/superpowers](https://github.com/obra/superpowers).

The implementation skill always uses an isolated task worktree, fetches and pulls
the latest `development` before starting a new ticket, and records the base SHA.
Resumed work integrates freshly fetched development without discarding task edits;
stacked work also includes the latest development plus its explicit dependency.
Implementation plans and evidence stay in the ticket's Implementation record.
Independent plan review, code review, and QA precede PR publication and `Testing`.
The skill's supporting references define risk/escalation and a bounded process
targeting one Plus five-hour usage allowance; this is a soft consumption target,
not a guaranteed subscription cap. Missing prerequisites or incomplete gates leave
the ticket out of `Testing`/`Done` with a resumable handoff.

## Locations

Verified through the connected Notion workspace in September 2026:

| Resource | ID / URL |
| --- | --- |
| Work Items database | https://app.notion.com/p/1db17d6b0c248070b070dae9daf41426 |
| Work Items data source | `collection://1db17d6b-0c24-8068-be3d-000bcc9064f3` |
| Initiatives database | https://app.notion.com/p/1db17d6b0c2480cba230fb48bba0d9be |
| Initiatives data source | `collection://1db17d6b-0c24-80a0-9fd7-000b14f6f7f1` |
| Current Sprint view | `view://30917d6b-0c24-80dc-907a-000c3d511f35` |
| All tasks view | `view://1db17d6b-0c24-80f6-8a20-000cde2b3ba0` |

Fetch the database to refresh its schema, templates, data sources, and view filters before writing. These IDs are locators, not credentials. If a resource becomes inaccessible, ask for its replacement link instead of selecting a similarly named board elsewhere.

Current Sprint filters on the Sprint property. Do not infer its selected month from the calendar or hardcode September 2026: inspect the live view. Unscheduled tickets are visible through All tasks; creating a ticket does not automatically schedule it.

## Epics and stories

Use **Initiatives as epics** and **Work Items as the stories/tasks that deliver them**. When the user asks for an epic, create it in Initiatives; do not substitute a parent Work Item or add an `Epic` type to Work Items.

Keep the epic's outcome, scope, shared acceptance criteria, and related work on the Initiative. Put implementable stories, their acceptance criteria, and verification steps in Work Items, linked through each item's `Initiative` relation. Verify that the Initiative's reciprocal `Tasks` relation includes those items. Use `Parent-task` / `Sub-tasks` only for an agreed breakdown within Work Items, not as a replacement for the Initiative-to-story structure.

Agree on the story split before creating multiple Work Items. An epic request authorizes creating the Initiative once its scope is settled; it does not require another permission gate. If the split is not settled, keep proposed stories in the Initiative body until agreed. Do not create an Initiative for every standalone ticket.

For new Initiatives, use `Project name` for the title, `Summary` for the outcome, and `Planning` for the status unless the user specifies otherwise. Leave `Owner`, `Dates`, and `Priority` unset unless provided. Preserve existing initiative statuses when linking or implementing stories.

## Work Item properties and defaults

These are observed schema values; live schema takes precedence for valid names and types. Default choices below are initial workflow conventions, not claims about database-enforced defaults. Honor explicit user choices.

| Property | Convention |
| --- | --- |
| Task name | Required title: a concise action or concrete problem |
| Summary | Brief description of the intended outcome |
| Status | Create as `Not started`; begin work as `In progress`; verified handoff as `Testing`; user owns `Done` unless explicitly delegated |
| Type | Choose `Bug`, `Story`, `Task`, or `Spike` to match the agreed work |
| Feature Area | Existing choices: `UI`, `Import`, `Ratings`; set when clearly applicable, otherwise omit |
| Priority | Existing choices: `Low`, `Medium`, `High`; omit unless chosen |
| Sprint | Omit unless chosen; use a live option or the live Current Sprint filter when the user requests the current sprint |
| Assignee / Due | Omit unless provided; do not infer identity or deadlines |
| Initiative | Link the agreed epic in Initiatives, including one created for the request; omit for standalone work without a confirmed relevant initiative |
| Parent-task / Sub-tasks | Preserve existing relations; create a hierarchy only for an agreed task split |
| Tags | Optional; use existing relevant choices only |

Work Items also has `Archived`; it has no observed Blocked status. Record blockers in the ticket body and retain its current non-complete status. Do not alter database schemas, views, templates, or initiative status as routine ticket work.

The observed Task template contains Description. The Bug template adds Steps to Reproduce. Use these conventions with the planning skill's acceptance criteria, agreed approach/constraints, and useful code starting points; the templates themselves do not contain a full implementation specification.

## Interaction and authority

- Planning is iterative. Inspect code, explore approaches, and refine the intended behavior with the user before creating a ticket. Keep working drafts in the conversation by default. Once material product/domain decisions are settled and creation is requested, create the agreed ticket without an extra approval round; detailed implementation choices can remain open. If explicitly asked to save an unfinished idea, preserve its open decisions and disclose that it is not ready for implementation, without inventing schema/status values. A requested batch may publish settled independent tickets while other ideas continue to evolve.
- Implementation may update the selected ticket's status and body with decisions, blockers, and a handoff. Use `Testing` after successful required verification so the user can review; do not equate local checks with deployment or user acceptance.
- Scope updates to the selected ticket and agreed relations. Do not create extra plan pages, initiatives, or batches of tickets without an agreed need. These skills do not authorize messages or comments to other people.

## Notion operations

Use currently available Notion MCP tool schemas, not copied payloads from an old session. Search within Initiatives when locating or deduplicating epics and within Work Items for their stories or standalone tickets; a filtered sprint view is not a complete duplicate search. Fetch full matching pages and resolve meaningful ambiguity before writing.

Before creating or editing page content, read `notion://docs/enhanced-markdown-spec` through the Notion fetch tool or its resource interface. Create pages with an explicit `parent.data_source_id` taken from the appropriate fetched collection (the UUID, not the database ID): Initiatives for epics, Work Items for stories/tasks. Use `Project name` for Initiative titles and `Task name` for Work Item titles, not a duplicate body heading.

For this simple ticket format, supply the agreed body directly. If a task specifically calls for applying a Notion template, follow the live tool's template rules: do not send template and content together, and wait for asynchronous template application before editing the result.

Re-fetch before updates. Prefer targeted content edits or one appended handoff section, and supply only properties being changed. Preserve user content, relations, and child pages. Do not replace entire pages to add progress notes.

After any write, fetch the page and verify the parent, intended properties, and content. On a timeout or ambiguous result, inspect the existing page or search for the creation before retrying; do not blindly duplicate tickets or notes. If the result remains uncertain, stop writes and report it. If a tool is unavailable, use other available read tools where sufficient and report the missing capability; do not repeatedly call a tool reported as not found.

If Notion is unavailable, keep the draft or implementation handoff in the conversation and state that it has not been saved. Do not claim a ticket was created, synchronized, or moved to another status without verification.

## Release notes

Include the Work Item page URL in its PR description. [`bin/release`](releases.md)
uses those explicit links to enrich merged PRs with task titles and current Status.
It includes unlinked changes, reads Notion only, and never marks work Done. Terminal
API access requires its own `NOTION_TOKEN`; the Codex connector is separate.
