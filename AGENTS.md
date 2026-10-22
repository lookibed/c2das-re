# Agents

`CLAUDE.md` is the entrypoint for every agent: it routes to the documents, the skills, the
gates and the review machinery. Codex sessions take their MCP wiring from
`.codex/config.toml` (copy `.codex/config.toml.example`); Claude Code sessions from
`.mcp.json` and the LSP plugin under `.claude/skills/daslang-lsp`.

# Git workflow

- `main` is the only long-lived branch. It receives verified work only through pull requests,
  is never force-pushed and never deleted. GitHub offers branch protection on a private
  repository only with a Pro plan (the protection and ruleset endpoints answer 403 here), so
  the rule holds by discipline. When the repository goes public, enable protection on `main`
  (no direct push, no force push, the required check `preflight`, linear history) and require
  approval for every outside contributor's workflow run.
- One branch per ledger item, named `<item>-<slug>` (`p4.9-<slug>`); outside the ledger
  `fix/<slug>`, `docs/<slug>`, `perf/<slug>`, `upstream/<slug>`. The branch is pushed after
  every verified commit (`git push origin HEAD`).
- Every item lands as a pull request into `main`, opened with `gh pr create --body-file`. The
  body states what changed, the suites (gcc-torture, c-testsuite, csmith), the perf ratio
  table and its delta, the readability delta, the ledgered leftovers and the preflight result,
  and ends with a `Refs:` line linking the related issues, `lookibed/daScript#N` for every
  upstream defect the item found. It merges with `gh pr merge --rebase --delete-branch` after
  the verification and only with the `preflight` check green; never a squash.
- Each phase end is an annotated tag `v0.<phase>.0` with a GitHub release carrying the suite
  counts and the perf and readability numbers at that commit, and the ports repository
  (`lookibed/c2das-ports`) regenerated from that tag with `bash scripts/publish_ports.sh --commit
  --push`; closing a phase includes both.
- CI is `.github/workflows/preflight.yml` on a self-hosted runner (labels `self-hosted`,
  `c2das`) installed under `/opt/actions-runner` on the machine that holds the toolchain, as the
  systemd service of the dedicated user `gha`, which reads `DASLANG_ROOT` and
  `PATH_TO_LIBCLANG` through read-only bind mounts (`/srv/daScript`, `/srv/libclang`; the
  runner's `.env` names them). A pull request runs the fast tier, a push to `main` the full
  tier; a fork's pull request never runs there (the job's `if` on the head repository, and the
  repository setting that keeps fork workflows off). `scripts/preflight.sh --full` still runs
  locally before each pull request.
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
