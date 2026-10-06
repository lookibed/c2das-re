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
  from dasClangBind join here when records enter the subset.
- `emit.das` - the emitter: `CirTu` in, gen2 text out, fails closed the same way. The
  lowering passes of the plan (type resolve and rename, promotion insertion,
  statement-ification, control flow) grow as their own files that transform a `CirTu`
  before emission; the emitter itself only spells nodes.
- `pipeline.das` - `convert(c_path, out_dir, target)`: dump, write the C-IR, read it back and
  rewrite it (the bytes must match), emit, format with `daslib/das_source_formatter`,
  compile-check with `compile_file`. Every artifact lands under `out_dir`.
- `tiers.das` - `run_tier(das_path, tier, work_dir, output[, module_dirs])`: the process exit
  code of the module under `interp`, `jit`, `exe` or `aot` (section 5); `module_dirs` are
  passed as `-load_module` to the interpreter and the JIT.
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
typedefs and `_GUID`) and every declaration whose location is another file (a header's).
Locations come from `loc`, else `range.begin`; clang omits `file` and `line` when they
repeat the previous node's, so the dumper carries the last seen values forward in tree
order, starting from the main file. Types are interned by a structural key
(`int:32:true:int`, `ptr:3`, `func:0:1,2:false`) in first-use order, which is the spec's
order. Type spellings come from `desugaredQualType` when clang gives one, else `qualType`,
with `const`, `volatile`, `restrict` and `__attribute__` text stripped: the C99 scalar names,
`_Bool`, `T *`, `T[N]`, `R (P, ...)` function types and `R (*)(P)` pointers to functions.
Widths follow the selected dialect (`msvc`: int 32, long 32, long long 64; `linux`: long
64); plain `char` is unsigned in both (`docs/probe-findings.md` F17), which the dumper
enforces with `-funsigned-char`. A file-scope `static` gets the TU-qualified name
`<stem>__<name>` and a local `static` is hoisted into `decls` as `<fn>_<name>` with
`from_func`; references use the hoisted name. Tentative definitions of one object merge
into the declaration carrying the initializer.

Declarations: `FunctionDecl` with `ParmVarDecl` and a `CompoundStmt` body, `VarDecl`.
Statements: compound, `DeclStmt` (one `decl` per variable), expression statements,
`if`, `while`, `do`, `for` (its five slots, an absent one spelled `{}`), `break`,
`continue`, `return`, the null statement. Expressions: integer, character, floating (as a
hex-float through the CRT) and string literals (C escapes decoded, the NUL appended),
`DeclRefExpr`, every pinned cast, the unary, binary, compound-assignment, conditional and
comma operators, calls, subscripts, `sizeof`. Anything else is an error naming the node
kind and its location: records, typedefs, enums, initializer lists, `goto`, `switch` are
the next phases' rows.

## 4. What the emitter spells

The module opens with the generated banner, `options gen2`, `options indenting = 4` and one
`require c_runtime/<name>` per piece the body reached (`printf`, `c_exit`, `c_function`).
Globals come first (`var`, `var private` for a C `static`, the initializer inline and under
`unsafe(...)` when it takes an address), then the functions. A function is
`def name(p : T; ...) : ret` with `private` for a C `static`; a parameter the body writes
is declared `p_in` with `var p = p_in` as the first statement, the callee copy C's by-value
rule needs, since a das parameter is a reference. A body that used an unsafe operation
(pointer arithmetic, `deref`, `addr`, a `reinterpret`, a string literal) gets
`[c_function]`. C `main` becomes `c_main` and the module ends with
`[export] def main : int { return c_main() }`, whose `return` is the CLI's exit-code
contract (`docs/probe-findings.md` F1). A C name that is a das keyword takes the `_c_`
prefix.

Expressions carry the C-IR casts: `IntegralCast` and the floating casts are the workhorse
cast, `IntegralToBoolean` is `x != 0` (`!= null` for a pointer), `BooleanToSignedIntegral`
is `b ? 1 : 0`, a comparison or `!` is spelled as the das bool it is and becomes `? 1 : 0`
only where C reads it as an int. Literals carry their suffix from the C-IR type (`u`, `l`,
`ul`, `lf`, `f`), small integers wrap in a cast. A compound assignment whose operand types
differ expands to `lhs = T_lhs(T_rhs(lhs) op rhs)`, which is C's small-int rule
(`b = int8(int(b) + 1)`). Statement-ification happens at emission: an assignment, a step
or a call met inside an expression is hoisted into the statements before the current one
(`let _t0 = x` then `x++` for a postfix step), left to right; a comma is two statements;
`&&` and `||` with a hoisted right side become a flag and an `if`; a ternary whose arm
carries hoisted statements becomes `var _tN : T` and an `if`/`else`, while a ternary of
pure arms stays inline since das `?:` evaluates only the taken arm (F18). Loops follow the
documents: `while` is `while`, with a side-effecting condition spelled `while (true)` plus
the test and `break`; `do` is the `_first` flag; `for` is a bare block holding the
initializer, the `_f` flag and `while (true)` with the increment first; `if` chains spell
`elif` when the nested condition is pure. Function pointers, records, arrays beyond
subscripts, string literals outside a pointer context (the empty literal included, F10) and
calls to external functions without a `c_runtime` mapping are errors until their lowering
lands (`docs/implementation_order.md`, P2 onward).

Output is assembled as an array of lines joined once (`docs/probe-findings.md` F19); the
text then goes through the formatter, so spacing is the formatter's and indentation is the
emitter's, four spaces per depth.

## 5. The four tiers

`interp` runs `daslang <module>`, `jit` runs `daslang -jit <module>`, `exe` runs
`daslang -exe <module> -output <work>/<stem>_exe` and executes the binary (the JIT names it
`.exe` on every platform), `aot` runs `daslang utils/aot/main.das -- -ctx <module> <work>/ctx/`
and compiles the generated context with a seven-line C host (`<stem>_create`, `<stem>_main`,
`<stem>_destroy` from the generated header) against the static runtime: `liblibDaScript.a`,
`liblibDaScript_runtime.a`, `liblibUriParser.a`, with the checkout's ABI flags (no RTTI,
`DAS_FUSION=2`, `SIZE_OF_VOID_P=8`). The AOT tier links no C++ module yet; when converted code
requires `crt`, its static archive joins the link. The interpreter and JIT tiers take the
module folders to load from the caller (`suites/c_testsuite/run.das` passes both). The exit code is the program's own on every tier, which is why the wrapper
returns from `main`.

## 6. Exception ledger

Empty.
