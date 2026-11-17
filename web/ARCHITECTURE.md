# web Architecture

Read `ARCHITECTURE_COMMON.md` (repo root) first - its contract binds this document. The folder
holds the browser demos of the ports repository (`lookibed/c2das-ports`): a converted program
compiled ahead of time to wasm64 by daslang and served as a static site from that repository's
GitHub Pages. The converted code is never edited here; the folder holds only the host each
program runs under in a browser and the page around it.

## 1. File charters

- `puredoom/main_web.das` - PureDOOM's browser host (section 3). It requires the processed
  variant's modules by bare name, so it compiles only beside them, in the project
  `scripts/build_web.sh` stages.
- `puredoom/tic_digest.das` - the fold of Doom's per-tic checksum lines (section 3), a module of its
  own so `tests/test_web_tic_digest.das` runs it on the pin and checks the page's JS fold against it.
- `puredoom/doom_synth.das` - the music synthesizer (section 5); it needs only math, so
  `tests/test_web_doom_synth.das` runs it on the pin.
- `puredoom/doom_midi.das` - the MIDI file player (section 5), tested by `tests/test_web_doom_midi.das`.
- `puredoom/shell.html` - the page emscripten fills with its loader (`daspkg`'s
  `release_web_shell`): the WAD (section 4), the play and timedemo buttons, the program's output,
  the timedemo's fps and the check of its checksums against the native build's log.
- `puredoom/.das_package` - the release of the staged project: the wasm entry, the shell, one link
  flag (`-sMAXIMUM_MEMORY=2GB`).
- `puredoom_c/main_web.c` - the C twin of `puredoom/main_web.das` for the C baseline (section 6);
  `puredoom_c/tic_digest.h` its checksum fold, the twin of `tic_digest.das`.
- `quake/main_web.das` - quakegeneric's browser host (section 7), staged beside the generated
  `quake_entry.das`; `quake/shell.html` its page; `quake/.das_package` its release;
  `quake/expected_frames.das` writes the reference frames out of the Rust repository's cases.
- `site/index.html` - the site's landing page, a list of the demos.
- `site/coi-serviceworker.js` - cross-origin isolation (section 2).
- `site/pages.yml` - the deploy workflow the ports repository's `gh-pages` branch carries (section 4).
- `scripts/build_web.sh` (repository root) - the build: checks, staging, release, the site, and with
  `--pages` the `gh-pages` checkout (`--from <site>` fills it from a site built before, without a
  build). `tests/test_build_web.das` holds its refusals and the `--pages` path.

## 2. The build

The wasm is cross-compiled by daslang's libc++ + C++-exceptions host (`VERSIONS.md`, the
emscripten line), built by daScript's `web/build_wasm_host.sh` at the pin's own commit; the build
refuses a host at another commit, one that does not link libc++, and an emscripten other than
5.0.7. The pin itself has no dasGlfw, so `scripts/preflight.sh` does not list this folder: the
build runs the host's das-fmt `--verify` and lint over `main_web.das` before it releases.

