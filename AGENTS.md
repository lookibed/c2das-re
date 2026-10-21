# Agents

`CLAUDE.md` is the entrypoint for every agent: it routes to the documents, the skills, the
gates and the review machinery. Codex sessions take their MCP wiring from
`.codex/config.toml` (copy `.codex/config.toml.example`); Claude Code sessions from
`.mcp.json` and the LSP plugin under `.claude/skills/daslang-lsp`.

# Git workflow

- `main` is the only long-lived branch. It receives verified work only through pull requests,
  is never force-pushed and never deleted. GitHub offers branch protection on a private
  repository only with a Pro plan (the protection and ruleset endpoints answer 403 here), so
  the rule holds by discipline.
- One branch per ledger item, named `<item>-<slug>` (`p4.9-<slug>`); outside the ledger
  `fix/<slug>`, `docs/<slug>`, `perf/<slug>`, `upstream/<slug>`. The branch is pushed after
  every verified commit (`git push origin HEAD`).
- Every item lands as a pull request into `main`, opened with `gh pr create --body-file`. The
  body states what changed, the suites (gcc-torture, c-testsuite, csmith), the perf ratio
  table and its delta, the readability delta, the ledgered leftovers and the preflight result.
  It merges with `gh pr merge --rebase --delete-branch` after the verification; never a squash.
- Each phase end is an annotated tag `v0.<phase>.0` (`v0.4.0` when P4 closes) with a GitHub
  release carrying a short summary.
- No GitHub Actions: `scripts/preflight.sh --full` runs locally before each pull request.
- `.gitattributes` marks the C inputs (fixtures, kernels, fetched suite trees, the vendored
  Doom sources) `linguist-vendored` and the recorded captures `linguist-generated`, so the
  language statistics show the converter's own code.

# Workspace hygiene

- Never use `docs/`, `probes/`, `suites/` or a deployment directory as scratch space. Diagnostic
  logs go under `logs/` (gitignored), converted output under `out/` (gitignored), suite fetches
  under `suites/*/fetch/`.
- Clean up files created for probes, benchmarks and abandoned launches when the work is done.
  Keep active process logs, user data and one useful rollback artifact unless asked otherwise.
- `git status` is clean of untracked files when a session ends: commit, ignore with a reason,
  or delete.
