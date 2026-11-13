# doom Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds PureDOOM (Daivuk's embeddable Doom, GPL-2) as the project's headline program: the commit
is fetched at a pin and patched, never committed; the folder holds the patch, the headless host,
the sidecar, the harness and the reference checksum logs the converted build must reproduce. The
folder is the repository's GPL-2 subtree: the patch and the host carry PureDOOM's license.

## 1. File charters

- `fetch.sh` - clones PureDOOM at the commit the `puredoom:` line of `VERSIONS.md` pins into
  `fetch/PureDOOM/` unless it is there at the pin, applies every `patches/*.patch` not yet applied
  (a patch that neither applies nor is applied stops it), downloads the freedoom release zip the
  `freedoom:` line names into `fetch/wads/` unless `fetch/wads/freedoom2.wad` is there, checks the
  zip's and the wad's sha256 against the line and extracts the wad. `fetch/` is gitignored.
- `patches/0001-per-tic-checksum.patch` - the instrumentation (section 3), against the pinned
  commit.
- `patches/0002-tic-trace.patch` - the trace lines under `-DDOOM_TIC_TRACE` (section 3).
- `patches/0003-signed-ticcmd.patch` - `ticcmd_t`'s moves as `signed char` (section 3).
- `patches/0004-fine-table-overruns.patch` - the fine tables' overruns spelled out (section 3).
- `host/doom_main.c` - the headless host (section 4), the program's `main`.
- `doom_sources.das` - the program's sources (section 2): `UNITS`, `program_sources`, the folder of
  the fetched units and the sidecar's path.
