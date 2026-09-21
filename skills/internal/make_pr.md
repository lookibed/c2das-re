# Pre-PR Checklist

Complete every step in order; fix a failure before proceeding. The tree is frozen while the
preflight runs: no commits, no reconfigure.

| Step | Gate / tool | Fix policy |
|---|---|---|
| 0 Sync | `git fetch origin && git rebase origin/main` | Behind `origin/main` = rebase first; squash only AFTER the rebase |
| 0 Untracked | preflight `untracked` gate | Empty at PR time - commit, delete, or ignore each |
| 0a0 Comment harvest | the diff's ADDED comments | Spawn ONE `harvester` per touched folder root, scoped to the comments the diff adds. Rule on its ledger: RENAME first, RULE proposals land in the folder's `REVIEW.md`, a FACT lands as the section, its `{#anchor}` and the `[arch]` citation, KEEP one-liners are `//!` contract comments. Finishes before any other agent spawns |
| 0a REVIEW audit | preflight `review-md` gate, then one `review-md-auditor` per checklist the walk lists (`$DASLANG_ROOT/utils/internal/review-md/main.das -- --base origin/main --list-only`) | Red gate = fix first, no agents until green. Checklist defects fixed in the same batch, then two `dragon` passes per rule document at most (`skills/review_md.md`) |
| 0a TDD audit | one `tdd-auditor` over the whole diff, in its own worktree (`skills/tdd_audit.md`) | UNTESTED branch -> test in the same change. UNPROVEN -> run the settling gate or state the claim in the PR body |
| 0a Dupe audit | one `dupe-auditor` over the whole diff (`skills/dupe_audit.md`) | DUPLICATE -> reuse; TEMPLATABLE -> discuss the fold; a declined fold is named under `### Not done` |
| 0a2 Style hygiene | `style-hygiene-auditor` (`skills/comment_style_hygiene.md`) | Non-blocking: fix each or consciously decline it |
| 0a3 Woodpecker | one codex round at the final branch shape (`skills/internal/woodpecker.md`), background Bash | Verify each finding; a round that did not run is disclosed under `### Validation` |
| 1 Preflight | `scripts/preflight.sh --full` (`skills/internal/preflight.md`) | Once per PR. A red gate is fixed and re-run alone with `--only` |
| 2 Workarounds | `git diff origin/main..HEAD`, read every changed file | A compensating step, a synthetic path diverging from the real one, a special-case branch: STOP and ask the user, fix-vs-workaround is their call |
| 3 Docs | `docs/` never changes to match code | A finding against a document is reported to its authoring repository, and the code cites the owning `ARCHITECTURE.md` section |
| 4 Format | MCP `format_file` on every changed `.das` | Verify the files still compile |
| 5 `.md` stop | `git diff --name-only origin/main..HEAD \| grep '\.md$'` | Any match: STOP, list the changes, ask the user to review BEFORE push |
| 6 PR | `gh pr create` (or the GitHub MCP), body per the template below | Later fixes on a squashed branch are `git commit --amend --no-edit` + `git push --force-with-lease` |
| 6a Babysit | `skills/internal/babysit.md` | Creating the PR does not end the workflow |
| 7 Post-land sweep | `git ls-files --others --exclude-standard` | Sweep the debris the rounds minted |

## Agent topology

The order is strict: row 0a0 finishes - the harvester's ledger ruled and applied, the amend
committed - before any agent of 0a, 0a2, 0a3 or the review round spawns; they audit the
harvested tree. A non-trivial change runs the full round (`skills/internal/review_round.md`)
on top of these instances. Agent definitions snapshot at session start: a just-edited
`.claude/agents/*.md` exists in the NEXT session.

## The PR body - two layers, one artifact

**Top - the reviewer document**, 100 words, 200 the ceiling: the consumer-impact line when
there is one, then `**Why.**` (the problem, one or two sentences), `**What changes.**` (one
bullet per mechanism), `**Observable behavior.**` (`before -> after` lines, or `None - <why>`),
`**Where to look.**` (entry points and risky spots). Plain English, no machinery narration.

**Fold - the ledger**, one `<details>` block with fixed headings: `### Validation` (exceptions
only: a gate skipped, a partial result, a known-red cell with its control), `### Claims -
stated, not tested`, `### Not done`. Omit an empty section; never rename one.

No session links, no "Generated with" footer, no `Co-Authored-By` trailer: the PR and its
commits are the user's. `#N` is GitHub reference syntax; a ledger row is cited as
`followup N` or in backticks.
