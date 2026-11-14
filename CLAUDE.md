# c2das-re Project Instructions

## Project Overview

A C-to-daslang converter written in daslang: libclang frontend, the C-IR interchange format
in the middle, gen2 daslang out. The design is complete and normative before the code: read
`docs/very-detailed-plan.md` first, then `docs/implementation_order.md` (the work items,
executed in order), with `docs/lowering-examples.md` and `docs/stdlib-examples.md` open -
they contain the expected output for every construct. When code and the documents
disagree, one of them is a bug: stop and resolve it deliberately, usually with a probe.

The predecessor `/root/c2das` (Rust, a C2Rust fork) is Dumper B of the C-IR contract and a
record of problems; it is never a template for code, pipeline or structure. This
repository is developed the way daScript (`DASLANG_ROOT`) is: the same document system,
agents, review round and preflight discipline.

## Toolchain

`DASLANG_ROOT` (`scripts/env.sh`, default `/root/daScript`) is a daScript checkout built in
place with dasClangBind, dasStdDlg, dasHV and dasLLVM, at or past the commit `VERSIONS.md`
pins. `scripts/verify_daslang.sh` names anything missing. Nothing else of daScript is
vendored: `bin/daslang` runs the code, `dastest/` runs the tests, `utils/lint`, `utils/das-fmt`
and `utils/internal/review-md` are the gates, `bin/watchdog` fronts MCP, LSP and DAP. A
rebuild of daScript that changes a requirement here (a module, a flag, a pin) updates
`VERSIONS.md` in the same change.

Run a script: `$DASLANG_ROOT/bin/daslang converter/main.das -- <args>`. Run a suite:
`$DASLANG_ROOT/bin/daslang $DASLANG_ROOT/dastest/dastest.das -- --test probes`. Anything that
`require crt` (the native module under `dasCRuntime/`, built by `scripts/build_crt.sh`) or
`require c_runtime/<name>` needs `-load_module $PWD/dasCRuntime -load_module $PWD/c_runtime`
before the script path; `scripts/preflight.sh` and `.mcp.json` pass both.

## The document system

The document types split one grammar, each with a repo-root contract:

- **`REVIEW.md`** (per folder) - bans and duties binding a diff, applied at review time via
  the folder walk. Contract: `REVIEW_COMMON.md`.
- **`ARCHITECTURE.md`** (per folder) - present-tense statements: how the system is and why.
  Contract: `ARCHITECTURE_COMMON.md`. **Read the folder's architecture doc BEFORE writing
  code there.**

An implementation folder holds no `.md` besides `REVIEW*.md` and `ARCHITECTURE*.md`. Planned
work is a row in a ledger: `docs/implementation_order.md` is this project's ledger, and a
finding that changes it is edited there, never recorded in a code comment. A plan-shaped or
past-tense document does not live in the tree: git keeps it. The mood test routes misplaced
text: must/never binding a diff -> `REVIEW.md`; present-tense fact -> `ARCHITECTURE.md`;
dated or past-tense -> deleted.

**Before editing a function annotated `[arch(at="<doc>.md#<anchor>")]`, read the section it
cites** (MCP `arch_of` locates every citation a file makes; `arch_sites` lists a document's
anchors with their citers). A heading code cites carries the `{#anchor}` its citation names,
and every anchor is cited: LINT026 fails a citation naming no such file or anchor and an
anchor nothing cites. A `REVIEW*.md` or `ARCHITECTURE*.md` past 300 lines splits into
companions (LINT027; the `archivist` agent does architecture-doc splits).

The `docs/` folder is exempt from the mood test: those documents are the normative design,
authored in their own repository (see `docs/overview.md`), dated statements included. A fact that
graduates from `docs/` into code is restated in the owning folder's `ARCHITECTURE.md` and
cited from the code; `docs/` is never edited to match the code.

## MCP-first

The daslang MCP server runs from `DASLANG_ROOT` with this repository as its served tree
(`.mcp.json`): a relative path in any tool resolves against this repository, the `cpp_*`
tools index this tree (the C inputs under `suites/`, `dasCRuntime/`), and `lint` reads
`.lint_config` here. `cpp_compile_check` and `cpp_build_info` take `build_dir` =
`dasCRuntime/_build` (`scripts/build_crt.sh` writes its `compile_commands.json`). Before reaching for `Bash`/`Grep`/`Read` to
find a symbol or trace usages, call the tool that answers the question:

| Question | Tool |
|---|---|
| Does daslib already do this? (before writing ANY helper) | `discover` |
| Where is symbol X defined? (`.das`) | `find_symbol` (`with_cpp_source=true` bridges to C++) |
| Where is X used? (`.das` / C) | `grep_usage` / `cpp_grep_usage` |
| What's in this file? | `outline` / `cpp_outline` |
| All references to X | `find_references` |
| Does it compile, is it clean, is it formatted? | `compile_check`, `lint`, `format_file` |
| Run a file or a suite | `run_script`, `run_test` |

Full tool table and caveats: `skills/mcp_tools.md`. A fresh clone has no MCP until
`.mcp.json` points at a built `DASLANG_ROOT`; the LSP plugin (`.claude/skills/daslang-lsp`)
runs the same checkout's `watchdog --lsp`.

## Skill Files (REQUIRED)

