# Agents

`CLAUDE.md` is the entrypoint for every agent: it routes to the documents, the skills, the
gates and the review machinery. Codex sessions take their MCP wiring from
`.codex/config.toml` (copy `.codex/config.toml.example`); Claude Code sessions from
`.mcp.json` and the LSP plugin under `.claude/skills/daslang-lsp`.

# Git workflow

- `main` is the only long-lived branch. It receives verified work only through pull requests,
  is never force-pushed and never deleted; the rule holds by discipline, since a private
  repository has no branch protection here (root `ARCHITECTURE.md` section 7). The change that
  makes the repository public enables protection on `main` (no direct push, no force push, the
  required check `preflight`, linear history) and the approval of every outside contributor's
  workflow run in the same change.
- One branch per pull request, named `<item>-<slug>` for a ledger item (`p4.9-<slug>`; a later
  pull request of a split item adds a number, `p5.3-<slug>-2`), otherwise `fix/<slug>`,
  `docs/<slug>`, `perf/<slug>` or `upstream/<slug>`. The branch is pushed after every verified
  commit (`git push origin HEAD`).
- Every item lands as a pull request into `main`, opened with `gh pr create --body-file`. The
  body states what changed, the gcc-torture, c-testsuite and csmith counts when the pull
  request ran those suites, the perf ratio table with its delta when it recorded perf, the
  readability delta when it changed converter output, the ledgered leftovers and the preflight
  result, and ends with a `Refs:` line when an issue relates, `lookibed/daScript#N` for every
  upstream defect the item found.
- A pull request merges with `gh pr merge --rebase --delete-branch`, never a squash.
- A pull request carries at most about 600 lines of non-generated code. A ledger item
  larger than that is split into consecutive pull requests, stacked or sequential, each green
  and reviewed on its own.
- A commit per logical step: a test with the change it covers, never one commit per phase. A
  coder subagent commits its steps as it goes; the lead does not squash them into one.
- A pull request merges only when the `preflight` check is green AND the pull request's review
  pass is closed with no BLOCKING or MAJOR finding open.
- Every pull request runs `scripts/preflight.sh`, the `ports/tests` suite and the dastest suites
  of the folders it touches locally before it is opened, and gets one review pass plus a re-check
  of each BLOCKING or MAJOR fix. A pull request that does not close a phase runs no
  per-document dragon audit and no `scripts/run_perf.sh` recording.
- A pull request that changes `converter/` outside `converter/tests/`, `c_runtime/` or
  `dasCRuntime/` also runs the gcc-torture, c-testsuite and csmith suites before it merges.
- A pull request touching `suites/suite_runner.das`, `lua/` or `ports/` runs
  `scripts/preflight.sh --full` before it merges.
- The last pull request of a phase runs `scripts/preflight.sh --full`, a dragon-agent audit of
  every `REVIEW*.md`, `ARCHITECTURE*.md` and `AGENTS.md` the phase changed, an archivist pass
  over each of those architecture documents, the dupe-sweeper and style-hygiene audits over the
  phase's new code, and `scripts/run_perf.sh --readme`, which re-records
  `perf/results_linux.json`.
- Closing a phase is an annotated tag `v0.<phase>.0` with a GitHub release carrying the suite
  counts and the perf and readability numbers at that commit, and the ports repository
  (`lookibed/c2das-ports`) regenerated from that tag with `bash scripts/publish_ports.sh --commit
  --push`; the phase is closed only with the tag, the release and the regeneration done.
- A diff to `.github/workflows/preflight.yml` keeps the job's `if` on the head repository, so a
  fork's pull request never runs on the self-hosted runner (root `ARCHITECTURE.md` section 7).
- A diff adding a C-input folder (fixtures, kernels, fetched suite trees, vendored sources) or a
  recorded capture marks it in `.gitattributes` (`linguist-vendored`, `linguist-generated`) in
  the same change, so the language statistics show the converter's own code.

# Workspace hygiene

- Never use `docs/`, `probes/`, `suites/` or a deployment directory as scratch space. Diagnostic
  logs go under `logs/` (gitignored), converted output under `out/` (gitignored), suite fetches
  under `suites/*/fetch/`.
- Clean up files created for probes, benchmarks and abandoned launches when the work is done.
  Keep active process logs, user data and one useful rollback artifact unless asked otherwise.
- `git status` is clean of untracked files when a session ends: commit, ignore with a reason,
  or delete.
