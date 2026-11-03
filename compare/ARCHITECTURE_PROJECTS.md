# compare Architecture - the real projects

Companion to `ARCHITECTURE.md` in this folder: the real projects comparison.

## The projects {#projects}

`run.das --project <name>` runs one real project of the Rust repository's `tests/manual` through
both translators and writes its entry of the capture's `projects` section, keeping every other
project and section. A project is a row of `project_table` in `projects.das`, the facts of the
project's README in the Rust checkout (`$C2DAS_RUST`, else `/root/c2das`, read in place, never
copied or built): the translation unit and the bench unit relative to the project folder (no bench
unit for a project without one), the include folders, the defines, the defines of our side alone
(`ours_defines`: plmpeg-stream's `c2da_rt_reset(...)=`, a test-runtime hook the Rust runtime
defines and the native build takes from the project's `shim.c`), further clang arguments
(`clang_extra`, after the defines), the C standard, the native build's flags and its link flags
(after the C files) the README gives, the fixture the program reads from its last argument, the id
of the project's canonical case in the Rust repository's `tests/canonical/cases.json`, whose
`expected.stdout` (`load_expected`, read at the start of a run, which exits 2 without it) is the
output the program must print, whose `translation_units`, when it lists them, are the program (the
row's unit the one among them defining `main`), and whose `c_reference.sources` are the C files the
native build compiles (else the units, else the unit; the bench's are the same with
`corpus.bench_c_entry` in place of the last, the entry), that case's
translator options, the C functions shown side by side, and the bench unit's departures from the
expected output (`bench_free_keys`, `bench_omitted_keys`, see the speed). The rows:

- wasm3: `src/all_host.c` and `src/all_host_bench.c`, `-std=c11 -Iinclude -Iupstream/wasm3/source
  -Isrc`, `-O2`, `fixtures/fib32.wasm`, the case `wasm3-fib32-std`, `--das-option "stack =
  4194304"`, and `op_Call` (an op that ends in the dispatch to the next op) and `call_fib` (the
  host's call of the module's `fib`).
- binjgb: `src/binjgb_all.c` and `src/binjgb_bench_all.c`, `-std=c11 -DNDEBUG -Iinclude
  -Iupstream/binjgb/src -Isrc`, `-O2`, `fixtures/cgb-acid2.gbc`, the case `binjgb-cgb-acid2-std`
  (60 frames: the cartridge header, `frame[i]=` hashes, `frames=60`, `ticks=`), no translator
  option, and `emulator_step_internal` (the CPU step: one instruction, or a pair of HDMA bytes;
  `execute_instruction`, the opcode switch it calls, is a few thousand lines translated) and
  `ppu_mode3_synchronize` (the PPU's pixel transfer, which renders a line). Its bench prints 300
  frames and their count and omits `width=`, `height=` and `ticks=`: free keys `frames` and the
  prefix `frame[`, omitted keys `width`, `height`, `ticks`.
- h264bsd-mp4: `src/h264_file_all.c` and `src/h264_file_bench_all.c` (the decoder graph `all.c` and
  the C file entry in one unit each), `-std=c11 -Iinclude -Iupstream/h264bsd/src -Iupstream/minimp4
  -Isrc`, `-w -O2`, `fixtures/test_640x360.mp4`, the case `h264bsd-mp4-640x360-std` (`bytes=`, a
  `frame[i]=` hash per decoded picture, `width=`, `height=`, `frames=73`), no translator option, and
  `h264bsdProcessBlock` (the inverse transform of a 4x4 residual block) and `FilterVerLumaEdge` (the
  deblocking filter across a vertical luma edge). Its native builds compile the case's own graph
  `src/all_reference.c` with `src/h264_file_reference_entry.c` or `src/h264_file_bench_entry.c`;
  the case's other two ids (`h264bsd-mp4`, `h264bsd-mp4-640x360`) run daslang entries of the Rust
  side and are not compared. Its bench prints its lines in another order and omits `bytes=`:
  omitted key `bytes`.
- plmpeg-stream: `src/plmpeg_file_all.c` and `src/plmpeg_file_bench_all.c` (the pl_mpeg graph
  `all.c` and the C file entry in one unit each), `-std=c11 -DPLM_NO_STDIO -Iinclude -Iupstream
  -Ifixtures -Isrc`, `-O2`, `fixtures/testsrc2_320x240.m1v`, the case `plmpeg-stream-320x240-std`
  (`bytes=`, `width=`, `height=`, a `frame[i]=` hash per decoded frame, `frames=59`), no translator
  option, and `plm_video_idct` (the inverse DCT of an 8x8 block) and `plm_video_decode_block` (one
  block's coefficients decoded, dequantised and added or copied into the frame). Its native builds
  compile `src/all_reference.c` with `src/plmpeg_file_reference_entry.c` or
  `src/plmpeg_file_bench_entry.c`; the case's other two ids (`plmpeg-stream`,
  `plmpeg-stream-320x240`) run daslang entries of the Rust side and are not compared. Its bench
  prints its lines in another order and omits `bytes=`: omitted key `bytes`.
- doomgeneric: `src/doom_all.c` and `src/doom_bench_all.c` (the engine graph `all.c`, its headless
  platform layer and the C entry in one unit each), `-std=c11 -Iinclude
  -Iupstream/doomgeneric/doomgeneric -Isrc`, `-O2`, `fixtures/doom1.wad` (the shareware IWAD), the
  case `doomgeneric-demo1-std` (`-timedemo demo1` on a virtual clock: a `frame[i]=` hash per
  rendered frame, `frames=70`), `--das-option "stack = 4194304"`, and `R_DrawColumn` (a wall or
  sprite column) and `R_DrawSpan` (a floor or ceiling span), the renderer's two inner loops. Its
  case names the unit as its reference source and the bench unit as its bench entry. Its bench
  prints 1000 frames and their count: free keys `frames` and the prefix `frame[`. The engine makes
  `./.savegame/` in its working folder at startup. The Eden and SDL hosts of the project are GUI
  programs and are not built; its other cases (the Eden memory model, the per-file graph) are not
  compared.
- quakegeneric: the case's 70 units (the 68 engine files of upstream's makefile, the platform layer
  `src/qg_platform.c` and the entry `src/quake_entry.c`), compiled one by one (Quake's headers have
  no include guards), `-std=c11 -Iupstream/quakegeneric/source -Isrc -include engine_config.h`
  (the forced include sends the engine's console to stderr), `-O2`, linked `-lm`, the folder
  `fixtures` (holding `id1/pak0.pak`, the shareware data) as the argument, the case
  `quakegeneric-demo1-std` (`+timedemo demo1` on a virtual clock: 100 `frame[i]=` hashes and
  `frames=100`), `--das-option "stack = 4194304"`, and `D_DrawSpans8` (a textured span of a world
  surface) and `D_DrawZSpans` (the same span's depth), which every world pixel of a frame passes
  through. Its case names no reference source and no bench, so the native build is the units and
  the project has no bench unit. The Eden and SDL hosts are GUI programs and are not built; the
  case under the Eden memory model is not compared.

Everything a run builds sits in `work/projects/<name>/`, or `<name>/` under the folder `--work`
names (the tests' scratch, so a test never meets a real run's work): `native/` (the pinned clang's builds of
both units), `ours/` and `ours_bench/` (our conversions), `rust/` and `rust_bench/` (the Rust
translations; `rust_db/` the compilation database of a project of units), and each side's lane
builds. Every program of the run (the native builds, each lane
and each bench sample of both sides, and the run each `exe` build ends with) runs with the working
folder `cwd/` there (`enter_working_folder`, every path passed on absolute), so a program writing
into its working folder writes into the run's scratch, never into the checkout. The run is capped by
the command that starts it (`prlimit --as=4294967296`), which every child process inherits: the
AOT generator's context needs more than 3 GiB of address space for the Rust modules (its 1 GiB
heap runs out under `--as=3221225472`).

The entry is `{rust_commit, rust_commit_error, daslang, date, cpu, box, samples, lanes, native,
native_compiler, address_cap, ours, rust, speed, code, functions}`: `native` the native build's
verdict, `address_cap` the soft `Max address space` of the run's `/proc/self/limits`
(`address_cap_of`: its bytes or `unlimited`, which every lane inherits),
`native_compiler` the first line of the pinned clang's `--version` (the Rust README builds with
clang-18, so the native cells are this machine's baseline, not the Rust repository's numbers),
`ours` and `rust` each `{error, lanes}` with the side's refusal and a verdict per lane of `lanes`
(`interp`, `jit`, `exe`, `aot`), `ours` also `defines`, the row's `ours_defines`, `speed`, `code` and `functions` as below. The capture's
`rust_commit` is the `HEAD` of the checkout holding the binary (`ARCHITECTURE.md` section 2).

## The verdicts {#verdicts}

The native build (the case's C files, the pinned clang, the row's flags) runs with the fixture; it
is `pass` when it prints the expected output, else `native` with the reason, and then every lane of
both sides is `refused` with `no native result`. Our side converts the unit under `linux` with a
sidecar of the project's defines, its include folders and the project folder as the program root,
every folder absolute, and `ours_defines` (a project of units with `convert_program`, in the source
layout); the converter takes no further clang argument (`clang_extra`'s forced include). The Rust side
translates it with `translate_file` (`--libc std --strict`, the case's options, the clang arguments of the row) within
600 s; a project of units through `translate_db` in the source layout over a compilation database
naming each unit with the row's clang arguments (`write_unit_commands`, as the Rust repository's
case runner writes one), the runtime module named by the translator.

Each side's lanes: `refused` with the side's error when it has no module; `compile` with the first
`error[` line when the module fails `daslang -compile-only` (with our module folders on our side,
none on the Rust side), `timeout` past that check's limit; else each lane runs with the fixture as
the program's argument (`lane_argv`: daslang over the module under `interp` and `jit`, under `exe`
and `aot` the binary `lane_binary` builds and runs once, the `aot` host's program given its
arguments after `--`, `compile` with the build's line when it leaves none: the `aot` build's
`out of heap memory` line, else its first naming an error, `aot_build_line`) and is judged
on its stdout (`run_split`; the program's stderr, doomgeneric's engine log, is apart): `timeout`
past its limit, `exit` with the code and the first line naming an error in the stderr, then the
stdout, `output` with the first line that differs from the expected text (numbered from 1, a missing
line `(none)`), `pass`. The native runs and each bench sample are judged the same way. The JIT's
`[I]` lines are not the program's output. A recorded reason names a path under the repository
relative to it (`path_free`: the JIT's warnings quote the module's absolute path), so the capture
reads the same from any checkout. A lane's limit is 120 s for a run and for the compile check, 300 s for each
`exe` or `aot` build step and the run it ends with (`COMPARE_LIMITS`).

## The speed {#speed}

The bench unit prints the unit's output or a longer run of it and two more lines, `setup_us=<n>`
(parse and load, or the emulator's creation) and `decode_us=<n>` (the timed loop). It is built
natively from its C files and converted and translated as the unit is. One run of the native bench,
its time lines dropped, is the bench's oracle (`native_bench_oracle`) when `bench_disagreement`
finds nothing: a line's key is its text before the first `=` or `:`; every line of the expected
output whose key is not in `bench_omitted_keys` is printed, equal to that line unless its key is in
`bench_free_keys`, and every other line printed has a key beginning with an entry of
`bench_free_keys`. wasm3 lists neither, so its bench must print the expected output exactly;
binjgb's prints the header and the hashes of 300 frames, doomgeneric's the hashes of 1000;
h264bsd-mp4's and plmpeg-stream's the hashes, `frames=`, `width=` and `height=`. Without that oracle
every side's cell is `{error: "bench: no native bench result: <reason>"}`. Each side's lane whose
verdict over the unit is `pass` is timed over `--samples` runs (five by default), each its own
process: the interpreter and the JIT run the module, `exe` and `aot` their binary built once
(`lane_binary`, our module folders loaded by absolute path). A run whose output without the two
lines differs from the oracle, or that lacks them, stops the cell with an error. A cell is `{setup, decode}`, each perf's
cell shape (`time` the median in seconds, `spread`, `samples`); a lane that does not pass is
`{error: "the lane does not pass: <status>"}`, a side whose bench unit does not convert or translate
`{error: "bench: <reason>"}`. The native cell is timed the same way. A project without a bench
unit times nothing: the native cell and every lane's of both sides are `{error: "no bench: the
project has no bench unit"}`. A run with `--samples 0` builds no bench and times nothing: every cell
is `{error: "not measured: the run timed no bench (--samples 0)"}` (`NOT_TIMED`), and the rendering
says the capture is not measured. Each side is timed where its
own lanes pass, whether or not the other side's do.

## The code {#code}

Each side that has a module is measured as the quality comparison measures one (`measure_side`): its
`.das` and `.das.inc` files, their non-blank lines and the readability counters over the entry
module, or over every module with the fragments it includes when there are several
(`count_program`), `compile` when the counters' compile fails. The Rust side's runtime lines are its `c2da_`
declarations named with a prefix of `RUNTIME_PREFIXES` (`c2da_rt_`, `c2da_std_`); a single project's
run has no other Rust modules to find the fixed prelude from, so the prelude counts as program code.
`functions` holds `{key, name, ours, rust}` per C function of the row, found by `function_text`
in the side's files.
`scripts/run_criteria.sh` measures its own inputs and takes no single one, so the criteria are not
computed per project.

## The rendering {#rendering}

`compare_render.das`'s `projects_text` renders the section under `### Real projects`: an intro
naming the oracle (each project's canonical case's `expected.stdout`) and each capture's stamp
(`project_stamp`: the Rust commit, the date, the box label and the address-space cap in words,
`cap_text`), the
verdicts table (per project and side, the native verdict and each lane's), one line per project
whose sidecar on our side carries defines of its own (`ours_define_lines`), one line per side and
reason for every lane that does not pass, the lanes sharing a reason named together, the bench table
under its sample count (`samples_text`: one count, `not measured` for 0, else each project's), (the
native compiler's version line without its source, the native decode seconds or the native cell's
error word as a lane's, each lane's
decode median over it, an error cell as the lane's status, `refused` for a side with no bench
module, else the error's first word), the code table (status, files, lines, the Rust runtime's lines
and each counter, `-` for a side not measured) and the functions side by side. A capture without the
section renders `No project is captured yet.` The list of where the Rust translator is ahead names
each project whose Rust side passes a lane ours does not.