Task-specific instructions live under `skills/`. Read the relevant skill BEFORE the task.
Vendored skills (`skills/README.md`, synced from daScript by `scripts/sync_daslang_skills.sh`)
are never edited here; this repository's own skills are the `skills/internal/*.md` files the
sync script does not list.

| Skill file | Read BEFORE... |
|---|---|
| `skills/daslang/SKILL.md` + `references/` | Writing or reviewing any `.das` code: the language, runtime and stdlib truth |
| `skills/das_formatting.md` | Creating or modifying any `.das` file |
| `skills/comment_style_hygiene.md` | Writing or reviewing comments, names, or local code shape in ANY language |
| `skills/writing_tests.md` | Writing or editing any dastest test (probes, c_runtime tests, converter tests) |
| `skills/das_macros.md` | The `[c_function]`, `[c_union]`, `[c_bitfields]`, `[variadic]` annotation macros and any AST work |
| `skills/daslib_modules.md` | Extending `c_runtime/` as a daslang module |
| `skills/dynamic_modules.md` | The `.das_module` descriptor of `c_runtime/` and `dasCRuntime/` |
| `skills/cpp_integration.md` | `dasCRuntime/` - binding the CRT (`addExtern` only) |
| `skills/internal/clang_bind_build.md` | Anything touching the dasClangBind build or libclang version |
| `skills/mcp_tools.md` | Using or debugging the MCP tools |
| `skills/review_md.md` | Creating or editing any `REVIEW.md`, or reviewing a diff to one |
| `skills/tdd_audit.md` | Auditing any diff for test coverage - the branch-test rule |
| `skills/dupe_audit.md` | Auditing a diff for duplicated or parameterizable code; before claiming a helper is new |
| `skills/internal/preflight.md` | Running the gates, reproducing a red one |
| `skills/internal/make_pr.md` | Creating a pull request (the whole pre-PR checklist) |
| `skills/internal/review_round.md` | The multi-agent deep review of a branch or diff |
| `skills/internal/babysit.md` | Babysitting an open PR through CI and review feedback |
| `skills/internal/review_triage.md` | Triaging any review comment on a PR |
| `skills/internal/woodpecker.md` | Running the external codex reviewer on a branch |
| `skills/internal/writing_skills.md` | Adding a `skills/internal/*.md` file |
| `skills/writing_benchmarks.md` | The perf table: benchmark `.das` files |
| `skills/memory_leak_detection.md`, `skills/profiler.md` | Any leak report at exit; runtime profiling |

### Updating instructions with new knowledge

A compiler error, probe, or user correction showing a claim in this file or a skill written
here is wrong gets fixed in place, in the same session, and flagged in the end-of-turn
summary. A wrong claim in a vendored skill is fixed upstream in daScript and re-synced. A
das-fact the converter relies on is a probe in `probes/`: a probe that contradicts a document
is a finding, reported, never worked around.

**Lint opportunities are reportable findings.** A pattern a mechanical check could catch
lands as a `REVIEW.das` gate in the folder that owns it, or is proposed as a daScript lint
rule; say so in the end-of-turn summary.

## Gates

`scripts/preflight.sh` (`skills/internal/preflight.md`) runs the fast tier - `env`, `native`,
`untracked`, `format`, `lint`, `compile`, `ast-verify`, `md-ascii`, `review-md`, `criteria` (a
report) - and with `--full` the `tests` lane over every dastest suite. `--only <gate>` reruns
one, `--list-gates` prints the table. The suites' pass counts are a ratchet: a count only goes up, and every
skipped suite test carries a ledger line naming the feature, the reason and the phase that
unblocks it (`suites/`).

## GitHub Operations

Use the GitHub MCP tools when available; otherwise `gh` with `--body-file` for any text with
backticks. Commits and PRs are authored by the user alone: no `Co-Authored-By` trailer, no
"Generated with" footer, no session links. The babysit driver is daScript's
`utils/internal/pr-babysit/main.das` with `--repo <owner>/c2das-re` (`skills/internal/babysit.md`),
run bare in a background Bash; the hook in `.claude/settings.json` denies hand-rolled watchers.

## Workspace Hygiene

`AGENTS.md`. Converted output is generated, never hand-edited, never committed: it lives under
`out/` (gitignored) or a suite's work folder; golden output is recorded as hashes.

## daslang Language

Language, runtime and stdlib truth is `skills/daslang/`. Two lists daScript keeps in its own
`CLAUDE.md` are house rules here too, read them at `$DASLANG_ROOT/CLAUDE.md`, section
"daslang Language": the shapes that **fail silently** (a `+`/`-` continuation line, `delete`
on `array<T?>`, `:=` on a string, `is`/`as` on handled types, `tab[k]` inserting on read,
`to_int` on garbage, argument evaluation order) and the **idiom table** the lint suite
enforces. `print` is for user-facing scripts only; tools and tests use `to_log`, whose `LOG_INFO` lines show
only under `DAS_LOG_LEVEL=info` (daslang's floor is `warning`; `scripts/env.sh` sets it).

Converter-specific: the converter emits `struct`, never `class`; generated modules carry the
generated banner and relaxed lint options; C strings are `uint8` bytes, never das `string`;
no C data ever lives on the das GC heap (`docs/stdlib-examples.md`, the GC ruling).