The staged project (`<out>/stage/puredoom`) holds copies, never links: `src/` is
`puredoom-readable/processed/doom` of the ports checkout with `main_web.das` beside it,
`modules/c_runtime` the ports checkout's vendored runtime (the one its modules were converted
against), and `modules/dasCRuntime` this tree's host-side `crt` (`scripts/build_crt.sh
--libcxx-host`) with its package pointed at this tree's `dasCRuntime/`. The cross-compile writes a
`.das_module.emscripten.manifest` beside every module it loads, so a link would leave that file in
the ports checkout. The build deletes the host's staged `crt` archive first, since `daspkg` never
refreshes one, so the archive is always this tree's.

`daspkg release wasm` links with its own defaults: wasm64 objects lowered to a 32-bit memory
(`-sMEMORY64=2`), WebGL2, wasm exceptions and `-pthread`. A threaded module instantiates only on a
cross-origin-isolated page, and GitHub Pages sets no response headers, so the site carries a
service worker that adds COOP and COEP to every same-origin response; the first visit reloads
once, after the worker controls the page.

The site's `puredoom/build.json` names the c2das-re commit (its `crt` and host), the ports commit,
the commit that converted the processed modules, the daScript commit and the emscripten version;
the page prints them. A tree with uncommitted changes is named `<sha>-dirty`.

## 3. The PureDOOM host

The browser drives a cross-compiled program through daslang's web lifecycle: `init` once, then
`update` on every animation frame until it returns false, then `shutdown`; `main` is never called
there. `main_web.das` keeps a `main` that runs the same three in a loop, for a desktop run.

- Drawing: `doom_get_framebuffer(4)` expands the 320x200 palettized screen to RGBA; the host
  uploads it into one texture and draws a quad letterboxed to 4:3 through GLFW and OpenGL, which
  the wasm build maps to the canvas and WebGL2.
- Input: the keys Doom's defaults and menus read (arrows, Ctrl, Space, Shift, Alt, Enter, Escape,
  Tab, letters, digits, F1-F12 and a few punctuation keys) and the left mouse button are polled
  through GLFW each frame into one state per Doom key (left and right Ctrl are one key, down while
  either is) and posted as Doom key and button events on a change. Emscripten's GLFW releases every
  key when the page loses focus, so a held key does not stay down.
- Time: PureDOOM's default clock reads 0, so the host always sets one. Play mode keeps a game clock
  that each frame advances by the real time since the last, at most 100 ms (daslang's own clock, not
  `crt`'s `clock()`, which emscripten under `-pthread` can return negative), and calls `doom_update`,
  which runs the tics due. A hidden tab gets no animation frames; the cap keeps its return from
  running every tic it missed in one frame. The clock starts at 1 s: `I_GetTime` takes its base from
  the first nonzero second it reads.
- Timedemo (`-timedemo demoN`): the clock is virtual and advances one tic per
  `doom_force_update`, as the native host `doom_main.das` does, so the checksums are the native
  ones. Each frame runs updates for 12 ms, then draws once. The fps the page reports is the tics
  over the seconds spent inside those updates; drawing and the wait for the next frame are outside
  it, as the native host's timed line has no drawing.
- Checksums: Doom prints a `tic=` line per tic (game-state and frame hash) in pieces, the first
  exactly `tic=`; the host folds every such line, newline included, into an FNV-1a 32 digest and a
  count (`tic_digest.das`) instead of printing it, and prints both when Doom exits. The page folds the `tic=` lines of the native build's log
  (`puredoom-readable/ref/freedoom2_demo1.log`, shipped as `demo1_ref.log`) the same way and
  compares.
- Frame rate: once a second the host prints `host: stats <frames> <tics> <renders> <seconds>`: the
  animation frames it presented, the tics Doom ran and the frames Doom rendered; the page shows them
  over the picture. Doom renders one frame per tic, so 35 a second, whatever the display rate.
- Uncapped (`-uncapped`, the page's checkbox or `?uncapped=1`): tics stay at 35 a second and each
  animation frame spends 10 ms (at most 60% of the last frame interval) rendering Doom's view again between tics (`D_Display`, skipped during
  a wipe); in a timedemo, one more render after every tic. PureDOOM has no render interpolation, so
  such a frame shows the state the last tic left: the rate is the renderer's throughput, and motion
  stays at 35 steps a second. Rendering touches no game state: a timedemo with a render after every
  tic keeps every checksum.
- Exit: Doom's exit callback (the end of a timedemo, the quit menu) prints `host: Doom exited`
  and longjmps out of the update through `c_runtime/setjmp`; that `update` returns false and the page
  says to reload. A das panic that is no longjmp is rethrown with its own message (`c_jmp_rethrow`).

## 4. The WAD

No WAD is in any repository or branch. The page loads `puredoom/freedoom2.wad` from its own
origin; the deploy workflow (`site/pages.yml`, run by the `gh-pages` branch with Pages' source set
to GitHub Actions and the `github-pages` environment allowing that branch) downloads Freedoom 0.13.0 from its official release, checks the zip's and the
WAD's sha256 (the sums `fetch_wad.sh` of the ports repository checks) and adds the WAD to the Pages
artifact only. The page checks the sha256 again in the browser and names the release. A page
cannot fetch the release itself: the release host sends no CORS headers. A file picker takes the
user's own `freedoom2.wad` or release zip, held to the same sha256. Only Freedoom (BSD) is
served, never a commercial id Software WAD. `scripts/build_web.sh --pages` refuses a site holding a
`.wad`, `.zip` or `.pak` and checks the checkout again before it commits.

## 5. Sound

The host streams one stereo PCM stream to dasAudio (`play_sound_from_pcm_stream`, `append_to_pcm`),
which mixes it into the browser's audio through its AudioWorklet backend. Each 512-frame block at
11025 frames a second is Doom's own sfx mix (`doom_get_sound_buffer`, int16) with the music
synthesizer added, clamped to the float range. The host feeds by the stream's own queue, which
dasAudio publishes into a status box (`set_status_update`): every frame it adds blocks until about
2048 frames are queued. So the sound never lags further than that; a stall or a hidden tab leaves a
gap, not a backlog; and a suspended page, whose audio pulls nothing, queues nothing. A timedemo
streams no sound.

Music: PureDOOM's own player (`doom_tick_midi`, ticked 140 times a second, each tick before the
frames it covers: `music_block` in `doom_midi.das`) reads only Doom's MUS format, and every music
lump of Freedoom is a MIDI file, so the host also plays those: it follows the song Doom plays (the
`S_music` entry holding data, which `S_ChangeMusic` sets and `S_StopMusic` clears), passes the
engine's messages for the change first, parses a MIDI lump with `doom_midi.das` into messages timed
by the file's tempo map, and hands them to the synthesizer as they fall due, every channel reset at a
song's start; a song loops at its last track's end (Doom's loop flag is private to its sound
module), and the game's pause holds it with its notes released. Both players feed `doom_synth.das`,
a small General MIDI synthesizer: one waveform and envelope per instrument family, shaped noise and
pitch sweeps for the percussion channel, whose note-offs it ignores (a drum sounds out its decay), 24
voices, a full set stealing a released voice first and never one still rising. Doom's music volume
reaches a MUS song as the engine's own volume messages and a MIDI song as the synthesizer's gain;
while a MIDI song plays the engine's volume messages are dropped, so the file keeps its own mix.

The page starts the browser's audio on the first click or key (browsers start audio only from a
gesture), and its button suspends and resumes it, remembered in the browser's storage: a muted
page's audio context ignores every other request to resume, the program's own included. The C
baseline (section 6) has no sound: it exists for the timedemo comparison.

## 6. The C baseline

`puredoom/doom_c.html` is the same game built from PureDOOM's own C at the pinned commit with this
repository's patches (`doom/fetch.sh`), under `puredoom_c/main_web.c`, the C twin of
`puredoom/main_web.das`: the same clocks, frame budgets, key table, checksum fold, uncapped mode and
output lines, so the same page (`puredoom/shell.html`), the same WAD and the same reference log serve both. The build passes the sidecar's defines
(`doom/doom.c2das`, the per-tic checksums included, as the converted code has them) and the link
flags `daspkg release wasm` gives the daslang build: wasm64 lowered by `-sMEMORY64=2`, SIMD, wasm
exceptions, `-pthread` with the same worker pool of 16, WebGL2 through GLFW, the same memory limits.
The differences, each in the C build's favour or neutral: `-O3` where daspkg links at `-O2` (the
daslang objects are optimized by daslang's own LLVM pipeline before the link); no
`-sGL_ENABLE_GET_PROC_ADDRESS`, `-sAUDIO_WORKLET`, `-sWASM_WORKERS` or
`-Wl,--wrap=emscripten_futex_wait`, which serve daslang's GL binding and audio; and
`-sSUPPORT_LONGJMP=wasm` for C's `setjmp`. The build writes which build a page is into its
`doom-build` meta. The page keeps the last timedemo of each build in the browser's storage (rate,
tics, sync, mode) and prints the daslang build's time over the C build's only for two runs in sync
over the same tics in the same mode.

## 7. quakegeneric

`quake/quake.html` is c2das-ports' `quakegeneric/readable` under `quake/main_web.das`. The generated
tree is staged whole (`game/`) and the host sits beside its entry `quake_entry.das`, requiring the
same modules; it keeps the generated platform layer (`qg_platform.das.inc`, part of the engine's
cluster: the frame hashes and the palette, no input) and drives the engine from outside it: each
frame `QG_Tick` with the real time since the last (at most 0.1 s), the 320x240 8-bit screen
(`vid.buffer`) drawn through `qg_palette`, and keys posted through the engine's own `Key_Event`
(Quake's key codes, polled through GLFW as the PureDOOM host does). The base directory is `/q`, with
the shareware `pak0.pak` under `id1/`.

The timedemo (`-timedemo`) passes `+timedemo demo1` and ticks 1/64 s, as the native entry does, as
many ticks a frame as fit in 12 ms. The host prints the frames the demo took (the engine's own count,
from the first frame of the timedemo to `cls.timedemo` falling, the first frame not counted) over
the seconds spent in the ticks, and once the platform layer has hashed 100 frames without the
console, the FNV-1a 32 digest of the `frame[i]=v` lines the native entry prints for them. The page
folds the same lines of the reference, which `quake/expected_frames.das` writes out of the Rust
repository's case `quakegeneric-demo1-std` (`--rust`), and compares. The engine draws random numbers
through `crt`'s `rand`, so the frames match only with glibc's sequence (`dasCRuntime/ARCHITECTURE.md`
section 8).

The data: the deploy workflow downloads Quake 1.06's shareware zip from id Software's release (the
mirror lookibed/c2das's `get_pak.sh` uses), checks its sha1 and sha256, extracts `pak0.pak` with lhasa,
checks it the same way and adds it to the Pages artifact only; the page checks its sha256 again and
offers a picker for the user's own copy. The port's sound layer is null, so the page is silent. The
lint of the host compiles the engine under lint's stricter policies, which the generated code does
not meet, so the build fails only on a finding in the host's own file.

