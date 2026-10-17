# Preparing a release

`development` is the integration branch. A push to `main` triggers the existing ECS
deployment workflow. `bin/release` prepares a tag and a **draft GitHub release**
from fetched `origin/development`; it does not merge branches, publish the draft,
change Notion statuses or deploy anything.

Run it from a checkout with Ruby, Git, GitHub CLI (`gh`) and an authenticated GitHub
account with access to the repository. No Rails server, database or bundle boot is
needed. Configure your Git name/email for annotated tags and run `gh auth login`
if necessary. GitHub commands use the checkout's repository, ignoring `GH_REPO`.

```bash
bin/release --dry-run
bin/release
```

Preview first. Dry-run fetches the two remote branch refs and reads GitHub/Notion,
but creates no local tags, remote tags or releases. Both modes use fetched commits,
not local branches or uncommitted files. Release notes print before remote writes.

The script includes first-parent commits in `origin/main..origin/development`.
Merged PRs are linked and grouped by Notion status; Dependabot has its own section.
PRs without Notion links and direct commits are retained. Notion status describes
work-item review state; it does not decide whether merged code belongs in a release.
The notes retain exact candidate/baseline SHAs and a comparison link.

Versions use the local calendar date: `vYYYY.MM.DD`, then `.01`, `.02`, etc. Both
local and remote tags reserve versions. A second run creates another dated release;
use `--update` when intentionally refreshing the same draft.

## Notion enrichment

Put an individual Work Item URL in the PR description, for example:

```text
Ticket: https://app.notion.com/p/<page-id>
```

The script reads each unique linked page's title and `Status` through the Notion
API, using an integration token supplied as `NOTION_TOKEN` in the environment.
Give that integration read access to the Work Items database. The Codex Notion
connection does not automatically supply credentials to a terminal script.
Do not commit tokens or add them to PR descriptions/release notes.

Without a token, ticket links remain and their status is **Notion unavailable**.
Access, network and parsing failures also retain links with unavailable status,
and print a warning. Check those groups before publishing the draft. No title-based
guessing or whole-board lookup is performed. The script uses the
[Notion page retrieval endpoint](https://developers.notion.com/reference/retrieve-a-page).

## Refreshing a draft

```bash
bin/release --update --dry-run
bin/release --update
# Or select a specific earlier draft:
bin/release --update vYYYY.MM.DD.NN --dry-run
bin/release --update vYYYY.MM.DD.NN
```

Without a tag argument, update selects today's latest numeric tag. Explicit tags
must follow the date format. Update refuses a missing or published GitHub release,
including in dry-run. It regenerates notes from the current production/development
refs and moves **that draft's tag** to the newly fetched development SHA.

The push uses an exact remote-tag lease: a concurrent tag change is rejected.
Unrelated local tags are protected. Draft creation/edit happens before tagging;
if tagging/pushing fails, the draft remains and the script prints the explicit
`--update <tag>` recovery command. Inspect any failed/ambiguous GitHub operation
before retrying. A retry of the same candidate can reuse its local draft tag.

Review the draft notes and tag target in GitHub. Promoting development to main is
still a separate, explicit action and triggers deployment. Publishing a GitHub
release or pushing its tag does not trigger the current deployment workflow.
