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
  <triple>`, with `-D<entry>` per entry of the sidecar's `defines`, on one file and normalizes
  the JSON into a `CirTu`. Fails closed: the first
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
  written as bytes; `stack` and `alloca_limit`; `param_writes`, `in-place` or `copy`, the
  parameter write mode, any other value refused naming the key; `loops`, `range` or `while`, how
  a canonical counting `for` is spelled, any other value refused naming the key; `defines`, a list of strings
  `NAME`, `NAME=value` or the function-like `NAME(params)=value` (params identifiers separated by
  commas, `...` last) the dump and the libclang pass give clang as one `-D<entry>` argument each,
  a value that is no list or an entry of another shape refused naming the key; `over_indexed`, a list of
  strings `Record.field`, the trailing arrays the program indexes past their length, a value that
  is no list or an entry of another shape refused naming the key, an entry naming no record's
  trailing array the emitter's error). A key's presence is
  `key_exists`, since json_boost's `?[]` of a missing key is a non-null sentinel
  (`probes/test_stdlib.das`). Nothing here knows the C-IR or the emitter.
- `pipeline.das` - `convert(c_path, out_dir, target[, clang, sidecar, param_writes, loops])`: read
  the sidecar (a `param_writes` or `loops` argument other than "" overrides the sidecar's key, and
  one that is not a mode is refused), dump under its `defines`, write the C-IR, read it back and rewrite it
  (the bytes must match), emit, format with
  `daslib/das_source_formatter`, compile-check with `compile_file`. Every artifact lands under
  `out_dir`; `file_stem` is the name every artifact of a C file carries. The result carries the
  bytes of clang's JSON dump and the seconds of the dumper, the emitter (with the formatter) and
  the compile check, which `lua/run.das` (repo root) reports.
- `tiers.das` - `run_tier(das_path, tier, work_dir, output[, module_dirs[, timeout[,
  flags]]])`: the process exit code of the module under `interp`, `jit`, `exe` or `aot`
  (section 5); `module_dirs` are passed as `-load_module` to the interpreter and the JIT, `flags`
  before the script, and a process past `timeout` seconds (600 by default) is killed and
  reported as a failure: the run, and under `exe` and `aot` each build step too. `program_args` are the program's own C `argv` after its name: after `--` under
  `interp` and `jit`, after the binary under `exe`; `aot` refuses them, since its host passes
  none. `CONVERTED_MODULES` names the module folders a converted program requires and
  `daslang_cmd` spells the prefix; `native_run` builds a C file with a given compiler and flags
  and runs it once, with the program's arguments when given, the native side every differential test compares against.
- `main.das` - the CLI (`daslib/clargs`): `c2das <file.c> [--out] [--target] [--run] [--arg]...
  [--sidecar] [--param-writes in-place|copy] [--loops range|while]`. Each `--arg` is one argument of the C `argv` the
  program `--run` runs gets, in order. `--param-writes` chooses how the emitter writes a scalar or
  pointer parameter the body assigns, steps or takes the address of: `in-place`, the default and
  the idiomatic form, writes the parameter itself; `copy` writes a local copy, which the
  interpreter runs faster (`ARCHITECTURE_EMITTER.md` section 4). The option wins over the
  sidecar's `param_writes` when both are given, since a command line names one run and the
  sidecar the project. A value other than those two is a usage error: exit 2 before any
  conversion, as a missing input is. `--loops` chooses how a canonical counting `for` is spelled:
  `range`, the default, a das range loop, which is both the idiomatic and the faster form
  (`ARCHITECTURE_EMITTER_LOOPS.md`); `while`, the `while` form every other `for` takes, which
  the plan's section 6 gates the rewrite behind until demo sync (`docs/implementation_order.md`
  P7.0 holds the owner's ruling); it wins over the sidecar's `loops` and refuses any other value
  the same way.
- `benchmarks/bench_for_shapes.das` - the loop-shape race behind section 4
  (`ARCHITECTURE_EMITTER.md`), run with `dastest -- --bench` under the interpreter and
  under `-jit`.
- `tests/test_lowerings.das` - the P1 fixtures under `tests/fixtures/p1_*.c`, each converted
  and run against the native build of the same file by the pinned clang (output and exit
  code), plus the lowering shapes the text must carry.
- `tests/test_cli.das` - `main.das` run as a child process over `tests/fixtures/p4_param_writes.c`:
  `--param-writes copy` and `in-place` reach the emitter, and a bad value exits 2; over
  `tests/fixtures/p7_loops.c`: `--loops range` and `while` reach the emitter, and a bad value
  exits 2; and over
  `tests/fixtures/p4_main_args.c`: `--arg` reaches the C `argv` under `interp` as the native
  build's arguments do and under `exe`, and `aot` refuses it.
- `tests/test_sidecar.das` - `read_sidecar` over written `.c2das` files: the `defines` list,
  its function-like entries and the shapes it refuses, the `over_indexed` list and the shapes it
  refuses, the `loops` values and the ones it refuses.
- `tests/test_tier_facts.das` - the das facts the emitter relies on, each a program run under the
  four tiers: `int` and `int64` `+` and `-` wrap, and `c_volatile_load` reads a global on every
  pass of a loop whose plain read the JIT, the exe and AOT fold out of it.
- `tests/test_csmith_verdict.das` - the csmith driver's classification of a worker that ended
  (`suites/csmith/verdict.das`), the one piece of the driver testable without a process.
- `tests/test_pipeline.das` - the P0 gate: `tests/fixtures/ret42.c` converts, the C-IR and the
  das text hash to their golden values, and the module exits 42 under all four tiers; and a
  program whose `#if` branch the sidecar's `defines` select prints what the native build under
  the same `-D` prints.
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
`typeinfo offsetof` and the spec has no node for it (`docs/probe-findings.md` F20); `alignof_v`
is `_Alignof` in the shape of `sizeof_v`, `v` clang's alignment and `of_t` the type, which the
spec has no node for either (F54). Another addition is `dims` on a `global`, a `decl` statement
and a record field: one `{enum_t, item}` per array dimension of the declarator, outermost
first, the item empty for a dimension not
spelled as one enum constant, the member absent when none is, since the lowering keeps the
constant as the dimension and the spec's `count` is the folded integer (F21). The spelling is
a fact about the declarator, not the type, so the type table interns `T[6]` once however the
source wrote it. An `enum` type carries `"signed": false` when clang gave it an unsigned
underlying type (F22); the member is absent for a signed one, which is every enum of the
`msvc` dialect. An lvalue node (`ref`, `member`, `index`, `un` `deref`) of volatile-qualified
type carries `"vol": true` after the members of its kind and before `macro`, absent otherwise,
since the type table strips qualifiers and the emitter keeps every access of such an object
(F65, `ARCHITECTURE_EMITTER_LOOPS.md`). The additions keep `"cir": "0.1"` (`CIR_VERSION`), where
the spec's section 10 bumps the minor for an additive field: F20, F21 and F65 record each as
additive at 0.1, and a reader of this tree accepts no other version.

