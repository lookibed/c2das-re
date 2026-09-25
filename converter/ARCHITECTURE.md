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
  daslang syntax.
- `dumper_a.das` - Dumper A: runs `clang -Xclang -ast-dump=json -fsyntax-only -target
  <triple>` on one file and normalizes the JSON into a `CirTu`. Fails closed: the first
  construct outside what it represents sets `Dumper.error` with `file:line:col`. Layout facts
  from dasClangBind join here when records enter the subset.
- `emit.das` - the emitter: `CirTu` in, gen2 text out, fails closed the same way. The
  lowering passes of the plan (type resolve and rename, promotion insertion,
  statement-ification, control flow) grow as their own files that transform a `CirTu`
  before emission; the emitter itself only spells nodes.
- `pipeline.das` - `convert(c_path, out_dir, target)`: dump, write the C-IR, read it back and
  rewrite it (the bytes must match), emit, format with `daslib/das_source_formatter`,
  compile-check with `compile_file`. Every artifact lands under `out_dir`.
- `tiers.das` - `run_tier(das_path, tier, work_dir, output)`: the process exit code of the
  module under `interp`, `jit`, `exe` or `aot` (section 5).
- `main.das` - the CLI (`daslib/clargs`): `c2das <file.c> [--out] [--target] [--run]`.
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
JSON spelling; the pipeline proves the pair by rewriting what it read and comparing.

## 3. Dumper A's subset

The dumper walks `TranslationUnitDecl.inner`, skipping `isImplicit` nodes (clang's builtin
typedefs and `_GUID`). Locations come from `loc`, else `range.begin`; clang omits `file` and
`line` when they repeat the previous node's, so the dumper carries the last seen values forward
in tree order. Types are interned by a structural key (`int:32:true:int`, `ptr:3`,
`func:0:1,2:false`) in first-use order, which is the spec's order. Type spellings come from
`qualType` strings: the C99 integer and floating names, `_Bool`, `T *`, and `R (P, ...)`
function types; widths follow the selected dialect (`msvc`: int 32, long 32, long long 64;
`linux`: long 64). A file-scope `static` gets the TU-qualified name `<stem>__<name>` with
`c_name` keeping the C spelling. Declarations: `FunctionDecl` with `ParmVarDecl` and a
`CompoundStmt` body. Statements: `CompoundStmt`, `ReturnStmt`. Expressions: `IntegerLiteral`,
`ImplicitCastExpr` and `CStyleCastExpr` with a pinned `castKind`, `ParenExpr` (dropped, C-IR
has no parentheses). Anything else is an error naming the node kind and its location.

## 4. What the emitter spells

The module opens with the generated banner, `options gen2` and `options indenting = 4`. A
function is `def name : ret {` with `private` for a C `static`; C `main` becomes `c_main`
and the module ends with the wrapper `[export] def main : int { return c_main() }`, whose
`return` is the CLI's exit-code contract (`docs/probe-findings.md` F1: `exit()` cannot carry
it). Integer literals carry their das suffix from the C-IR type (`u`, `l`, `ul`), small
integers wrap in a cast (`int8(1)`), `_Bool` literals are `true`/`false`. `LValueToRValue`
and `NoOp` casts emit their operand; `IntegralCast` emits the workhorse cast. Parameters,
globals, every other statement and expression, and the other cast kinds are errors until
their lowering lands (`docs/implementation_order.md`, P1 onward). The text goes through the
formatter, so spacing is the formatter's; indentation is the emitter's, four spaces per depth.

## 5. The four tiers

`interp` runs `daslang <module>`, `jit` runs `daslang -jit <module>`, `exe` runs
`daslang -exe <module> -output <work>/<stem>_exe` and executes the binary (the JIT names it
`.exe` on every platform), `aot` runs `daslang utils/aot/main.das -- -ctx <module> <work>/ctx/`
and compiles the generated context with a seven-line C host (`<stem>_create`, `<stem>_main`,
`<stem>_destroy` from the generated header) against the static runtime: `liblibDaScript.a`,
`liblibDaScript_runtime.a`, `liblibUriParser.a`, with the checkout's ABI flags (no RTTI,
`DAS_FUSION=2`, `SIZE_OF_VOID_P=8`). The AOT tier links no C++ module; when converted code
requires `crt`, its static archive joins the link and the interpreter tiers add
`-load_module`. The exit code is the program's own on every tier, which is why the wrapper
returns from `main`.

## 6. Exception ledger

Empty.
