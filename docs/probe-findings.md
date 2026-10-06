# C-To-DAS — Probe Findings (divergences between the documents and the live binary)

Every ✓ in the design documents was verified on a daslang binary of 2026-08-21. The P0.3
probe suite (`probes/`, this repository) re-ran the facts on the pinned build (daScript
`0fd34f17f`, Linux x86_64, libclang 22.1.8). This file records every place where the probe
contradicts a document, with the document line, the probe arm that settles it, and the
consequence for the phase that consumes the fact. The documents themselves are never edited
to match code; each entry here is a report to the documents' authoring repository
([lookibed/C-To-DAS](https://github.com/lookibed/C-To-DAS)). A row leaves this file when the
document changes or the fact is re-probed green.

| # | Document line | Claim | Probe | What the binary does | Consumer |
|---|---|---|---|---|---|
| F1 | `c-feature-matrix.md` §5 `exit(code)` | "das `exit(code)` 1:1 … probed ✓ from deep stack, process code propagates" | `probes/test_process.das`, "exit(N) from a deep stack reports exit code 1 …" | `exit(42)` unwinds as an abnormal termination: the process exits **1**, prints `exit(42) called from …` plus the CALL STACK on **stdout**, and `[daslang atexit] FATAL: g_envTotal=1` on stderr. `exit_now(42)` (`daslib/fio`, unsafe) flushes stdout and exits **42**; `def main : int { return 42 }` exits 42 | P1.2 `c_exit` must end in `exit_now`, not `exit`. The `sidequest.md` "Quiet `exit()`" row is confirmed necessary if `exit` stays: the noise is on stdout, so "harness diffs stdout only" does not shield the runner |
| F2 | `stdlib-examples.md` "mem* family" | "`memcpy`/`memset` exist as das builtins (probed ✓)" | `probes/test_stdlib.das`, "malloc, free, memcpy and memset8 are builtins …" | `memcpy` exists; there is no `memset`. The builtins are `memset8/16/32/64/128(ptr, value, count)`. `very-detailed-plan.md` §7 lists `memset` among the CRT binds, so the two documents already disagree | P0.4 / P1: C `memset(p, v, n)` lowers to `memset8(p, uint8(v), n)` or binds CRT `memset`; pick one and say so in stdlib-examples |
| F3 | `lowering-examples.md` "Pointers + `[c_function]` ✓ (all probed)", the `blit` example | `def blit(src_in, dst_in : uint8?; n_in : int)` then `var dst = dst_in` … `deref(dst) = deref(src)` | `probes/test_macros.das`, "a pointer written through must be a var parameter …" | Does not compile: a non-`var` parameter `dst_in : uint8?` has type `uint8? const`, and a local copy of it is `uint8 const?` (const pointee); `deref(dst) = …` is "can't write to a constant value". With `var dst_in : uint8?` the copy is `uint8?` and the body compiles under the whole-body `unsafe` | P2.3: the emitter declares every pointer parameter the body writes through as `var`; the callee-copy pattern is unchanged otherwise |
| F4 | `lowering-examples.md` "Variadics", `to_cvalist` | The `else` arm covers "int-class incl. small ints, enums" | `probes/test_variadics.das` (the arm list deliberately omits `bool`) | `int64(bool)` does not exist, so a `bool` tuple field fails the `else` arm at instantiation. C `_Bool` promotes to `int` through `...`, so a converted call site can pass one | P1.3: add a `static_elif (typeinfo is_bool(field))` arm pushing `CVal(i = field ? 1l : 0l)`; not a document contradiction, a gap |
| F5 | `lowering-examples.md` "Bitfields", `c-feature-matrix.md` §1 bitfields | "backing `_bits0 : uint` per allocation unit at clang's bit offsets … layout/size C-exact" | `probes/test_layout.das`, "bitfield bit offsets and widths come from clang; the unit width follows the target ABI" | For `struct BF { unsigned a : 3; int b : 5; short e; }` clang on Linux (Itanium ABI) reports `e` at bit 16, size 4, align 4: the unit is packed to the bytes used, yet the declared `unsigned` still aligns the struct. The das mirror `{ _bits0 : uint8; e : int16 }` has size 4 but **align 2**, and no das spelling gives size 4 / align 4 / `e` at 2. MSVC allocates the whole `unsigned` (e at 4, size 8), which `{ _bits0 : uint; e : int16 }` mirrors exactly | P4.1 `[c_bitfields]`: the unit width comes from the C-IR bit offsets, not always `uint`; on an Itanium host the alignment can only be restored by the `[align_as]` sidequest. The documents assume the MSVC ABI throughout; say so where layout is claimed C-exact |
| F6 | `very-detailed-plan.md` §4.1 (Dumper A, dasClangBind) | — (no claim) | `probes/test_layout.das` (the collector runs inside the test body) | `clang_parseTranslationUnit` called from a global initializer overflows the init script's stack; from a function body it works | P0.5 Dumper A: parse inside a function, never in module init |
| F7 | `stdlib-examples.md` "errno / time.h / rand" | "dasCRuntime exposes `c_errno()` ... coherent by construction, since every bound CRT function sets the same one" | `dasCRuntime/tests/test_crt.das`, "strtol family reports the end pointer and ERANGE through errno" | Coherent it is: `strtol` overflow reads back `ERANGE`, base 1 reads back `EINVAL`. But the libm calls through the module (`log1p(-2)`, `fmod(1, 0)`, `tgamma(-1)`, `remainder(1, 0)`) return NaN and leave errno at 0 on this glibc, so `EDOM` never arrives from libm; the test asserts the errno round trip instead | P1+: converted code that reads errno after a libm call sees the platform's answer, which differs from MSVC; a differential suite compares against a native binary on the same libm, so it stays self-consistent. Not a document contradiction, a platform fact |
| F8 | `skills/cpp_integration.md`, `examples/daspkg/packages/daspkg-example-cpp/CMakeLists.txt` (daScript's own standalone-module template) | A standalone module links `${DASLANG_DIR}/lib/libDaScriptDyn.so` and compiles with the default flags | `scripts/build_crt.sh`, `dasCRuntime/CMakeLists.txt` | On this checkout the libraries are `lib/liblibDaScriptDyn.so` and `liblibDaScriptDyn_runtime.so` (the `lib` prefix doubled), and a module compiled with RTTI fails to load with `undefined symbol: typeinfo for das::gc_node`: the checkout builds `-fno-rtti` with `DAS_FUSION=2` and `DAS_ENABLE_DYN_INCLUDES=1`, which its headers read. The module CMake globs both spellings and repeats the ABI flags | P0.4 done that way; any further native module here copies `dasCRuntime/CMakeLists.txt`, not the daScript example |
| F9 | daslang lint STYLE025 ("narrow to `unsafe(<sub-expr>)`") | The expression form `unsafe(call(addr(x)))` covers the call and its arguments | `dasCRuntime/tests/test_crt.das`, `test_crt_math` | `unsafe(crt::frexp(8.0lf, addr(e)))` is rejected with "address of reference requires unsafe": the expression form covers one operation, the nested `addr` needs its own `unsafe` or a block. A block `unsafe { ... }` around a statement with two unsafe operations is what the lint accepts | P2 emitter: an `unsafe` wrap covers exactly one unsafe operation; a statement with several takes the block form, and `[c_function]` bodies avoid the question |
| F10 | `lowering-examples.md` "Strings & literals", `c-feature-matrix.md` §2 string literal | `char *p = "lit"` lowers to `reinterpret<uint8?>("lit")`, "das literals are legal read-only C strings (interned, static, NUL-terminated)" | `probes/test_strings.das`, "the empty das literal is a null pointer, not a pointer to a NUL" | True for every literal but `""`: the empty das string is `nullptr` at runtime, so `reinterpret<uint8?>("")` is `null`, while C's `""` points at one NUL byte | P2.5: the emitter gives the empty literal storage (a one-byte `uint8[1]` global, `cstr_array("", 1)`) instead of the reinterpret; `c_vformat` treats a null format as empty rather than dereferencing it |

## Confirmed by the same run (no divergence)

`exit()` skips `[finalize]` (stdlib-examples "exit() skips normal context teardown") ✓;
`[finalize]` runs after `main`, LIFO walk ✓; `options stack = 400000` carries 128KB frames
and its absence overflows ✓; every shape listed as rejected (small-int arithmetic,
`fixed_array` size mismatch, `[1, 2, 3]` into a fixed array, enum `<`, `[inline]` on a
property operator) is a compile error ✓; every other ✓ in the lowering and stdlib documents
re-probes green (96 assertions, `probes/`).

## What upstream says (research over daScript sources, history, issues and Boris Batkin's repositories, 2026-09-25)

Sources: the daScript checkout at `DASLANG_ROOT` (a shallow clone grafted at `93f8550a8`,
2026-07-13, so older history is invisible locally), the fork remotes for pre-2026 commits,
`GaijinEntertainment/daScript` issues to #4110 and PRs to #4132 (Discussions disabled, wiki
empty), `borisbat`'s 37 public repositories, and `borisbat.github.io/dascf-blog`. No `daslang`
GitHub organization exists. Verdicts: **design** (upstream intends it), **bug** (upstream
would fix it), **gap** (nobody asked).

### F1 `exit(N)` exits 1 - a two-layer story: the message is design, the exit code is a bug

- `builtin_exit` (`src/builtin/module_builtin_fio.cpp:1030-1041`) prints `exit(N) called from`
  through `TextPrinter` and walks the stack through `Context::stackWalk`, both of which are the
  **stdout** channel (`src/misc/string_writer.cpp:214`, `Context::to_out`), then calls libc
  `exit(ec)`. PR #3523 "crash capture: report the failures that used to die silently" (Boris
  Batkin, 2026-07-21) states the intent: "Non-zero exits now name their das call site;
  `exit(0)` stays quiet." So the stdout noise is design, and `sidequest.md`'s "Quiet `exit()`"
  row asks upstream to reverse a deliberate choice.
- The exit code is overwritten by the runtime's own atexit hook: `Module::Initialize`
  registers `daslang_atexit_audit` (`src/ast/ast_module.cpp:133-142`), which at process exit
  does `if (g_envTotal != 0 && !g_exitingNow) { fprintf(stderr, "[daslang atexit] FATAL ..."); _Exit(1); }`.
  A script-level `exit()` never reaches `Module::Shutdown`, `g_envTotal` is still 1, and the
  audit replaces N with 1. Re-probed: **`exit(0)` also exits 1** and prints the FATAL line.
- `exit_now` (`module_builtin_fio.cpp:1043-1050`, PR #4009, 2026-09-11, for dastest's
  `--timeout` code 124) sets `g_exitingNow`, flushes both streams and `_exit(ec)`; it is the
  only exit that keeps N, and the only one upstream tests
  (`tests/fio/test_process.das:200-209`, "the runtime's atexit audit must stay quiet on a
  deliberate exit"). Nothing tests plain `exit(N)`'s code; the repo's own tools only ever call
  `exit(1)`/`exit(-1)`, where the override is invisible. The handmade docs of both functions
  contradict the behavior (`exit`: "equivalent to C exit"; `exit_now`: "prefer `exit`, which
  shuts down in order").
- Issue #3442 (Boris Batkin, open) wants runtime deaths distinguishable by exit code from
  compile errors, so exit-code discrimination is a live concern upstream.
- **Resolution for c2das.** `c_exit(code)` = run the atexit list, flush, `exit_now(code)`
  (unsafe, free under `[c_function]`); `c_abort()` = `exit_now(3)`. The synthesized `main`
  returns `c_main`'s result as `int`, which is the CLI's documented contract
  (`utils/daslang/main.cpp:460-462`). **Upstream candidate:** an issue against
  `GaijinEntertainment/daScript`: `builtin_exit` should set `g_exitingNow` (or shut the
  environment down) so `exit(N)` keeps N; model test `tests/fio/test_process.das:200`.

### F2 `memset` - design; the plain name never existed

- PR #527 "collection of memset" (Boris Batkin, 2023-04-07) introduced `memset8/16/32/64/128`
  with the width in the name from the first commit; `git log --all -S'"memset"'` finds no plain
  `memset` ever registered. The 128 variant went through aligned/unaligned twins and settled
  on one unaligned `memset128` (`843713e54`); the LLVM JIT maps `memset8` to `llvm.memset`
  (`66b7b160f`). The handmade doc of `memset8` says "equivalent to the C `memset` function".
- Surface today (`src/builtin/module_builtin_runtime.cpp:2707-2769`, all `unsafe`):
  `memcpy`/`memcmp`/`memmove` with `int`/`uint`/`int64`/`uint64` size overloads;
  `memset8/16/32/64/128(left : void?; value; count : int)` where **count is elements, `int`
  only** (no 64-bit overload, unlike memcpy). `memmove` arrived 2026-09-11 (PR #4005, "someone
  porting wasm to das asked for it"), so the 2026-08-21 binary lacked it; `memcmp` has existed
  since 2020.
- `malloc`/`free` (`7f7f6b266`, 2023) wrap `das_aligned_alloc16` = `posix_memalign` /
  `_aligned_malloc` plus a tracking hook (`include/daScript/misc/platform.h:470-506`): system
  memory, never the context heap, but with 16/64/2MB alignment rules and `size != 0` asserted,
  so `malloc(0)` differs from CRT. The bind-first ruling (CRT `malloc` via dasCRuntime) stands.
- **Resolution.** C `memset(p, v, n)` lowers to `unsafe { memset8(reinterpret<void?>(p), uint8(v), int(n)) }`
  or binds CRT `memset` through dasCRuntime; `very-detailed-plan.md` section 7 already says the
  latter. A byte count above 2GB needs the CRT bind. **Upstream candidate:** a byte-count
  `memset(void?, uint8, int64)` request has the exact precedent of PR #4005.

### F3 const pointer parameters - design, ruled twice, enforced by a lint

- The parser gives a non-`var` parameter `constant = true` on the top-level type
  (`src/parser/ds2_parser.ypp:2788-2808`), so `p : uint8?` is `uint8? const`. `visitLetInit`
  (`src/ast/ast_infer_type.cpp:5725-5728`) moves that const onto the pointee when an `auto`
  local copies it, with the only in-code comment: `// var a = Foo? const -> var a : Foo const? = Foo? const`.
  The explicit-type case is `canCopyOrMoveType` (`src/ast/ast_infer_type_op.cpp:599-604`,
  "can't copy constant to non-constant pointer", `void?` exempt).
- The rationale is Boris Batkin's, in two rulings: PR #3316 (2026-06-30, after issue #3311
  where const-stripped writes were dead-code-eliminated in every tier): "the fork-callable
  pointer kernels took their writable output as `T const?` and reinterpret-stripped the const
  to write through it. That was never a JIT quirk - it's a lie to the type system"; and issue
  #3991 / PR #3996 (2026-09-10, filed by this project's author): "Under the language's const
  model the declared type is the contract the optimizer reads, so `var dst : void?` stays the
  supported spelling for a C-shaped out-parameter". The JIT marks a const pointer parameter
  LLVM `readonly` (`modules/dasLLVM/daslib/llvm_jit.das:666-669`); LINT031 (on by default)
  rejects the const-strip write. Documented in `skills/daslang/references/types.md:201-231`,
  `memory.md:5-27`, `doc/source/reference/language/pointers.rst:25,262-305`.
- Escape hatches, all rejected: `options relaxed_pointer_const` (per file; the JIT `readonly`
  attribute does not consult it); `T? -const` (only acts during generic binding); a
  `[c_function]` macro flipping `arg._type.flags.constant` in `apply` (possible pre-inference,
  no precedent in daslib, hides the write from LINT014/LINT031 and from the JIT).
- The repo idiom is unanimous: about 440 `var x : T?` parameters next to about 2900
  `T const?` ones, e.g. `def dot32_acc8(var acc : float?; w : int8 const?; x : int8 const?; ...)`
  (`daslib/x64_avx.das:68`).
- **Resolution.** The emitter maps C `T *p` to `var p : T?`, C `const T *p` to `p : T const?`,
  C `T * const p` to `var p : T?` (one C guarantee lost, no das spelling). The `blit` example
  becomes `def blit(src_in : uint8 const?; var dst_in : uint8?; n_in : int)`, and the callee
  copy `var dst = dst_in` is then `uint8?`. `probes/test_macros.das` pins both types.

### F4 `bool` through varargs - gap, and the trait to dispatch on

- No bool-to-integer cast exists because `ADD_NUMERIC_CASTS` (`src/builtin/module_builtin.cpp:70-85`)
  never lists `bool` as a source; bool gets only `==`, `!=` and the boolean operators
  (`module_builtin.cpp:115-117`). The policy is the design philosophy's "Explicit, not
  implicit ... no hidden type conversions (not even `int` to `float`)"
  (`skills/design_philosophy.md:49-53`, served as daslang.io's design page) and
  `datatypes.rst:362` "No bool(int): use `x != 0`". Nobody has asked for `int(bool)` (only
  issue #167, 2021, `double(bool&)`, closed).
- There is no `typeinfo is_bool` trait (the trait chain in `src/ast/ast_infer_type.cpp` has
  `is_numeric`, `is_int`, `is_float`, `is_double`, `is_enum`, `is_bitfield`...; `isNumeric`
  excludes bool). daslib dispatches on `typeinfo stripped_typename(field) == "bool"`
  (`daslib/json_boost.das:579,723`), which is immune to the constness trap because
  `stripped_typename` drops the qualifiers, and converts with `v ? 1l : 0l`
  (`daslib/sql_boost.das:203`).
- **Resolution.** P1.3 adds `static_elif (typeinfo stripped_typename(field) == "bool") { lst |> push(CVal(i = field ? 1l : 0l)) }`
  before the int-class arm.

### F5 bitfield unit alignment - design; upstream's answer is a handled type, not an annotation

- das layout is the host compiler's natural C++ layout and nothing else: field offsets
  `(off + align - 1) & ~(align - 1)` in declaration order, size tail-padded, struct alignment
  = max field alignment (`src/ast/ast.cpp:394-456`, `src/ast/ast_infer_type.cpp:477-492`,
  scalar alignments from `alignof` in `src/simulate/debug_info.cpp:196-260`). The AOT emitter
  static-asserts `sizeof`/`offsetof` against the emitted C++ struct
  (`daslib/aot_cpp.das:1523-1530`), and PR #3927's `-lib` C-ABI output asserts every offset
  too: upstream's C-compatibility strategy is "assert the natural layout", never annotate it.
- The only layout annotation is `[cpp_layout]` (inheritance padding, `module_builtin_runtime.cpp:647-659`).
  `Structure` flags carry no packing bit; no `packed`, `alignas`, `pack(`, `align_as` exists
  anywhere in `src`, `include` or `daslib`; no issue or PR ever asked. The design philosophy
  says it outright: "daslang's data layout is essentially identical to C++ (**minus
  bitfields**)". dasClangBind's generator skips C bitfields
  (`modules/dasClangBind/cbind/cbind_boost.das:602-605`) and takes every other offset from the
  C++ compiler (`addField<T, offsetof(...)>`, line 1130).
- das `bitfield` types are single-bit flags over `uint8/16/32/64` storage
  (`include/daScript/misc/arraytype.h:274-277`, PR #3874); no multi-bit widths.
- The sanctioned way to give a das program a struct with a C layout das cannot spell is a
  **handled type**: `BasicStructureAnnotation::addFieldEx(name, cppName, offset, type)`
  (`src/ast/ast_handle.cpp:157-167`) stores any offset, `getSizeOf`/`getAlignOf` are virtual,
  and the C API `das_structure_make(lib, name, cppname, sizeof, alignof)` +
  `das_structure_add_field(..., offsetof, ...)` (`include/daScript/daScriptC.h:450-468`,
  tutorial `integration_c_03_binding_types.rst`) exposes exactly that; the in-tree AST
  bindings already map C++ `bool x:1` unions onto das bitfields with `addFieldEx`
  (`src/builtin/module_builtin_ast_annotations_2.cpp:23,34,118`).
- **Resolution.** Under the MSVC ABI the documents target, `_bits0 : uint` per allocation
  unit mirrors clang exactly, and the Doom/Lua metric is unaffected. On an Itanium host the
  `[c_bitfields]` macro takes the unit width from the C-IR bit offsets (here `uint8`) and
  matches size and offsets but not the struct alignment; when that alignment matters (the
  struct nested in another, or in an array), the type is sidecar-marked marshal-only or bound
  as a dasCRuntime handled type with clang's `sizeof`/`alignof`/`offsetof`, which is upstream's
  own recipe for packed and over-aligned C structs. The `[align_as]` sidequest has no upstream
  precedent and would be the first layout annotation in the language.

### F6 parsing in a global initializer - gap

Nothing upstream: cbind's own generator parses inside `generate()` (`cbind_boost.das:271-290`).
The init script's stack is not the program's; parse inside a function.

### A stance worth knowing: `borisbat/dasCHash`

Boris Batkin's only source-to-das converter (C# to daScript, 2024) states its contract as: "the
converter does all the tedious syntax conversion, and then code is copy-pasted on an as-needed
basis ... It should mostly compile, with minor fixes required". c2das's repeatable-pipeline
rule (hand edits forbidden, sidecar for judgment) is the opposite choice; the difference is
deliberate, not an oversight, and the perf table is the reason.

### How c2das-re lives with each of these

No divergence is reported upstream and nothing in daslang is asked to change: the converter
and `c_runtime` follow the language as it is, using the idioms its author uses.

1. F1: `c_exit(code)` runs the atexit list, flushes, and ends in `exit_now(code)`; `c_abort()`
   is `exit_now(3)`; the synthesized `main` returns `c_main`'s result as `int`. Converted
   programs never call `exit`. `sidequest.md`'s "Quiet `exit()`" row is moot.
2. F2: C `memset` binds the CRT through dasCRuntime (plan section 7 already says so);
   `memset8` is the das-side spelling where `c_runtime` fills bytes itself.
3. F3: the emitter declares every pointer parameter the body writes through as `var`, and
   read-only ones as `T const?`; no option, no cast, no macro relaxes the const model.
4. F4: `to_cvalist` dispatches `bool` on `typeinfo stripped_typename(field) == "bool"` and
   pushes `field ? 1l : 0l`.
5. F5: the bitfield unit width comes from the C-IR bit offsets; a struct whose alignment a
   das struct cannot mirror is marshal-only or a dasCRuntime handled type with clang's
   `sizeof`/`alignof`/`offsetof`, the language's own recipe. `[align_as]` stays a sidequest
   nobody blocks on.
6. F6: Dumper A parses inside a function, never in module init.
