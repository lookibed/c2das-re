# c2das-re Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The
folder charters are section 1; the pipeline is section 2; definitions section 3; the
toolchain binding section 4; the readability inputs section 5; the exception ledger section 6;
the continuous integration section 7.

## 1. Folder charters

- `converter/` - the daslang program: the C-IR reader, the passes (type resolve and rename,
  promotion insertion, statement-ification, control-flow lowering, escape-hatch
  application), the emitter and its formatter and compile-check calls. Never re-derives C
  semantics the C-IR already carries.
- `c_runtime/` - the daslang module converted programs require: the libc subset, the
  annotation macros (`[c_function]`, `[c_union]`, `[c_bitfields]`, `[variadic]`), `atexit`,
  `alloca`. Grown demand-driven by the suites; every piece lands with an as-if-converted
  fixture test under `c_runtime/tests/` first.
- `dasCRuntime/` - the native glue module `crt`: `addExtern` lines binding the real CRT
  (malloc family, mem*, string.h, libm exotica, errno, time, locale, stdio, rand, getenv, the
  per-directive `snprintf` family) under their C names, qualified `crt::` at every use. No logic; built by
  `scripts/build_crt.sh` and loaded with `-load_module` (`dasCRuntime/ARCHITECTURE.md`).
- `probes/` - the das-facts regression net: one dastest probe per fact the backend relies
  on. Runs first in every test lane.
- `suites/` - fetch scripts, runners, ratchet state and skip ledgers for c-testsuite, GCC
  c-torture `execute` and csmith; fetched inputs and work trees are gitignored.
- `metrics/` - the readability metric: the suites' passing tests and the perf kernels
  converted and counted for `unsafe` scopes and expressions, pointer steps, `reinterpret`
  casts, `goto`, raw `while` loops and unnamed literals, the totals ratcheted in
  `metrics/readability_linux.json` (`metrics/ARCHITECTURE.md`).
- `compare/` - the head-to-head with the Rust translator lookibed/c2das (ledger item P8.1): the
  module that runs its binary and its translations, and the suites, perf, output-quality and Lua
  comparisons over the same inputs, runners and oracles as this repository's own, recorded in
  `compare/results_linux.json` (`compare/ARCHITECTURE.md`).
- `docs/` - the normative design, authored in its own repository and copied here whole
  (`README.md`). Never edited to match code.
- `skills/` - agent instructions: vendored daScript skills (never edited here) and this
  repository's own under `skills/internal/`.
- `scripts/` - `env.sh` (the toolchain variables and `das`, daslang with both module folders
  loaded), `verify_daslang.sh`, `preflight.sh`, `sync_daslang_skills.sh` and the runners
  `run_suite.sh`, `run_perf.sh` and `run_readability.sh`; `build_c2das_rust.sh` builds the Rust
  translator `compare/` runs, at its `VERSIONS.md` pin. Shell only; anything that reads `.das` is a daslang tool from
  `DASLANG_ROOT`.
- `lua/`, `doom/` - vendored programs with their sidecars and harnesses, created by the phases
  that need them (`docs/implementation_order.md`, P5 and P6). `doom/` is the GPL-2 subtree.
- `.claude/agents/` - the agent set, copied from daScript: the auditors (`review-md-auditor`,
  `tdd-auditor`, `dupe-auditor`, `style-hygiene-auditor`, `placement-auditor`), the rule-doc
  judges (`dragon`, `janitor`, `archivist`, `spartan`), the comment `harvester`, the
  `targeted-reviewer` the review round is built from, `flashlight`, `analysis-bot`,
  `dupe-sweeper`. `.claude/hooks/monitor_guard.jq` denies hand-rolled PR watching.

## 2. The pipeline

```
.c files --clang--> TU AST --dump--> C-IR (json) --passes--> das AST text --> formatter --> .das
                                       ^                                            |
                    Dumper A (das): ast-dump=json + dasClangBind layout             v
                    Dumper B (Rust): /root/c2das serializer          compile-check (MCP)
                                       sidecar (.c2das) ------------------> passes
```

