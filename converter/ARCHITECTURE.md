# converter Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The
folder is the daslang program that turns C into gen2 daslang: Dumper A, the C-IR model, the
emitter, the pipeline that chains them, and the tier runner the gate and the suites use. The
normative design is `docs/very-detailed-plan.md` (sections 4 and 5) and the expected output is
`docs/lowering-examples.md`; this document states only what the code here is.

## 1. File charters

- `cir.das` - the C-IR of `docs/c-ir-spec.md` as das values (`CirTu`, `CirType`, `CirDecl`,
  `CirStmt`, `CirExpr`, one struct per spec table), the canonical writer `write_cir`, the
  reader `read_cir`, `write_program` (the manifest of `docs/c-ir-spec.md` section 7), `write_cir_decl` (one
  declaration's bytes), `ident_of` (a file stem as an identifier), the pinned `CAST_KINDS`, the two
  dialects, `is_jmp_buf` (the dumper's opaque `jmp_buf` record, `JMP_BUF`). Nothing here knows clang or
  daslang syntax. A tree is owned through plain pointers and freed by one `delete` of its
  root: the generated finalizer recurses through pointer fields and arrays of pointers
  (`probes/test_delete.das`), so no hand-written walk frees a child.
- `dumper_a.das` - Dumper A: runs `clang -Xclang -ast-dump=json -fsyntax-only -target <triple>`,
  with `-D<entry>` per entry of the sidecar's `defines` and `-I<dir>` per entry of its
  `include_dirs` (`DumpInputs`), on one file and normalizes the JSON into a `CirTu`. Fails closed:
  the first construct outside what it represents sets `Dumper.error` with `file:line:col`. Layout
  facts come from a libclang pass over the same file (`ARCHITECTURE_DUMPER.md`, section 3), and
  its macro expansions mark nodes through `macro_sites.das` (`ARCHITECTURE_DUMPER_MACROS.md`).
- `emit.das` - the emitter: `CirTu` in, gen2 text out, fails closed the same way. The
  lowering passes of the plan (type resolve and rename, promotion insertion,
  statement-ification, control flow) happen as it spells nodes (`ARCHITECTURE_EMITTER.md`,
  section 4); no pass transforms the `CirTu` before emission. `emit_tu` spells one module,
  `emit_program` the modules of a source layout over one program state (section 8).
- `bit_units.das` - the layout law over the C-IR (section 2, `packed`): `type_size`,
  `natural_align` (a record's is its das mirror's, which can be below clang's, F5),
  `natural_layout` (the dumper's `packed` verdict), `bit_units` (the allocation units that cover
  a record's bitfields), `union_flaw` (why a union is not natural), `union_member_layout` (the
  size and alignment a bare `[c_union]` derives), `record_under`/`element_under` (the type at
  an array's bottom), `jmp_buf_field` (a record's field holding a `jmp_buf`) and
  `is_storage_bitfield`. Every answer about a record lands in a `LayoutMemo` the dumper and the
  emitter each own, so a nest of records is measured once per record; a unit search never
  retries a failed state (field, offset, alignment so far). Nothing here knows clang or das syntax.
- `sidecar.das` - the per-project `.c2das` file as a `Sidecar` value: `find_sidecar` (the path
  given, else `<stem>.c2das` beside the C file, else `.c2das` in its folder) and `read_sidecar`
  (JSON; a key the row that needs it adds - `marshal`, the records read and written as bytes;
  `stack` and `alloca_limit`; `param_writes`, `in-place` or `copy`, the parameter write mode, any
  other value refused naming the key; `loops`, `range` or `while`, how a canonical counting `for` is
  spelled, any other value refused naming the key; `first_member`, `addr` or `reinterpret`, how the
  address of a member at offset 0 is spelled, `switch_dispatch`, `chain` or `goto`, how a dense switch dispatches and whether a goto into another case group re-dispatches, and `past_end`, `call` or `inline`, how `&a[k]` of a plain-load index is spelled, each other value refused naming the key; `layout`,
  `source`, `source-cut` or `single`, the module layout of a program of several files, or an object
  of `mode` (one of those), `threshold` (a count), `keep_together` (symbols and lists of file
  stems), `cut` (symbols) and `profile` (a file beside the sidecar), the cycle cut's choices, any
  other value or key refused naming it; `defines`, a list of strings `NAME`, `NAME=value` or the
  function-like `NAME(params)=value` (params identifiers separated by commas, `...` last) the dump
  and the libclang pass give clang as one `-D<entry>` argument each (a function a host defines
  outside the unit, plmpeg's test hook `c2da_rt_reset`, is nothing under `NAME(...)=`, its prototype
  and its calls alike), a value that is no list or an entry of another shape refused naming the key;
  `over_indexed`, a list of strings `Record.field`, the trailing arrays the program indexes past
  their length, a value that is no list or an entry of another shape refused naming the key, an
  entry naming no record's trailing array the emitter's error; `padded`, the same for the arrays
  indexed one past either end into the members beside them, an entry naming no integer array flanked
  by integers of its element's width the emitter's error; `include_dirs`, a list of folders both
  clang passes of the dump search as `-I<dir>` in order, `include_files`, the headers both passes
  read first as `-include <file>` in order, and `program_root`, the folder whose files are the
  program's (`ARCHITECTURE_DUMPER.md`, the file policy), each read beside the sidecar unless
  absolute, a value of another shape refused naming the key; `solid_context`, `jit_whole_program`, `inline_helpers` and `strict_aliasing`, booleans, the second the entry module's JIT pin of `ARCHITECTURE_EMITTER.md` section 4, the third the pure helpers spelled at their call sites of `ARCHITECTURE_EMITTER_CONTROL.md`; `--inline-helpers` sets it), the fourth keeping the JIT's typed aliasing (`ARCHITECTURE_TIERS.md` section 9). A key outside these is refused naming
  it. A key's presence is `key_exists`, since json_boost's `?[]` of a missing key is a non-null
  sentinel (`probes/test_stdlib.das`). Nothing here knows the C-IR or the emitter.
- `pipeline.das` - `convert(c_path, out_dir, target[, clang, sidecar, param_writes, loops,
  first_member])`: read the sidecar (a `param_writes`, `loops` or `first_member` argument other
  than "" overrides the sidecar's key, and
  one that is not a mode is refused), dump under its `defines`, write the C-IR, read it back and rewrite it
  (the bytes must match), emit, format with
  `daslib/das_source_formatter`, compile-check with `compile_file`. Every artifact lands under
  `out_dir`; `file_stem` is the name every artifact of a C file carries. The result carries the
  bytes of clang's JSON dump and the seconds of the dumper, the emitter (with the formatter) and
  the compile check, which `lua/run.das` (repo root) reports. `convert_program(c_paths, ...[,
  entry])` is the program of several files: each dumped, written and round-tripped as `convert`
  does it, then linked (section 6) and emitted in the layout of section 8: by default a module per
  C file under `out_dir` as the files lie under their common folder, every cycle one module
  (`source`), the cycles cut by late binding (`source-cut`), or one module, `<stem>.das` of the unit holding `main`,
  else of the first (`single`), as `--layout` or the sidecar's `layout` chooses; beside
  `program.cir.json`, and in the two module-per-file layouts `program.layout.txt`, the partition's
  report; its result adds the link's seconds and report, the files it wrote and that report. One
  file is `convert` of it. `read_program_input` reads a manifest the converter takes (section 6).
- `link.das` - the link of section 6 (`ARCHITECTURE_LINK.md`): `link_tus` over the dumper's trees
  of a program's units, each unit's scope (its output module) from the caller's block.
  Nothing here knows clang or daslang syntax.
- `layout.das` - the source layout of section 8 (`ARCHITECTURE_LAYOUT.md`): `plan_layout`, the
  partition of a linked program into modules with the cycle cut (`CutOptions`), and
  `layout_report`, its lines. Nothing here knows
  clang or daslang syntax.
- `tiers.das` - `run_tier(das_path, tier, work_dir, output[, module_dirs[, timeout[,
  flags]]])`: the process exit code of the module under `interp`, `jit`, `exe` or `aot`
  (section 5, `ARCHITECTURE_TIERS.md`); `module_dirs` are passed as `-load_module` to the interpreter and the JIT, `flags`
  before the script, and a process past `timeout` seconds (600 by default) is killed and
  reported as a failure: the run, and under `exe` and `aot` each build step too. `program_args` are the program's own C `argv` after its name: after `--` under
  `interp`, `jit` and `aot` (whose host hands its command line to the runtime), after the binary
  under `exe`. `CONVERTED_MODULES` names the module folders a converted program requires and
  `daslang_cmd` spells the prefix; `native_run` builds a C file, or a program's files in order,
  with a given compiler and flags and runs it once, with the program's arguments when given, the native side every differential test compares against.
- `main.das` - the CLI (`daslib/clargs`): `c2das <file.c>... | --program <p.json> [--out] [--target]
  [--run] [--arg]... [--sidecar] [--param-writes in-place|copy] [--loops range|while] [--first-member
  addr|reinterpret] [--layout source|source-cut|single]`. Several files are one program linked in their order, as are the files a manifest
  names; files beside `--program` are a usage error (exit 2). `--layout` chooses the modules of such
  a program (section 8): `source`, the default and the idiomatic form, a module per C file with
  every cycle one module of fragments; `source-cut`, the cycles cut by late binding; `single`, one
  module; it wins over the sidecar's `layout` mode, and any other value is a usage error (exit 2).
  One file is one module in each layout. Each `--arg` is one argument of the C `argv` the program
  `--run` runs gets, in order. `--param-writes` chooses how the emitter writes a scalar or
  pointer parameter the body assigns, steps or takes the address of: `in-place`, the default and
  the idiomatic form, writes the parameter itself; `copy` writes a local copy, which the
  interpreter runs faster (`ARCHITECTURE_EMITTER.md` section 4). The option wins over the
  sidecar's `param_writes` when both are given, since a command line names one run and the
  sidecar the project. A value other than those two is a usage error: exit 2 before any
  conversion, as a missing input is. `--loops` chooses how a canonical counting `for` is spelled:
  `range`, the default, a das range loop, which is both the idiomatic and the faster form
  (`ARCHITECTURE_EMITTER_LOOPS.md`); `while`, the `while` form every other `for` takes; it wins
  over the sidecar's `loops` and refuses any other value the same way. `--first-member` chooses how
  the address of a member at offset 0 is spelled: `addr`, the default and the idiomatic form,
  `addr(p.f)`; `reinterpret`, the record's pointer reinterpreted, which the interpreter runs faster
  (`ARCHITECTURE_EMITTER_AGGREGATES.md`); it wins over the sidecar's `first_member` the same way, as `--switch-dispatch` (`chain`, the default, or `goto`, the jump table and the flat case groups of `ARCHITECTURE_EMITTER_CONTROL.md`) over `switch_dispatch` and `--past-end` (`call`, the default, or `inline`, the conditional of `ARCHITECTURE_EMITTER_AGGREGATES.md`, One past an array's end) over `past_end`.
- `benchmarks/bench_for_shapes.das` - the loop-shape race behind section 4
  (`ARCHITECTURE_EMITTER.md`), run with `dastest -- --bench` under the interpreter and
  under `-jit`.
- `tests/test_lowerings.das` - the P1 fixtures under `tests/fixtures/p1_*.c`, each converted
  and run against the native build of the same file by the pinned clang (output and exit
  code), plus the lowering shapes the text must carry.
- `tests/test_cli.das` - `main.das` run as a child process over `tests/fixtures/p4_param_writes.c`:
  `--param-writes copy` and `in-place` reach the emitter, and a bad value exits 2; over
  `tests/fixtures/p7_loops.c`: `--loops range` and `while` reach the emitter, and a bad value
  exits 2, as `--first-member` over `tests/fixtures/p7_first_member.c` and `--switch-dispatch` over `tests/fixtures/p7_goto_dispatch.c`; over `tests/fixtures/p5_layout_cut/`: `--layout source`, `source-cut` and `single` reach the
  converter, and a bad value or the old name `scc` exits 2; and over
  `tests/fixtures/p4_main_args.c`: `--arg` reaches the C `argv` under `interp` as the native
  build's arguments do, under `jit`, under `exe` and under `aot`.
- `tests/test_sidecar.das` - `read_sidecar` over written `.c2das` files: the `defines` list,
  its function-like entries and the shapes it refuses, the `over_indexed` and `padded` lists and the
  shapes they refuse, the `loops`, `first_member`, `switch_dispatch`, `layout` (as a mode and as an object), `solid_context`, `jit_whole_program` and `strict_aliasing` values and the ones
  they refuse, `include_dirs` and `program_root` read beside the sidecar and the shapes they
  refuse, and an unknown key.
- `tests/test_tier_facts.das` - the das facts the emitter relies on, each a program run under the
  four tiers: `int` and `int64` `+` and `-` wrap, and `c_volatile_load` reads a global on every
  pass of a loop whose plain read the JIT, the exe and AOT fold out of it.
- `tests/test_csmith_verdict.das` - the csmith driver's classification of a worker that ended
  (`suites/csmith/verdict.das`), the one piece of the driver testable without a process.
- `tests/test_suite_audit.das` - the runner's skip audit (`--audit-skips`) over a stand-in suite.
- `tests/test_torture_filter.das` - the gcc-torture import's rules (`suites/gcc_torture/filter_rules.das`).
- `tests/test_pipeline.das` - the P0 gate: `tests/fixtures/ret42.c` converts, the C-IR and the
  das text hash to their golden values, and the module exits 42 under all four tiers; and a
  program whose `#if` branch the sidecar's `defines` select prints what the native build under
  the same `-D` prints; and `tests/fixtures/p8_include_dirs/` (a unit including a sibling folder's
  C file through `include_dirs` and a `../` header, under a `program_root` above both) printing what
  its native build prints, with the refusals of a C file outside the root and of a main file
  outside it, and the program converting with its folder named in `CPATH`.
- `tests/test_link.das` - the three files of `tests/fixtures/p5_multi_link/` linked into one module
  that prints what their native build prints, with the renames, the header copies and the scoping
  the text must carry; the file list and the fixture's manifest giving one module through
  `main.das`; the manifest's and the link's refusals; the binding rules over trees built by hand;
  all of it in the single layout.
- `tests/test_layout.das` - the source layout of section 8: `tests/fixtures/p5_layout_tree/` (four
  files in two folders, a cluster of two, a header's types, the shared types module) converted and
  run against its native build under the interpreter and the JIT, with the requires, the include
  order, the renames, the header copies and the literal objects the text must carry; the single
  layout's text against the recorded hash of the link's one module; one file as one
  module; the tree under the sidecar's `jit_whole_program`, its entry module alone pinned; `tests/fixtures/p5_layout_types/` (two headers whose records point at each other); the
  refusals; and `tests/fixtures/p5_layout_cut/` (two files calling each other, a variadic callee, a
  header pointing at a record a unit defines): the cut by the static count, by a profile, under
  `layout.keep_together`, `layout.cut` and `layout.threshold`, the refused cut of an object, a file
  reached only through cut edges, and the three layouts printing what the native build prints;
  `cut_order` against every permutation of small weighted graphs, and its greedy order past 16
  nodes.
- Fixtures under `tests/fixtures/` are C inputs, never das.

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
One node is this repository's addition to the spec's table: `offsetof` with `of_t` and `field` (the
record type and the field index), since the lowering spells `offsetof` as `typeinfo offsetof` and
the spec has no node for it (`docs/probe-findings.md` F20); `alignof_v` is `_Alignof` in the shape
of `sizeof_v`, `v` clang's alignment and `of_t` the type, which the spec has no node for either
(F54). Another addition is `dims` on a `global`, a `decl` statement and a record field: one
`{enum_t, item}` per array dimension of the declarator, outermost first, the item empty for a
dimension not spelled as one enum constant, the member absent when none is, since the lowering
keeps the constant as the dimension and the spec's `count` is the folded integer (F21). The
spelling is a fact about the declarator, not the type, so the type table interns `T[6]` once
however the source wrote it. An `enum` type carries `"signed": false` when clang gave it an
unsigned underlying type (F22); the member is absent for a signed one, which is every enum of the
`msvc` dialect. An lvalue node (`ref`, `member`, `index`, `un` `deref`) of volatile-qualified type
carries `"vol": true` after the members of its kind and before `macro`, absent otherwise, since the
type table strips qualifiers and the emitter keeps every access of such an object (F65,
`ARCHITECTURE_EMITTER_LOOPS.md`), then a character literal's `"char": true` (P7.0i), additive at
`"cir": "0.1"` with F20, F21 and F65. The macro fields of the spec's section 6.3, each absent when
empty, are 0.2 (`CIR_VERSION`, `ARCHITECTURE_DUMPER_MACROS.md`); a reader here accepts no other.
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
zero-width included), a field whose record won below its clang alignment or a field that is the
opaque `jmp_buf` record, whose one `int` stands for the C library's buffer, takes
one relaxed search, unless clang's alignment exceeds the alignment its members give, which only an attribute
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
included, so Dumper B applies the relaxed search to write the same byte.

The C-IR carries no attribute: a record declared `packed` or under `#pragma pack(n)` whose layout
the law places converts like any other (`packed { unsigned a : 3; char c; unsigned b : 20; }` takes
byte units, size 5), and `packed` in the C-IR means a record the law cannot place, not an
attributed one (`docs/probe-findings.md` F51).

A union is natural when it has a member, every member sits at offset 0, clang's alignment is 1, 2,
4 or 8 and divides its positive size, and every member fits it: a member's das alignment (as this
law finds it) at most clang's alignment, its size at most clang's size, and a member record
(through arrays) natural itself. An unnamed bitfield of a union is no member; a named one sits at
bit 0 and fits when its bits fit clang's size, whatever its declared type's alignment (under `msvc`
a bitfield member adds no alignment of its own: `union { char c; long long f : 5; }` aligns 1
there, while `union { signed f0 : 8; unsigned f1; }` aligns 4 through `f1`). `[c_union]` then gives
the storage clang's size and alignment, so a natural union's das alignment is clang's even where
its members align lower (a member record below its clang alignment, F5; an `aligned` attribute up
to 8).

An anonymous member (a struct or union member with no declarator) is a field named `""` that is not
a bitfield: its `t` is the anonymous record, its `off` the byte offset clang gives it, and it
carries no `bit_w`. In an `init_list` of a record, `pos` is the field index; an unnamed bitfield is
never an item, and a union's list holds at most one item, `pos` the member it initializes (none for
`{}`). A record spelling carries no owner scope: `union S::(anonymous at f:l:c)` interns as `union
(anonymous at f:l:c)`, the spelling libclang and the dump share.

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
`ARCHITECTURE_EMITTER_CONTROL.md`, the loops, the compound stores and the volatile access in
`ARCHITECTURE_EMITTER_LOOPS.md`, and the C spelling it carries in `ARCHITECTURE_EMITTER_TEXT.md`.

## 5. The four tiers

Section 5, how `tiers.das` runs a module under each tier, is in `ARCHITECTURE_TIERS.md`.

## 6. The link

Section 6, how several C files link into one program, is in `ARCHITECTURE_LINK.md`.

## 7. Exception ledger

Empty.

## 8. The source layout

Section 8, the modules of a program of several files (the partition, the fragments, the program
and module state of the emitter), is in `ARCHITECTURE_LAYOUT.md`.
