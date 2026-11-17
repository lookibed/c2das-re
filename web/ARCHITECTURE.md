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
- `puredoom/shell.html` - the page emscripten fills with its loader (`daspkg`'s
  `release_web_shell`): the WAD (section 4), the play and timedemo buttons, the program's output,
  the timedemo's fps and the check of its checksums against the native build's log.
- `puredoom/.das_package` - the release of the staged project: the wasm entry, the shell, one link
  flag (`-sMAXIMUM_MEMORY=2GB`).
- `site/index.html` - the site's landing page, a list of the demos.
- `site/coi-serviceworker.js` - cross-origin isolation (section 2).
- `site/pages.yml` - the deploy workflow the ports repository's `gh-pages` branch carries (section 4).
- `scripts/build_web.sh` (repository root) - the build: checks, staging, release, the site, and with
  `--pages` the `gh-pages` checkout.

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
  through GLFW each frame and posted as Doom key and button events on a change.
- Time: PureDOOM's default clock reads 0, so the host always sets one. Play mode gives the time
  since `init` from daslang's own clock (not `crt`'s `clock()`, which emscripten under `-pthread`
  can return negative) and calls `doom_update`, which runs the tics due.
- Timedemo (`-timedemo demoN`): the clock is virtual and advances one tic per
  `doom_force_update`, as the native host `doom_main.das` does, so the checksums are the native
  ones. Each frame runs updates for 12 ms, then draws once. The fps the page reports is the tics
  over the seconds spent inside those updates; drawing and the wait for the next frame are outside
  it, as the native host's timed line has no drawing.
- Checksums: Doom prints a `tic=` line per tic (game-state and frame hash); the host folds every
  such line, newline included, into an FNV-1a 32 digest and a count instead of printing it, and
  prints both when Doom exits. The page folds the `tic=` lines of the native build's log
  (`puredoom-readable/ref/freedoom2_demo1.log`, shipped as `demo1_ref.log`) the same way and
  compares.
- Exit: Doom's exit callback (the end of a timedemo, the quit menu) longjmps out of the update
  through `c_runtime/setjmp`; the next `update` returns false.

## 4. The WAD

No WAD is in any repository or branch. The page loads `puredoom/freedoom2.wad` from its own
origin; the deploy workflow (`site/pages.yml`, run by the `gh-pages` branch with Pages' source set
to GitHub Actions) downloads Freedoom 0.13.0 from its official release, checks the zip's and the
WAD's sha256 (the sums `fetch_wad.sh` of the ports repository checks) and adds the WAD to the Pages
artifact only. The page checks the sha256 again in the browser and names the release. A page
cannot fetch the release itself: the release host sends no CORS headers. A file picker takes the
user's own `freedoom2.wad` or release zip, held to the same sha256. Only Freedoom (BSD) is
served, never a commercial id Software WAD.