The backend consumes C-IR only (`docs/c-ir-spec.md`): resolved types with layout baked in,
every implicit conversion an explicit cast node, constants evaluated, initializers positional.
Two dumpers produce it; their outputs for one TU are byte-identical, which makes every
disagreement a frontend bug with a repro attached. Emission is whole-program: one das module
per C program, split by strongly connected component when a module grows past what the
daslang compiler handles comfortably. All per-project judgment (union policies, marshal
markers, renames, entry points) lives in the sidecar, so the output is
regenerable at will and never hand-edited.

## 3. Definitions

- **C-IR** - the versioned JSON interchange format between a dumper and the backend,
  `docs/c-ir-spec.md`.
- **Dumper** - a program that turns one C translation unit into C-IR. Dumper A is the daslang
  one in `converter/`; Dumper B is the Rust one in `/root/c2das`.
- **Sidecar** - the per-project `.c2das` file that carries every judgment the pipeline cannot
  derive from the C source.
- **Probe** - a dastest case under `probes/` asserting one fact about daslang the backend
  relies on.
- **Ratchet** - a suite pass count that may only grow; each excluded test has a ledger line.
- **Served tree** - this repository, as the daslang MCP server sees it: a relative path in a
  tool resolves against it, the C++ index covers it.
- **As-if-converted fixture** - a hand-written `.das` file shaped exactly as the converter
  will emit it, used to test `c_runtime` and a lowering before the converter produces it.

## 4. Toolchain binding

One daScript checkout, `DASLANG_ROOT` (`scripts/env.sh`), serves everything: the binary
runs the converter and the suites, `dastest` runs the tests, `utils/lint` and `utils/das-fmt`
are the code gates, `utils/internal/review-md` walks the `REVIEW.das` gates, and
`bin/watchdog` fronts the MCP server, the LSP and the DAP bridge with this repository as the
served tree (`.mcp.json`, `.codex/config.toml`, `.claude/skills/daslang-lsp`). The checkout
is built with dasClangBind (the frontend), dasStdDlg (the watchdog's tray), dasHV (the MCP
server's HTTP client) and dasLLVM (the JIT and `-exe` lanes). `VERSIONS.md` pins the commit
and the libclang release; `scripts/verify_daslang.sh` checks the build has every part.
Generic daScript skills are vendored under `skills/` by `scripts/sync_daslang_skills.sh`,
pinned in `skills/DASLANG_SKILLS_PIN`, so the agent definitions under `.claude/agents/`
resolve their `skills/...` paths inside this repository.

## 5. Readability inputs

`metrics/readability_linux.json` counts what the converter makes of a fixed set of C programs,
so it changes when one of those programs or the code converting them changes. The inputs are
each suite's pin in `VERSIONS.md`, what `csmith_program` (`suites/csmith/generate.das`) writes
for a seed, the C text of a kernel under `perf/kernels/`, and the prologue or epilogue
`perf/perf_compose.das` puts around a kernel. The converting code is every `.das` file under
`converter/` outside `converter/tests/` and `converter/benchmarks/`, and every annotation macro
under `c_runtime/c_runtime/`.

## 6. Exception ledger

Empty.

## 7. Continuous integration

CI is `.github/workflows/preflight.yml` on a self-hosted runner (labels `self-hosted`, `c2das`)
installed under `/opt/actions-runner` on a machine that holds the toolchain, as the systemd
service of the dedicated user `gha`, which reads `DASLANG_ROOT` and `PATH_TO_LIBCLANG` through
read-only bind mounts (`/srv/daScript`, `/srv/libclang`; the runner's `.env` names them). A pull
request runs the fast tier of `scripts/preflight.sh`, a push to `main` the full tier. A fork's
pull request never runs there: the job's `if` on the head repository, and the repository setting
that keeps fork workflows off. The repository is private, and GitHub offers branch protection on a
private repository only with a Pro plan, so `main` is protected by the rules of `AGENTS.md`
alone. The runner has no root and no user manager of its own, so a memory cap it grants is
`prlimit`'s (`lua/ARCHITECTURE.md` section 6). The perf check (`.github/workflows/perf.yml`,
`perf/ARCHITECTURE.md` section 6) runs on a second runner, labelled `c2das-fx`, on the machine the
captures name.