A record's `packed` is false exactly when das's natural layout reproduces clang's, by this law
(`bit_units.das`), which a Dumper B applies to the same facts to write the same byte. Fields go
in declaration order, each at its offset rounded up to its das alignment (a scalar's size, an
array's element's, a nested record's das alignment as this law found it, or clang's for a record
it finds packed); a flexible array member (an array of count -1 that ends the record) adds no
bytes. An unnamed or zero-width bitfield never opens a storage unit. The first named bitfield
not yet covered opens an unsigned unit of its declared type's size first, then of 1, 2, 4 and 8
bytes in that order, at the next offset that size divides; every following bitfield whose bits
lie inside the unit joins it, and when the rest of the record then misses a clang offset or
clang's size the search backtracks to the next size. The end, rounded up to the largest
alignment met, must be clang's size, and that alignment must be the target: clang's alignment
first, then each power of two below it, the first target that works winning. A target below
clang's is tried only when the record has a named bitfield of nonzero width or a field whose
record (through arrays) won below its clang alignment, and when clang's alignment is the one its
members give with no alignment attribute: the largest of each field's das alignment, a named
bitfield's declared type, a nested record's clang alignment (through arrays), and under `msvc`
alone, by its declared type, an unnamed bitfield of nonzero width and a zero-width one that
directly follows a bitfield of nonzero width. That is the one ABI fact the law reads from the
target (`CirTarget.triple`): under `msvc` a nonzero-width unnamed bitfield, and a zero-width one
directly after a nonzero-width bitfield, align a record by their declared type; under the
Itanium ABI no unnamed bitfield does (`{ char a; int : 20; }` is size 4, align 1 under `linux` and 8, 4 under
`msvc`; `{ char c; unsigned a : 9; long long : 0; char d; }` is 12, 4 and 16, 8; a zero-width one
after a plain field or after another zero-width one aligns neither, `{ char a; int : 0; char b;
}` is 5, 1 and 2, 1, `{ char x : 3; int : 0; long long : 0; char d; }` 9, 1 and 8, 4;
`probes/test_layout.das`). When no target works, a record with any bitfield (named or unnamed,
zero-width included) or a field whose record won below its clang alignment takes one relaxed
search, unless clang's alignment exceeds the alignment its members give, which only an attribute
does. The relaxed search places fields in the same order and adds three moves: where das's
offset falls short of clang's, a padding field of the missing bytes (`_pad<N> : uint8[n]`)
before the field, before a unit or at the tail up to clang's size; a unit of each size in the
same order also at the offset that size divides at or below the bitfield's first byte; and,
last, a byte unit of `k` bytes (1 to 8, alignment 1) at that byte. A byte unit joins the
bitfields that follow while their bits stay within 8 bytes of its start, a zero-width one
carrying no bits and adding nothing to the size; it tries each join from the most bitfields down
to its own alone, the joins of at most 4 bytes first and those past 4 bytes after, so a join
backtracks when the rest of the record misses clang's offsets. The record's das alignment is
then the largest its fields give, which must be at most clang's; since both are powers of two
and the size is clang's, every clang offset of the record, in an array or nested, is a multiple
of it. The C-IR's `packed` is false for every record the law places, the relaxed search
included, so Dumper B applies the relaxed search to write the same byte. The C-IR carries no
attribute: a record declared `packed` or under `#pragma pack(n)` whose layout the law places
converts like any other (`packed { unsigned a : 3; char c; unsigned b : 20; }` takes byte units,
size 5), and `packed` in the C-IR means a record the law cannot place, not an attributed one
(`docs/probe-findings.md` F51). A union is natural when it has a member, every member sits at
offset 0, clang's alignment is 1, 2, 4 or 8 and divides its positive size, and every member fits
it: a member's das alignment (as this law finds it) at most clang's alignment, its size at most
clang's size, and a member record (through arrays) natural itself. An unnamed bitfield of a
union is no member; a named one sits at bit 0 and fits when its bits fit clang's size, whatever
its declared type's alignment (under `msvc` a bitfield member adds no alignment of its own:
`union { char c; long long f : 5; }` aligns 1 there, while `union { signed f0 : 8; unsigned f1;
}` aligns 4 through `f1`). `[c_union]` then gives the storage clang's size and alignment, so a
natural union's das alignment is clang's even where its members align lower (a member record
below its clang alignment, F5; an `aligned` attribute up to 8). An anonymous member (a struct or
union member with no declarator) is a field named `""` that is not a bitfield: its `t` is the
anonymous record, its `off` the byte offset clang gives it, and it carries no `bit_w`. In an
`init_list` of a record, `pos` is the field index; an unnamed bitfield is never an item, and a
union's list holds at most one item, `pos` the member it initializes (none for `{}`). A record
spelling carries no owner scope: `union S::(anonymous at f:l:c)` interns as `union (anonymous at
f:l:c)`, the spelling libclang and the dump share.

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
`ARCHITECTURE_EMITTER_AGGREGATES.md`, the switch and the labels in
`ARCHITECTURE_EMITTER_CONTROL.md`, and the loops, the compound stores and the volatile access in
`ARCHITECTURE_EMITTER_LOOPS.md`.

