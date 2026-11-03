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
- `host/doom_main.c` - the headless host (section 4), the program's `main`.
- `sources.das` - the program's sources (section 2): `UNITS`, `program_sources`, the folder of
  the fetched units and the sidecar's path.
- `doom.c2das` - the sidecar (section 5).
- `harness.das` - the checks and formats `run.das` applies: the pins read from `VERSIONS.md`,
  `fetch_problems` (the checkout off the pin, a patch not applied, the wad missing or of another
  hash), `missing_units`, `tic_checksum` (the patch's formula), `tic_lines` and `non_tic_lines`,
  the one reader of a run's or a log's tic lines, `timed_gametics`, `demo_log` (section 6), and `tic_sync` with
  `sync_summary` (section 8).
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
  reference log; `--demo N` without `--run` stays the native run above. The run fails unless every
  compared tic is in sync and, held to the whole demo, the program ends in `timed N gametics`.
- `demo_run.das` - the demo runs (section 8): `wad_stem`, `wad_dir`, `reference_log`, `DemoSpec`,
  `run_converted`, `in_sync` and `run_report`.
- `convert_check.das` - the conversion checks `--convert` and `--compile-check` apply:
  `stage_program`, `convert_units`, `compile_modules`, `first_error_line`, `classify` (the
  `BLOCKERS` table) and `blocker_table`.
- `ref/freedoom2_demo1.log`, `ref/freedoom2_demo2.log`, `ref/freedoom2_demo3.log` - the committed
  reference logs (section 6).
- `REVIEW.das` - the mechanical gate: nothing under `fetch/` or `work/` and no `.wad` file of the repository is
  tracked.
- `tests/test_harness.das` - `harness.das` over stand-ins: the checksum on known values, the pins,
  `fetch_problems` over a checkout built from the patch's own pre-image, to which the patch
  applies, and a stand-in wad, `missing_units`, `demo_log`'s format and refusals, and the sidecar
  through the converter's `read_sidecar`.
- `tests/test_demo_run.das` - `demo_run.das` over a stand-in program, a das module that checks its
  `argv` and `$DOOMWADDIR/doom2.wad` and prints the tic lines an environment variable asks for,
  held to a four-tic stand-in log: sync, the comparison bounded by `--tics`, the first desynced
  tic, a missing and a doubled tic, a run past the demo's end, an early exit with its first error
  line, every tic in sync then an exit or a timeout without the timedemo line, a timeout, the
  converted program's module folders, a wad link that fails, no reference log, no entry module,
  no wad and an empty log. Only the `interp` tier runs there.
- `tests/test_convert.das` - `convert_check.das` over a stand-in program (two units that link, one
  the dumper refuses, a host outside their folder): the staging, the units alone, the program's
  modules compiled alone, a module that fails, and the classification.

The IWADs: freedoom2.wad (BSD) is the fetched one every committed log is recorded on;
`doom2.wad`, id Software's commercial IWAD, is user-supplied, local only, kept under `wads/`
by convention and never fetched or committed (`.gitignore` ignores `doom/wads/*.wad`); the
harness takes it through `--wad` and no log of it is committed.

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

## 3. The patch

Two hunks against the pin. `g_game.c`: under `-DDOOM_TIC_CHECKSUM`, `G_Ticker` ends by printing
`tic=<gametic> cs=<8 hex digits>` through `doom_print`, `gametic` being the tic just run (the
caller increments it after); without the define the build prints nothing more. The checksum is the
32-bit FNV-1a (offset basis 2166136261, prime 16777619; per byte `cs = (cs ^ b) * prime` modulo
2^32) over the little-endian bytes of six 32-bit values in order: `players[0].mo->x`, `y`, `z`,
`angle` (each 0 while `players[0].mo` is null), `players[0].health` and `prndindex`, the index
`P_Random` steps (PureDOOM's `rndindex` is `M_Random`'s, which the menus and the screen melt step,
so it stays out). `d_main.c`: `-playdemo` and `-timedemo` return from `D_DoomMain` after
`I_InitGraphics`. PureDOOM's `D_DoomLoop` runs one tic and returns where vanilla's never returns,
so `D_DoomMain` went on into the title loop (a single-player demo) or `G_InitNew` (a multiplayer
one, `demo2` of freedoom2), which replaced the demo; with the return the host's loop plays the
demo from its first tic. The fix is unconditional, since a timedemo is P6.7's benchmark too.

## 4. The host

`host/doom_main.c` installs a virtual clock (`doom_set_gettime`: it starts at 0 and advances
1/35 s per update) and an exit callback that flushes stdout and exits with Doom's code, calls
`doom_init(argc, argv, 0)`, then `doom_force_update` in a loop, at most 2000000 times. Each update
runs one game tic (PureDOOM's `singletics` is on) or, while the screen melts, one wipe step that
runs none; no wall time reaches the game, so a run repeats tic for tic. A `-timedemo` run ends in
`I_Error`'s `Error: timed <N> gametics in <M> realtics` and exit code 255; `M` counts virtual tics.

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
PureDOOM pin with the patch and its sha256, clang's version line, the build's compiler, flags and
defines, the wad's name and sha256, the demo and the exit code. `demo_log` refuses a run that does
not end in the `timed N gametics` line (a crash, a hang the timeout kills) or prints other than `N`
tic lines. `ref/` holds the logs of demo1, demo2 and demo3 on freedoom2.wad: 2664, 5444 (a
two-player demo, `consoleplayer` 1) and 2743 tics; the native build at `-O0` prints the same lines
as at `-O2`. They are the oracle of the converted build's demo sync (`docs/implementation_order.md`
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
Initialization loops). The harness runs the native build alone (`--demo`); the converted program
has no run mode yet. The whole-program
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

## 8. The converted run

`run_converted` runs the converted program's entry module, `doom_main.das` in every layout (the
module holding `main`), through `converter/tiers.das`'s `run_tier` from the repository root with
the converted program's module folders and the native run's C `argv`, `-timedemo demoN`.
`run_tier` takes no environment for the child, so the harness process sets `DOOMWADDIR` to the
wad's run folder, absolute, and the program inherits it: the wad opens as in the native run. A
wad link that fails stops the run. The `exe` and `aot` builds go to `work/run/<wad stem>/<layout>/`,
one folder per layout. The reference log is `<wad stem>_demo<N>.log` in `ref/`, else in `work/ref/` (a local
reference, a `doom2.wad` one among them). The run's tic lines, a timed-out run's included, since
`run_and_capture` keeps the output a killed process wrote, are held to the log's by `tic_sync`:
the first `--tics` lines, or all of them, a run that goes on past the demo's last tic desyncing
there. Held to the whole demo, a run is in sync only when it also ends, not timed out, in the
`timed N gametics` line with N the log's tics, the end `demo_log` requires of a native run; under
`--tics` an exit after the compared tics passes, its exit code reported. The report names the first desynced tic (expected against got) or `N tics in sync`, a run
short of the compared tics, the exit code or the timeout, the first error line of a run that did
not end in the `timed N gametics` line (`first_error_line`, matching `error` or `exception` in any
case, since PureDOOM's `I_Error` text starts `Error: ` and a daslang panic `EXCEPTION: `), and the seconds per 35 tics over the whole process, start
included: a sanity number, not P6.7's measure. The host has no tic cap, so `--tics` bounds the
comparison, not the run: the program plays the demo to its end or to `--timeout`.
