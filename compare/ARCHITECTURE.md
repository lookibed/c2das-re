# compare Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the head-to-head of ledger item P8.1: c2das-re against the Rust translator lookibed/c2das
on the same inputs - the three suites, the perf kernels, Lua and, once P6 exists, PureDOOM - with
the same runner, oracle and machine for both. The Rust translator is a C2Rust fork that writes
daslang; this repository never builds it inside a test and never vendors it.

## 1. File charters

- `rust_translator.das` - the Rust translator as a child process: where its binary is, the
  commit its checkout is at, a translation of one C file (`translate_file`) or of a compilation
  database (`translate_db`) into a `RustTranslation`, the compilation database writer for a list
  of C files (`write_compile_commands`), and a run of a translation's entry module under one
  execution tier (`run_translation`). It classifies nothing and reads no suite.
- `tests/` - `test_rust_translator.das`, the module over a stand-in translator: a shell script
  the test writes that records its argv, prints the real banner, and writes, refuses, stays
  silent or sleeps by the name of its input.
- `work/` - gitignored scratch: translations, compilation databases and the runs' builds.

## 2. The Rust translator

A Rust translation is the set of `.das` and `.das.inc` files the binary
`c2dascript-transpile` writes into one output folder for one C program. Its pins are in
`VERSIONS.md`: the lookibed/c2das commit, the rust toolchain its `rust-toolchain.toml` names,
LLVM 18, and the daScript commit lookibed/c2das runs its own output on. That daScript is a fork
commit older than this repository's pin; the Rust side's output runs here on this repository's
daScript, so both sides run on one daslang.

`scripts/build_c2das_rust.sh` clones the checkout when it is absent, refuses one at another
commit than the pin unless `--allow-other`, checks rustup, the toolchain and `llvm-config-18`,
and builds the release binary; `--check` builds nothing. The binary the module runs is
`$C2DAS_RUST_BIN`, else `target/release/c2dascript-transpile` under `$C2DAS_RUST`, else under
`/root/c2das` (`rust_binary`). The commit a capture records is the `HEAD` of the git work tree
holding the binary, accepted only when that tree has `c2dascript-transpile/Cargo.toml`
(`rust_version`).

## 3. The entry module {#entry}

Under `--libc std` the translator renames C's `main` to `main_0` and adds a wrapper,
`[export] def main() : int`, that turns the daslang command line into C's `argc` and `argv`
and calls `main_0` (at the pinned commit: `c2dascript-transpile/src/translator/functions.rs`
lines 315-322, `translator/libc.rs` `build_main_wrapper` at line 5792 and its declaration named
`main` at line 6020). A C `main` with more than two parameters is refused under `--libc std`
(`translator/libc.rs` line 1541). The printer writes every function as `def <name>(<params>)`,
parentheses always (`das_ast/src/stmt.rs` lines 245-250), so a line opening `def main(` marks
the wrapper and a line opening `def main_0(` does not.

The module daslang runs is `<output folder>/<stem>.das`, where `<stem>` is the stem of the file
holding the wrapper. One C file under `--file` becomes `<output folder>/<file name>.das`
(`lib.rs` `output_path_for`, lines 569-581). Under `--module-layout source` a unit outside any
cycle is its own `<stem>.das`, and a unit in a cycle is a fragment `<stem>.das.inc` included by
its cluster module; the cluster holding C `main` takes the entry unit's stem as its name
(`lib.rs` lines 1224-1230). Both cases give the same rule.

Since the wrapper is daslang's default entry `main`, no `-main` is passed in any tier. The
wrapper takes C's arguments from after a `--`, else from after the script, so
`converter/tiers.das`'s `run_tier`, which passes `--` before the program's arguments and nothing
when there are none, runs a Rust translation unchanged. A Rust translation requires only
daslib and its own modules, so it runs with no module folder loaded.

## 4. The command line {#command-line}

`translate_file` runs `<bin> --file <c> --libc std --strict --output-dir <out> <flags> <clang
args>`; `translate_db` runs `<bin> <compile_commands.json> --libc std --strict --module-layout
source --runtime-module <name> --output-dir <out> <flags>`. The translator takes each of its own
options from anywhere in its argv and drops every `--` before handing the rest to clang
(`c2dascript-transpile/src/main.rs` lines 295-298 and 311-314, `take_flag` and `take_value` at
lines 326 and 410), so no separator is passed: it would protect no clang argument.

The translator prints the banner `c2dascript-transpile v<version>` to stderr first (`main.rs`
line 10), exits 2 with `translation failed: <error>` when a translation fails and 1 on a usage
error (`main.rs` lines 253-321 and 423-441). A `RustTranslation`'s `error` is the first non-empty
line of the merged output that is not the banner, `exit <code>` when there is none, and `timed
out after <seconds> s` past the timeout.
