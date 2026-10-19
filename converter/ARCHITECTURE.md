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
- `bit_units.das` - the layout law over the C-IR (section 2, `packed`): `type_size`,
  `natural_align` (a record's is its das mirror's, which can be below clang's, F5),
  `natural_layout` (the dumper's `packed` verdict), `bit_units` (the allocation units that cover
  a record's bitfields), `union_flaw` (why a union is not natural), `union_member_layout` (the
  size and alignment a bare `[c_union]` derives), `record_under`/`element_under` (the type at
  an array's bottom) and `is_storage_bitfield`. Every answer about a record lands in a
  `LayoutMemo` the dumper and the emitter each own, so a nest of records is measured once per
  record; a unit search never retries a failed state (field, offset, alignment so far). Nothing
  here knows clang or das syntax.
- `sidecar.das` - the per-project `.c2das` file as a `Sidecar` value: `find_sidecar` (the
  path given, else `<stem>.c2das` beside the C file, else `.c2das` in its folder) and
  `read_sidecar` (JSON; a key the row that needs it adds - `marshal`, the records read and
  written as bytes). Nothing here knows the C-IR or the emitter.
- `pipeline.das` - `convert(c_path, out_dir, target[, clang, sidecar])`: dump, write the C-IR,
  read it back and rewrite it (the bytes must match), read the sidecar, emit, format with
  `daslib/das_source_formatter`, compile-check with `compile_file`. Every artifact lands under
  `out_dir`; `file_stem` is the name every artifact of a C file carries.
- `tiers.das` - `run_tier(das_path, tier, work_dir, output[, module_dirs[, timeout[,
  flags]]])`: the process exit code of the module under `interp`, `jit`, `exe` or `aot`
  (section 5); `module_dirs` are passed as `-load_module` to the interpreter and the JIT, `flags`
  before the script, and a run past `timeout` seconds (600 by default) is killed and reported
  as a failure. `CONVERTED_MODULES` names the module folders a converted program requires and
  `daslang_cmd` spells the prefix; `native_run` builds a C file with a given compiler and flags
  and runs it once, the native side every differential test compares against.
- `main.das` - the CLI (`daslib/clargs`): `c2das <file.c> [--out] [--target] [--run] [--sidecar]`.
- `benchmarks/bench_for_shapes.das` - the loop-shape race behind section 4
  (`ARCHITECTURE_EMITTER.md`), run with `dastest -- --bench` under the interpreter and
  under `-jit`.
- `tests/test_lowerings.das` - the P1 fixtures under `tests/fixtures/p1_*.c`, each converted
  and run against the native build of the same file by the pinned clang (output and exit
  code), plus the lowering shapes the text must carry.
- `tests/test_csmith_verdict.das` - the csmith driver's classification of a worker that ended
  (`suites/csmith/verdict.das`), the one piece of the driver testable without a process.
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

A record's `packed` is false exactly when das's natural layout reproduces clang's, by this law
(`bit_units.das`), which a Dumper B applies to the same facts to write the same byte. Fields go
in declaration order, each at its offset rounded up to its das alignment (a scalar's size, an
array's element's, a nested record's das alignment as this law found it, or clang's for a
record it finds packed); a flexible array member (an array of count -1 that ends the record)
adds no bytes. An unnamed or zero-width bitfield never opens a storage unit. The first named
bitfield not yet covered opens an unsigned unit of its declared type's size first, then of 1,
2, 4 and 8 bytes in that order, at the next offset that size divides; every following bitfield
whose bits lie inside the unit joins it, and when the rest of the record then misses a clang
offset or clang's size the search backtracks to the next size. The end, rounded up to the
largest alignment met, must be clang's size, and that alignment must be the target: clang's
alignment first, then each power of two below it, the first target that works winning. A target
below clang's is tried only when the record has a named bitfield of nonzero width or a field
whose record (through arrays) won below its clang alignment, and when clang's alignment is the
one the record would have without an alignment attribute: the largest of its named bitfields'
declared types, its other fields' das alignments and a nested record's clang alignment. A union
is natural when it has a member, every member sits at offset 0, clang's alignment is 1, 2, 4 or
8 and divides its positive size, and every member fits it: a member's das alignment (as this
law finds it) at most clang's alignment, its size at most clang's size, and a member record
(through arrays) natural itself; `[c_union]` then gives the storage clang's size and alignment,
so a natural union's das alignment is clang's even where its members align lower (a member
record below its clang alignment, F5; an `aligned` attribute up to 8). An anonymous member (a
struct or union member with no declarator) is a field named `""` that is not a bitfield: its
`t` is the anonymous record, its `off` the byte offset clang gives it, and it carries no
`bit_w`. In an `init_list` of a record, `pos` is the field index; an unnamed bitfield is never
an item, and a union's list holds at most one item, `pos` the member it initializes (none for
`{}`). A record spelling carries no owner scope: `union S::(anonymous at f:l:c)` interns as
`union (anonymous at f:l:c)`, the spelling libclang and the dump share.

A C `va_list` is one opaque record named `va_list`, this repository's choice as `jmp_buf` is
(the spec has no type for it, `docs/probe-findings.md` F39), and Dumper B writes the same bytes:
one field `words`, an `unsigned long long[N]`, at clang's size and alignment, `N` 3 under
`linux` (`struct __va_list_tag[1]`, 24 and 8) and 1 under `msvc` (a `char *`, 8 and 8),
`packed` false, `spell` `va_list` (a C record tagged `va_list` spells `struct va_list`, which is
how the two are told apart). A `va_list` parameter is clang's type for it: the record under
`msvc`, a pointer to the record under `linux`, whose `struct __va_list_tag *` is the decayed
array. The lowering never lays the record out (`sizeof(va_list)` is clang's size). The
`va_arg` node is the spec's: `list` the list's expression (the decay under `linux`, the
variable under `msvc`) and `arg_t` the type read, which is also the node's `t`. `va_start`,
`va_end` and `va_copy` stay calls to the builtins they expand to (`__builtin_va_start`,
`__builtin_va_end`, `__builtin_va_copy`), as every `__builtin_*` call does (F23).

Section 3, Dumper A's subset (what the dumper reads from clang and libclang), is in
`ARCHITECTURE_DUMPER.md`.

Section 4, what the emitter spells (the das text of every construct), is in
`ARCHITECTURE_EMITTER.md`, with bitfields, unions, function pointers and variadics in
`ARCHITECTURE_EMITTER_AGGREGATES.md`.

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
