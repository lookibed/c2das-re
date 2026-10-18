# converter Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The
folder is the daslang program that turns C into gen2 daslang: Dumper A, the C-IR model, the
emitter, the pipeline that chains them, and the tier runner the gate and the suites use. The
normative design is `docs/very-detailed-plan.md` (sections 4 and 5) and the expected output is
`docs/lowering-examples.md`; this document states only what the code here is.

## 1. File charters

- `cir.das` - the C-IR of `docs/c-ir-spec.md` as das values (`CirTu`, `CirType`, `CirDecl`,
  `CirStmt`, `CirExpr`, one struct per spec table), the canonical writer `write_cir`, the
  reader `read_cir`, the pinned `CAST_KINDS`, the two dialects. Nothing here knows clang or
  daslang syntax. A tree is owned through plain pointers and freed by one `delete` of its
  root: the generated finalizer recurses through pointer fields and arrays of pointers
  (`probes/test_delete.das`), so no hand-written walk frees a child.
- `dumper_a.das` - Dumper A: runs `clang -Xclang -ast-dump=json -fsyntax-only -target
  <triple>` on one file and normalizes the JSON into a `CirTu`. Fails closed: the first
  construct outside what it represents sets `Dumper.error` with `file:line:col`. Layout facts
  come from a libclang pass over the same file (`ARCHITECTURE_DUMPER.md`, section 3).
- `emit.das` - the emitter: `CirTu` in, gen2 text out, fails closed the same way. The
  lowering passes of the plan (type resolve and rename, promotion insertion,
  statement-ification, control flow) happen as it spells nodes (`ARCHITECTURE_EMITTER.md`,
  section 4); no pass transforms the `CirTu` before emission.
- `sidecar.das` - the per-project `.c2das` file as a `Sidecar` value: `find_sidecar` (the
  path given, else `<stem>.c2das` beside the C file, else `.c2das` in its folder) and
  `read_sidecar` (JSON; a key the row that needs it adds - `marshal`, the records read and
  written as bytes). Nothing here knows the C-IR or the emitter.
- `pipeline.das` - `convert(c_path, out_dir, target[, clang, sidecar])`: dump, write the C-IR,
  read it back and rewrite it (the bytes must match), read the sidecar, emit, format with
  `daslib/das_source_formatter`, compile-check with `compile_file`. Every artifact lands under
  `out_dir`.
- `tiers.das` - `run_tier(das_path, tier, work_dir, output[, module_dirs[, timeout]])`: the
  process exit code of the module under `interp`, `jit`, `exe` or `aot` (section 5);
  `module_dirs` are passed as `-load_module` to the interpreter and the JIT, and a run past
  `timeout` seconds (600 by default) is killed and reported as a failure.
- `main.das` - the CLI (`daslib/clargs`): `c2das <file.c> [--out] [--target] [--run] [--sidecar]`.
- `benchmarks/bench_for_shapes.das` - the loop-shape race behind section 4
  (`ARCHITECTURE_EMITTER.md`), run with `dastest -- --bench` under the interpreter and
  under `-jit`.
- `tests/test_lowerings.das` - the P1 fixtures under `tests/fixtures/p1_*.c`, each converted
  and run against the native build of the same file by the pinned clang (output and exit
  code), plus the lowering shapes the text must carry.
- `tests/test_pipeline.das` - the P0 gate: `tests/fixtures/ret42.c` converts, the C-IR and the
  das text hash to their golden values, and the module exits 42 under all four tiers.
  Fixtures under `tests/fixtures/` are C inputs, never das.

## 2. The C-IR bytes

`write_cir` is the one canonical spelling of the spec's section 8, and Dumper B must produce
these bytes for the byte-diff to mean anything: an object opens with `{` and a newline, every
member sits on its own line indented one space per depth as `"key": value`, members are
separated by `,` at the end of the line, the closing `}` sits at the parent's depth; an array
of scalars is one line `[1, 2, 3]`; an array of objects opens with `[` and a newline, holds
one object per line at the inner depth, and closes with `]` at the parent's depth; an empty
array is `[]`; keys follow the spec's table order; `null` spells an absent optional node; a
string is JSON-escaped by `write_json`; the file ends with one LF. The reader accepts any
JSON spelling; the pipeline proves the pair by rewriting what it read and comparing. One
node is this repository's addition to the spec's table: `offsetof` with `of_t` and `field`
(the record type and the field index), since the lowering spells `offsetof` as
`typeinfo offsetof` and the spec has no node for it (`docs/probe-findings.md` F20). The other
addition is `dims` on a `global`, a `decl` statement and a record field: one `{enum_t, item}`
per array dimension of the declarator, outermost first, the item empty for a dimension not
spelled as one enum constant, the member absent when none is, since the lowering keeps the
constant as the dimension and the spec's `count` is the folded integer (F21). The spelling is
a fact about the declarator, not the type, so the type table interns `T[6]` once however the
source wrote it. An `enum` type carries `"signed": false` when clang gave it an unsigned
underlying type (F22); the member is absent for a signed one, which is every enum of the
`msvc` dialect.

Section 3, Dumper A's subset (what the dumper reads from clang and libclang), is in
`ARCHITECTURE_DUMPER.md`.

Section 4, what the emitter spells (the das text of every construct), is in
`ARCHITECTURE_EMITTER.md`.

## 5. The four tiers

`interp` runs `daslang <module>`, `jit` runs `daslang -jit <module>`, `exe` runs `daslang -exe
<module> -output <work>/<stem>_exe` and executes the binary (the JIT names it `.exe` on every
platform), `aot` runs `daslang utils/aot/main.das -- -ctx <module> <work>/ctx/` and compiles
the generated context with a seven-line C host (`<stem>_create`, `<stem>_main`,
`<stem>_destroy` from the generated header) against the static runtime: `liblibDaScript.a`,
`liblibDaScript_runtime.a`, `liblibUriParser.a`, with the checkout's ABI flags (no RTTI,
`DAS_FUSION=2`, `SIZE_OF_VOID_P=8`). The AOT tier links no C++ module, so a module that
requires `crt` runs under the interpreter and the JIT (`docs/implementation_order.md`, P7.3).
The interpreter and JIT tiers take the module folders to load from the caller
(`suites/c_testsuite/run.das` passes both). The exit code is the program's own on every tier,
which is why the wrapper returns from `main`.

## 6. Exception ledger

Empty.
