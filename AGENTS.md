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
- One branch per ledger item, named `<item>-<slug>` (`p4.9-<slug>`); a split item's later pull
  requests branch as `<item>-<slug>-N`; outside the ledger `fix/<slug>`, `docs/<slug>`,
  `perf/<slug>` or `upstream/<slug>`. The branch is pushed after every verified commit (`git
  push origin HEAD`).
- At most one pull request is open at a time; a second is opened only for a fix of a BLOCKING
  defect on `main` or in the open pull request.
- A branch without a pull request lives at most one working session (the time from one start of
  the agent's session to the next).
- Before an item starts, `git branch -r` must show only `main` and the current item's branch, and
  `gh pr list` at most the current item's pull request. Merging a pull request deletes its remote
  and local branches and every worktree of that branch.
- The first report of each working day lists the open branches and pull requests with the reason
  each one still exists.
- Every item lands as a pull request into `main`, opened with `gh pr create --body-file`. The
  body states what changed, the gcc-torture, c-testsuite and csmith counts when the pull
  request ran those suites, the perf ratio table and its delta (the phase end's re-record, or
  the pull request's own measurement), the readability delta, the ledgered leftovers and the
  preflight result, and ends with a `Refs:` line when an issue relates, `lookibed/daScript#N`
  for every upstream defect the item found.
- A pull request merges with `gh pr merge --rebase --delete-branch`, never a squash.
- A pull request carries at most about 400 to 600 lines of non-generated code. A ledger item
  larger than that is split into consecutive pull requests, each opened after the one before
  merges, each green and reviewed on its own.
- A commit per logical step: a test with the change it covers, never one commit per phase. A
  coder subagent commits its steps as it goes; the lead does not squash them into one.
- A commit subject is at most about 72 characters; the details go in the body.
- A new `Done` entry in `docs/implementation_order.md` is at most about ten lines: what was done,
  one to three numbers, a link to the report (the pull request or the item's report). Older entries
  are not rewritten.
- A pull request that closes a ledger item prints in its body the readability criteria table and
  its delta against `main` (`scripts/run_criteria.sh --delta <main's metrics/criteria_linux.json>`,
  or the preflight `criteria` gate's output when the item does not change the output).
- A pull request that closes a ledger item carries a `Кратко` section: two to four lines in
  Russian, no table, in the order essence, number, execution mode (interp, JIT, AOT, exe), next
  step; only facts this pull request measured.
- A decision that waits for the owner (a `NEEDS RULING`) is one line in `docs/rulings-pending.md`:
  the item, the question, the options, the date. The open lines are the first lines of every
  report until the owner rules; a line leaves the file when its ruling lands in the ledger.
- A pull request that changes the default generated output (a lowering, the layout, the names)
  shows before and after on a fixed sample of real output in its body: the `luaV_execute` slice of
  `lvm.das`, `ldo.das`, a module header with its `require` lines, and from P6 a Doom render loop.
  Its review judges readability by the plan's Readable-first decision, not correctness alone.
- The implementer sets no threshold: an item that makes any perf lane worse than `main` by more
  than 5%, or trades speed against the output's shape, is a `NEEDS RULING` line, not the agent's
  decision.
- An item that aims to change a perf number, and any answer to "why is X slower", starts with a
  reference pass and shows it first in its report: how the Rust translator emits the same C
  construct (its output under `compare/work`, its source in `/root/c2das`, both read-only), and
  what daslang's options, JIT and AOT flags and dasProfile (daScript's own benchmark method,
  `perf/ARCHITECTURE.md` section 6) do for that construct. Our own idea comes after the pass.
- The same item or answer then profiles the native C build and the slow lane with `perf/sampler`
  and shows, second, the top functions by self time, each with its share of the run and its
  lane-to-native time ratio. A per-construct cost table is built only for a function in that list.
- Every `perf/sampler` profile of the interpreter lane that a report shows or a commit adds also
  gets a das-level profile that names das functions and lines: daslang's own profiler, or
  `perf/sampler` with das line attribution when that profiler cannot run the program.
- Before a run whose numbers a report will quote (an item's A/B, a phase-end re-capture), the
  expected value of every number the report will quote is written with one line of reasoning: for
  an item in its row of `docs/implementation_order.md`, in a commit made before the run; for a
  phase-end re-capture in the capture's predictions file, dated before the run and named by the
  report. The report shows each expected value beside the measured one, one line on the cause of
  every miss over 25%, and the hit rate: the share of numbers within 25% of their prediction.
- A run whose numbers a report quotes (a perf capture, `compare --perf`, an A/B, Doom fps, the
  ports publish's timing) runs as `heavy --exclusive --label TIMING-<item>-<what> ...` (owner rule
  2026-11-06): it waits for every other job to end and for a quiet CPU, then runs alone; its stderr
  says `machine quiet` or `NOT quiet`. A number from a run that was not exclusive, or not quiet, is
  not quoted as a result. Builds and conversions run before it as ordinary heavy jobs.
- The last pull request of a phase also commits, under `perf/profiles/`, a top-10 self-time
  profile of the native build and of each lane in the speed tables, for each of Lua fib, Lua
  nbody, Doom demo1 and every compare project, so that a change in where the time goes shows up
  like a change in speed.
- A pull request merges only when the `preflight` check is green AND the pull request's review
  pass is closed with no BLOCKING or MAJOR finding open; a green check never overrides an open
  review.
- Every pull request gets one review pass plus a re-check of each BLOCKING or MAJOR fix. A pull
  request that does not close a phase runs no per-document dragon audit.
- Every pull request runs, before it is opened, the fast tier (`scripts/preflight.sh`) and the
  suites of the folders its diff touches by this map; a diff touching several folders runs the
  union. A subset runs as `PREFLIGHT_TEST_GROUPS="<suite>;<suite>" scripts/preflight.sh --only
  tests`, the suites in parallel (`skills/internal/preflight.md`).

  | The diff touches | Suites |
  |---|---|
  | `converter/` (or adds a plan item's feature) | `converter/tests`, `lua/tests`, `doom/tests`, gcc-torture, c-testsuite, csmith |
  | `c_runtime/`, `dasCRuntime/` | `c_runtime/tests`, `dasCRuntime/tests`, `probes`, `converter/tests` |
  | `probes/` | `probes` |
  | `perf/` | `perf/tests` |
  | `ports/` | `ports/tests` |
  | `metrics/` | `metrics/tests` |
  | `lua/` | `lua/tests` |
  | `doom/` | `doom/tests` |
  | `compare/` | `compare/tests` |
  | `suites/` | `converter/tests` (the runners' tests) and the C suite whose runner changed |
  | `tests/`, `scripts/` | the full tier, `scripts/preflight.sh --full` |

  The full tier also runs once at the start of each night on clean `main`, so a red already on
  `main` shows before it blocks a pull request, and in the last pull request of a phase.
  gcc-torture, c-testsuite and csmith run under `heavy --low`, never beside a build: a csmith
  seed times out under load.
- The last pull request of a phase runs `scripts/preflight.sh --full`, a dragon-agent audit of
  every `REVIEW*.md`, `ARCHITECTURE*.md` and `AGENTS.md` the phase changed, an archivist pass
  over each of those architecture documents, the dupe-sweeper and style-hygiene audits over the
  phase's new code, and `scripts/run_perf.sh --readme`, which re-records
  `perf/results_linux.json`.
- Closing a phase is an annotated tag `v0.<phase>.0` with a GitHub release carrying the suite
  counts and the perf and readability numbers at that commit, and the ports repository
  (`lookibed/c2das-ports`) regenerated from that tag with `bash scripts/publish_ports.sh --commit
  --push`, and the list of open branches and pull requests with the reason each one exists; the
  phase is closed only with the tag, the release, the regeneration and the list done.
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
- A lesson about the box, the tools or the method that a later session needs is written to the
  session's memory file in the same session, not only into a report. For Claude Code that is the
  project's auto-memory `MEMORY.md` and the notes it links.
