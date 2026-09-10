# Notion workflow

Prophet Ratings uses Notion for planning and this repository for implementation evidence. The repository skills are `prophet-plan-ticket` and `prophet-implement-ticket` in `.agents/skills/`. Both read this shared map so board conventions have one maintained source.

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

## Properties and defaults

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
| Initiative | Link an existing, confirmed relevant initiative; otherwise omit |
| Parent-task / Sub-tasks | Preserve existing relations; create a hierarchy only for an agreed task split |
| Tags | Optional; use existing relevant choices only |

Work Items also has `Archived`; it has no observed Blocked status. Record blockers in the ticket body and retain its current non-complete status. Do not alter database schemas, views, templates, or initiative status as routine ticket work.

The observed Task template contains Description. The Bug template adds Steps to Reproduce. Use these conventions with the planning skill's acceptance criteria and implementation notes; the templates themselves do not contain a full implementation specification.

## Interaction and authority

- Planning is iterative. Inspect code, ask material clarifying questions, and wait for answers before creating a ticket. Do not create an early Notion draft. Once questions are answered and creation is requested, create the agreed ticket without an extra approval round.
- Implementation may update the selected ticket's status and body with decisions, blockers, and a handoff. Use `Testing` after successful required verification so the user can review; do not equate local checks with deployment or user acceptance.
- Scope updates to the selected ticket and agreed relations. Do not create extra plan pages, initiatives, or batches of tickets without an agreed need. These skills do not authorize messages or comments to other people.

## Notion operations

Use currently available Notion MCP tool schemas, not copied payloads from an old session. Search within the Work Items data source when locating or deduplicating tickets; a filtered sprint view is not a complete duplicate search. Fetch full matching pages and resolve meaningful ambiguity before writing.

Before creating or editing page content, read `notion://docs/enhanced-markdown-spec` through the Notion fetch tool or its resource interface. Create tickets with an explicit `parent.data_source_id` taken from the fetched Work Items collection (the UUID, not the database ID). Put the title in `Task name`, not a duplicate body heading.

For this simple ticket format, supply the agreed body directly. If a task specifically calls for applying a Notion template, follow the live tool's template rules: do not send template and content together, and wait for asynchronous template application before editing the result.

Re-fetch before updates. Prefer targeted content edits or one appended handoff section, and supply only properties being changed. Preserve user content, relations, and child pages. Do not replace entire pages to add progress notes.

After any write, fetch the page and verify the parent, intended properties, and content. On a timeout or ambiguous result, inspect the existing page or search for the creation before retrying; do not blindly duplicate tickets or notes. If the result remains uncertain, stop writes and report it. If a tool is unavailable, use other available read tools where sufficient and report the missing capability; do not repeatedly call a tool reported as not found.

If Notion is unavailable, keep the draft or implementation handoff in the conversation and state that it has not been saved. Do not claim a ticket was created, synchronized, or moved to another status without verification.