## 5. The four tiers

`interp` runs `daslang <module>`, `jit` runs `daslang -jit <module>`, `exe` runs `daslang -exe
<module> -output <work>/<stem>_exe` and executes the binary (the JIT names it `.exe` on every
platform), `aot` runs `daslang utils/aot/main.das -- -ctx <module> <work>/ctx/` and compiles
the generated context with a seven-line C host (`<stem>_create`, `<stem>_main`,
`<stem>_destroy` from the generated header, `<stem>` spelled as a C++ identifier, which also
names the binary `aot_binary` answers) against the static runtime: `liblibDaScript.a`,
`liblibDaScript_runtime.a`, `liblibUriParser.a`, with the checkout's ABI flags (no RTTI,
`DAS_FUSION=2`, `SIZE_OF_VOID_P=8`). The compiler is the pinned clang's `clang++` at `-O3`,
the native perf lane's compiler and level (`perf/ARCHITECTURE.md` section 2); `default_clang()`
answers `clang` on PATH when `PATH_TO_LIBCLANG` is unset, so the host is then `clang++` on
PATH, the same requirement the conversion already has. Every tier takes the module folders
from the caller (`suites/c_testsuite/run.das` passes both): the interpreter and the JIT load
them, `exe` loads them while it builds the executable, and `aot` uses them twice, loaded while `-ctx` generates the context and
as sources, where a folder holding `src/*.cpp` (`dasCRuntime`) compiles into the host with its
`src/` on the include path, because the generated context declares the module and includes
its header. The exit code is the program's own on every tier,
which is why the wrapper returns from `main`.

## 6. Exception ledger

Empty.