- `doom.c2das` - the sidecar (section 5).
- `harness.das` - the checks and formats `run.das` applies: the pins read from `VERSIONS.md`,
  `fetch_problems` (the checkout off the pin, a patch not applied, the wad missing or of another
  hash), `missing_units`, `tic_checksum` and `frame_checksum` (the patch's formulas), `tic_lines`
  and `non_tic_lines`, the one reader of a run's or a log's tic lines, `timed_gametics`,
  `host_timing` (section 4), `demo_log` (section 6), `tic_sync` with `differing_fields` and
  `sync_summary` (section 8), `trace_lines` (section 3), `with_define` and `without_define`.
- `run.das` - the harness, run from the repository root: `daslang -load_module dasCRuntime
  -load_module c_runtime doom/run.das -- [--fetch-check] [--native] [--demo <1|2|3> [--wad
  <path>]]`. `--fetch-check` reports every problem `fetch_problems` and `missing_units` find;
  `--native` builds the program natively into `work/native/doom` (section 2); `--demo N` runs
  `-timedemo demoN` on that build over `--wad` (default `fetch/wads/freedoom2.wad`) in
  `work/run/<wad stem>/` (`demo_run.das`'s `wad_dir`), where `doom2.wad` links to the wad and
  `DOOMWADDIR` is `.`, under
  `prlimit --as` 3 GiB and a 600-second timeout, and writes the reference log
  `work/ref/<wad stem>_demo<N>.log`, refusing a run section 6 refuses. `work/` is gitignored; the
committed references under `ref/` are those files copied by hand after a reference run.
- `run.das --convert [--layout source|source-cut|single]` and `--compile-check` (section 7):
  `--convert` stages the program into `work/src/`, dumps and emits each unit alone, then converts
  the program in the layout (default `source`) into `work/<layout>/`; `--compile-check` compiles
  every module `work/<layout>/` lists with `daslang -compile-only`. Each logs a verdict per unit or
  module, the count that pass and the blocker table; either fails the run when one does not pass.
- `run.das --run [--layout L] [--tier interp|jit|exe|aot] [--demo N] [--tics N] [--wad <path>]
  [--timeout S]` (section 8): runs `work/<layout>/doom_main.das`'s `-timedemo demoN` (default
  demo 1, tier `interp`, every tic of the demo, 3600 seconds) and holds its tic lines to the
  reference log, `--tics N` also stopping the program after N tics; `--demo N` without `--run`
  stays the native run above. The run fails unless every
  compared tic is in sync and, held to the whole demo, the program ends in `timed N gametics`.
- `run.das --run --fps [--tiers T,...] [--samples N] [--demo N]` and `--readme` (section 9): `--fps`
  checks each demo (or `--demo`'s) natively and under `--tiers` (default `interp,jit`) with the sync
  build, times the speed build `--samples` runs a cell (default 3) into `results_linux.json`, a
  cell that does not stand failing the run; `--readme` renders it into `README.md`. `--speed` with
  `--native`, `--convert` or `--compile-check` takes the speed build: `work/native/doom-speed`,
  `work/<layout>-speed/`.
- `run.das --trace` with any of the above: the build, the conversion and the runs of the trace
  (section 3), apart from the reference ones. `--native` builds `work/native/doom-trace` with
  `DOOM_TIC_TRACE` after the sidecar's defines; `--demo N` runs it and writes its trace lines to
  `work/trace/<wad stem>_demo<N>.native.log`, no reference log; `--convert` and `--compile-check`
  take `work/<layout>-trace/`, converted under `work/doom-trace.c2das`, the sidecar with the
  define added; `--run` runs that conversion, writes its trace lines to
  `work/trace/<wad stem>_demo<N>.<tier>.log` and holds them to the native ones over the same
  `--tics` (a traced desync fails the run), the tic lines still held to the reference log.
- `run.das --variant <file>` with any of the above: `doom.c2das` with the knobs of
  `ports/variants/puredoom.<variant>.json` set (`ports/ARCHITECTURE_VARIANTS.md`), written to
  `work/variants/<variant>/doom.c2das`; every `work/<layout>...` folder, form sidecar and `--fps`
  capture above then lies under `work/variants/<variant>/`, the native builds staying shared.
- `demo_run.das` - the demo runs (section 8): `wad_stem`, `wad_dir`, `reference_log`, `DemoSpec`,
  `program_argv`, `run_converted` (the converted program under a tier, or the native build under
  `NATIVE_LANE`), `in_sync` and `run_report`.
- `fps.das` - the frame rate (section 9): `run_problem` and `add_run`, a run's fps into a cell,
  `FpsCapture`, `fps_command`, `lane_command`, `slowdown` and `render_fps`. It runs and reads nothing.
- `fps_run.das` - `--fps`'s runs over an `FpsPlan` (section 9): `fps_refusal`, `fps_demos`,
  `commit_label`, `new_capture`, `fps_cell`, `time_demos` and `write_fps_readme`.
- `results_linux.json` - the committed fps capture `--fps` writes (section 9).
- `ARCHITECTURE_RUN.md` - sections 8 and 9.
- `convert_check.das` - the conversion checks `--convert` and `--compile-check` apply:
  `stage_program`, `convert_units`, `compile_modules`, `first_error_line`, `classify` (the
  `BLOCKERS` table) and `blocker_table`.
- `ref/freedoom2_demo1.log`, `ref/freedoom2_demo2.log`, `ref/freedoom2_demo3.log` - the committed
  reference logs (section 6).
- `REVIEW.das` - the mechanical gate: nothing under `fetch/` or `work/` and no `.wad` file of the repository is
  tracked.
- `tests/test_harness.das` - `harness.das` over stand-ins: the checksums on known values, tic 0
  of every reference log against the zeroed screen, the pins, `fetch_problems` over a checkout
  built from the patch's own pre-image, to which the patch applies, and a stand-in wad,
  `missing_units`, `demo_log`'s format and refusals, the desync's differing fields, the host's
  line, `without_define`, and the sidecar through the converter's `read_sidecar`.
- `tests/test_demo_run.das` - `demo_run.das` over a stand-in program, a das module that checks its
  `argv` and `$DOOMWADDIR/doom2.wad` and prints the tic lines an environment variable asks for,
  held to a four-tic stand-in log: sync, the comparison bounded by `--tics` and the program
  stopped there, the first desynced tic, a missing and a doubled tic, a run past the demo's end,
  an early exit with its first error line, every tic in sync then an exit or a timeout without
  the timedemo line, a timeout, the converted program's module folders, a wad link that fails, no
  reference log, no entry module, no wad and an empty log, the host's timing line read from a run;
  the native lane over a shell stand-in, with and without the build, and speed runs held to the
  demo's end. Only the `interp` tier runs there.
- `tests/test_fps.das` - `fps.das` over fixed runs and captures: a run's fps and each reason it
  gives none, a desync among them, the median and spread, the suspect bar at and above 20%, the
  rendered table, a missing cell, the lane commands, the recorded command with and without
  `--demo` and the capture's JSON shape.
- `tests/test_fps_run.das` - `fps_run.das` over the stand-ins, every function of it, and `run.das`
  as a child process: `--fps` against the plain `--run`, and a refusal.
- `tests/_stand_in.das` - the stand-ins the demo-run tests share: the das program, the native
  script and the spec of a run of them.
- `tests/test_convert.das` - `convert_check.das` over a stand-in program (two units that link, one
  the dumper refuses, a host outside their folder): the staging, the units alone, the program's
  modules compiled alone, a module that fails, and the classification.
- `tests/test_host.das` - `host/doom_main.c` converted over a stand-in Doom (the four calls the
  host makes, the fourth update ending in the timedemo's line and the exit callback) and run under
  every tier, the JIT uncached: the C exit's code 255 and timing line, the same under
  `-return-from-main` with no F75 warning, `-tics` with it ending in 0; a trailing `-tics` ignored,
  a Doom that never exits ending in 2 with and without the flag (JIT), and under `interp` the
  profiler's summary printed under the flag and not through C exit.

The IWAD is freedoom2.wad (BSD), the fetched one every committed log is recorded on; `--wad`
takes another path for a local run.

## 2. The program

PureDOOM's multi-file form: the 62 `.c` files of `src/DOOM/`, in the byte order of their names (the
order of PureDOOM's CMake glob), then `host/doom_main.c`, which includes `DOOM.h` by its path
relative to `host/`. The defines are the sidecar's: `DOOM_IMPLEMENT_PRINT`, `_MALLOC`,
`_FILE_IO`, `_EXIT` and `_GETENV` select PureDOOM's libc-backed callbacks (print to stdout,
malloc, stdio files, exit, getenv), `DOOM_TIC_CHECKSUM` the patch's tic lines; the time callback
is the host's, so `DOOM_IMPLEMENT_GETTIME` is not defined, and neither is `DOOM_IMPLEMENT_SOCKETS`.
The native build is the pinned clang (`VERSIONS.md` libclang) at `-O2 -w` with those defines, `-lm`
linked. PureDOOM has no `-iwad`: it opens `$DOOMWADDIR/doom2.wad`, which is why the harness links
the chosen wad under that name.

## 3. The patches

`0001-per-tic-checksum.patch`: hunks in five files against the pin. `g_game.c` and `d_main.c`, under `-DDOOM_TIC_CHECKSUM`:
`G_Ticker` ends by storing `gametic`, the tic just run (the caller increments it after), and the
tic's checksum; `D_DoomLoop`, once `D_Display` has drawn that tic, prints one line through
`doom_print`, `tic=<gametic> cs=<8 hex digits> fb=<8 hex digits>`; without the define the build
prints nothing more. The line is printed whole after the frame, so no other output can split it
and `tic_lines` stays the one reader; a run that dies drawing a tic prints no line for it. Both
checksums are the 32-bit FNV-1a (offset basis 2166136261, prime 16777619; per byte
`cs = (cs ^ b) * prime` modulo 2^32). `cs` runs over the little-endian bytes of six 32-bit values
in order: `players[0].mo->x`, `y`, `z`, `angle` (each 0 while `players[0].mo` is null),
`players[0].health` and `prndindex`, the index `P_Random` steps (PureDOOM's `rndindex` is
`M_Random`'s, which the menus and the screen melt step, so it stays out). `fb` runs over the
`SCREENWIDTH * SCREENHEIGHT` bytes of `screens[0]` as `D_Display` leaves it: the frame of the tic,
or, on a tic that starts a screen melt, the screen the melt starts from (`wipe_EndScreen` puts it
back); the melt's own steps run no tic and print nothing. Every tic of a timedemo has its line.

`w_wad.c`, `r_data.c` and `i_video.c` make the frame a function of the game alone, so the
reference frames are the patched source's, not vanilla's, at the pixels below. A column
drawer reads `dc_source[(frac >> FRACBITS) & 127]`, up to 127 bytes past a column's start: a wall
taller than its texture (freedoom2's 16-row `CRATINY` as a bottom texture) or a sprite post whose
first row rounds to row -1, which `& 127` wraps to 127. Past the end of a lump that read the
zone's next block header, its pointers among them, so the frame of such a tic changed with the
heap's addresses from run to run (3 of demo1's 2664 tics over four runs). So `W_CacheLumpNum`
allocates each lump with 128 zero bytes past its end, `R_GenerateComposite` zeroes a composite
texture with the same slack, and `I_InitGraphics` zeroes the screen, which tic 0 does not draw.
The game state does not read those bytes: `cs` is the same with and without the hunks.

`d_main.c`, unconditionally: `-playdemo` and `-timedemo` return from `D_DoomMain` after
`I_InitGraphics`. PureDOOM's `D_DoomLoop` runs one tic and returns where vanilla's never returns,
so `D_DoomMain` went on into the title loop (a single-player demo) or `G_InitNew` (a multiplayer
one, `demo2` of freedoom2), which replaced the demo; with the return the host's loop plays the
demo from its first tic. The fix is unconditional, since a timedemo is P6.7's benchmark too.

`0002-tic-trace.patch`, `p_tick.c`: under `-DDOOM_TIC_TRACE`, `P_Ticker` ends by printing
`trace=<gametic> x=<hex> y=<hex> z=<hex> ang=<hex> hp=<d> prnd=<d>`, the six values `cs` hashes, so
a desync names the value that differs; `tic_lines` skips the line and no reference log is
recorded with the define.

`0003-signed-ticcmd.patch`, `d_ticcmd.h`: `ticcmd_t`'s `forwardmove` and `sidemove` are `signed
char`, as in Chocolate Doom. A demo stores a backward move or a strafe left as a negative byte;
read back through a plain `char` it stays negative only where `char` is signed, and the
converter's dialect makes plain `char` unsigned (`docs/probe-findings.md` F17), under which a
plain field reads a strafe of -40 as 216. The native build at `-O2` with or without
`-funsigned-char` prints the reference lines of all three demos with the patch.

`0004-fine-table-overruns.patch`, `r_main.c` and `r_segs.c`: `R_ScaleFromGlobalAngle` indexes
`finesine` by an `int` angle shifted right, negative past `ANG180` (demo1's tic 255 reaches
-4096), and `R_RenderSegLoop` indexes `finetangent[angle]` with `angle` up to 8191, past its 4096
entries. `tables.c` defines `finetangent` right before `finesine`, so the native build reads the
other table; das range-checks both reads and panics. The patch spells the neighbouring read out,
`finetangent[FINEANGLES / 2 + i]` for a negative `i` and `finesine[angle - FINEANGLES / 2]` past
`finetangent`'s end, the values the native build reads: its lines, frames included, are the same.

## 4. The host

In `ARCHITECTURE_RUN.md`: the headless host, its arguments and its timing line.

## 5. The sidecar keys

- `defines`: section 2's six.
- `marshal`: the WAD's on-disk records the C reads in place from a lump's bytes through a cast
  pointer (field widths in bits; `c8` is `char[8]`): `mapvertex_t` (VERTEXES, 4 bytes: x i16, y i16),
  `mapsidedef_t` (SIDEDEFS, 30: textureoffset i16, rowoffset i16, toptexture c8, bottomtexture
  c8, midtexture c8, sector i16), `maplinedef_t` (LINEDEFS, 14: v1, v2, flags, special, tag i16,
  sidenum i16[2]), `mapsector_t` (SECTORS, 26: floorheight, ceilingheight i16, floorpic c8,
  ceilingpic c8, lightlevel, special, tag i16), `mapsubsector_t` (SSECTORS, 4: numsegs, firstseg
  i16), `mapseg_t` (SEGS, 12: v1, v2, angle, linedef, side, offset i16), `mapnode_t` (NODES, 28: x,
  y, dx, dy i16, bbox i16[2][4], children u16[2]), `patch_t` (every picture lump's header, 40:
  width, height, leftoffset, topoffset i16, columnofs i32[8] indexed up to `width`), `post_t`
  (`column_t` is its typedef: 2, topdelta u8, length u8, at any byte offset of a patch),
  `mappatch_t` (10: originx, originy, patch, stepdir, colormap i16) and `maptexture_t` (a TEXTURE1
  or TEXTURE2 entry, 22 + 10 per patch, at the offset the lump's directory names, which is 2-byte
  aligned only: name c8, masked i32, width, height i16, columndirectory i32, patchcount i16,
  patches `mappatch_t[1]` indexed up to `patchcount`). Left out, since the C holds them as values
  or takes their address: `mapthing_t` (THINGS, 10: x, y, angle, type, options i16; read in place
  by `P_LoadThings`, but `playerstarts` and `deathmatchstarts` are arrays of it, `mobj_t.spawnpoint`
  a field and `&playerstarts[i]` an address), `wadinfo_t` (the header, 12: identification c4,
  numlumps, infotableofs i32; read into a local through its address) and `filelump_t` (the
  directory, 16: filepos, size i32, name c8; a local `singleinfo` addressed for a lone lump file).
  The BLOCKMAP lump is read as `short`s, no record.
- `over_indexed`: `patch_t.columnofs`, `maptexture_t.patches` and `texture_t.patches`, the trailing
  arrays the C indexes past their declared length over a longer lump or allocation.
- `padded`: `visplane_t.top` and `visplane_t.bottom`, whose index `R_DrawPlanes` takes one past
  either end (`pl->top[pl->minx - 1]`, `pl->top[pl->maxx + 1]`, and `R_MakeSpans`'s arguments
  `top[x - 1]`, `bottom[x - 1]` up to `maxx + 1`) into the flanking `pad1` to `pad4` bytes.
  `openings`, `floorclip`, `ceilingclip`, `negonearray` and `screenheightarray` need no entry: the
  C reaches them past their start only through pointers (`lastopening - rw_x`, `mfloorclip`),
  which das indexes unchecked.
- No `stack` or `alloca_limit`: no unit calls `alloca` (the keys size an alloca arena's module),
  and the native build at `-O0` plays all three demos under `ulimit -s 16` (a 16 KiB C stack;
  12 KiB fails), well inside the emitter's 8 MiB default.
- No entry for `actionf_t`: a union of function pointers is a `[c_union]` like any other
  (`docs/probe-findings.md` F32).

## 6. The reference logs

A reference log is the `tic=` lines of a `-timedemo` run in order under one `# ` header line: the
PureDOOM pin with each patch and its sha256, clang's version line, the build's compiler, flags and
defines, the wad's name and sha256, the demo and the exit code. `demo_log` refuses a run that does
not end in the `timed N gametics` line (a crash, a hang the timeout kills) or prints other than `N`
tic lines. `ref/` holds the logs of demo1, demo2 and demo3 on freedoom2.wad: 2664, 5444 (a
two-player demo, `consoleplayer` 1) and 2743 tics; the native build at `-O0` prints the same lines
as at `-O2`, and a run prints the same lines as the next, address randomization on. They are the oracle of the converted build's demo sync (`docs/implementation_order.md`
P6.5).

## 7. The conversion

`--convert` stages the program into `work/src/`: every file of `src/DOOM/` and the host, its
`#include` of `DOOM.h` spelled bare. The dumper takes a declaration as the program's when its
file lies under the unit's own folder (`converter/ARCHITECTURE_DUMPER.md`, "The program's
files"), and the host in `host/` would hold PureDOOM's headers external; in one folder every
header is the program's and the output folder is flat.

Two stages report. Each unit alone: dumped under the sidecar's defines, then emitted under the
sidecar with its `over_indexed` and `padded` entries narrowed to the records the unit declares, since the emitter
refuses an entry naming a record it does not see. A unit alone has no binding for a function another
unit defines, nor a length for an array another unit defines (`extern T a[];`); an emitter error
naming one is marked `link-bound:` and classed apart, and the emitter stops at its first error, so
it hides what follows it in that unit. Then the program: `convert_program` in the layout, which
stops at the first unit the dumper refuses, since the link needs every unit. `--compile-check`
compiles each module of `work/<layout>/`'s module list alone, in a `daslang -compile-only` process
with the converted program's module folders.

`classify` names the construct of a first line by the `BLOCKERS` fragments, P6.1's numbered
findings among them (finding 3: an over-indexed trailing array inside a marshal record); a line no
fragment matches is `new:` with its stage and locations dropped. `blocker_table` counts the units
or modules per construct.

At the pin, 11 of the 63 units pass alone; 52 stop at a function or an array another unit
defines, which the link binds. The whole program passes the dumper, the layout and the emitter,
past the gotos into a branch body P7.7 lowers and the array and record fields of a marshal record
P6.3e and P6.3i lower (`patch->columnofs[col]`, `maptexture_t.patches`), the offset idiom
through a null pointer (`d_net.c:103`'s `&(((doomdata_t*)0)->cmds[netbuffer->numtics])`) and the
sum with its count on the left (`p_pspr.c:655`'s `flashstate + psp->state`) P6.3j lowers. Its
`source` program passes the converter's compile check: `--compile-check` compiles all 39 modules
alone, `m_menu.c`'s menus among them, whose function values reach their own globals back
(`MainMenu` -> `M_NewGame` -> `EpiDef` -> ... -> `MainMenu`), das's initialization loop, so the
emitter stores them at module init (`converter/ARCHITECTURE_EMITTER_AGGREGATES.md`,
Initialization loops). The harness runs the native build with `--demo` and the converted program
with `--run` (section 8). The whole-program
conversion needs more than 3 GiB of address space: under `prlimit --as=3G` daslang dies with
SIGSEGV on an allocation failure, so the harness runs uncapped in a `heavy` scope of its own.

The partition (`converter/ARCHITECTURE_LAYOUT.md`, the cut and the edge census): the `source` layout
holds 51 of the 63 units in one cluster and 3 headers (`d_player_h`, `p_mobj_h`, `r_defs_h`) in
another, 39 modules. The 51-unit cluster has 438 edges: 326 carry calls (698 symbols), 218 objects
(600), 14 function addresses (93), none a type; 209 carry calls alone. `source-cut` cuts 72 of them
(132 symbols over 65 functions, 297 call sites; 38 symbol edges into `i_system`, `I_Error` most, 33
into `z_zone`, 25 into `p_spec`) and leaves 36 units in one cluster, 55 modules with the link
module. The 36 are the census's cluster with every function forward-declared: objects (`players`,
`consoleplayer`, `sectors`, `DOOM.c`'s `doom_print` and `error_buf`) tie 29 of them, and function
addresses tie in 7: `info.c`'s `states` take the `A_*` actions' of `p_enemy` and `p_pspr`,
`p_saveg.c` the `T_*` thinkers' of `p_doors`, `p_floor`, `p_lights` and `p_plats`, and `info` is
reached by objects (`states`, `mobjinfo`); with objects forward-declared too no unit cycle is left.
Every render and sound unit and the play simulation's per-tic core (`p_map`, `p_maputl`, `p_mobj`,
`p_sight`, `p_enemy`, `p_tick`) are inside the 36, so no call among them is late-bound; the heaviest
cut edge is `r_data -> z_zone` (21 call sites). The sidecar sets no `layout` object: no profile
exists until the converted build runs a demo (`docs/implementation_order.md` P6.4), and a
`layout.threshold` only keeps cut edges, which joins their units to the cluster (a threshold of 10
leaves 41 units); the defaults give the smallest cluster the cut can reach.

## 8. The converted run and 9. The frame rate

In `ARCHITECTURE_RUN.md`: the converted program's demo run held to the reference log (section 8),
and the frame rate `--fps` measures and publishes (section 9).
