options gen2

module fps public

require math
require daslib/strings_boost
require ../perf/boxes.das
require ../perf/perf_lanes.das
require ../ports/ports_render.das
require ../ports/upstream_cells.das
require harness
require demo_run

//! Doom's frame rate (`ARCHITECTURE_RUN.md` section 9): a run's fps from the host's own clock, the
//! cell of a demo under one lane over its runs, the capture `run.das --fps` writes and the table
//! rendered from it. It runs and reads nothing, so the tests feed it fixed runs and captures.

//! One demo under one lane: the median fps of the runs and their spread (half the range over the
//! median), each run's fps and host seconds, the tics of the demo; or the error of the run that
//! kept the cell from standing, `desync` when that run fell out of sync, the runs before it kept.
struct FpsCell {
    workload : string
    lane : string
    fps : double
    spread : double
    tics : int
    samples : array<double>
    seconds : array<double>
    error : string
    desync : bool
}

//! A lane of a capture: `native`, or the tier the converted program runs under, with the command
//! one run of it is.
struct FpsLane {
    name : string
    command : string
}

//! Every number one `--fps` run measured: the c2das-re commit, the command that reproduces it,
//! the end of the run, the machine (`perf/boxes.das`) and the tools, the runs per cell and the
//! clock, the lanes, the demos and one cell per demo and lane.
struct FpsCapture {
    commit : string
    command : string
    timestamp : string
    platform : string
    cpu : string
    box : string
    clang : string
    daslang : string
    samples : int
    clock : string
    lanes : array<FpsLane>
    workloads : array<string>
    cells : array<FpsCell>
}

//! the clock a capture's seconds are read on
let FPS_CLOCK = "the process CPU time (`clock()`) of the host's update loop"
let FPS_TITLES <- {"native" => "native", "interp" => "interp", "jit" => "JIT", "exe" => "exe", "aot" => "AOT"}

def private fps_title(lane : string) : string => FPS_TITLES?[lane] ?? lane

//! Why `run` gives no fps, "" when it gives one: an error, a desync or a run that did not end in
//! the demo's `timed N gametics` (a desync fails the run: the fps of a wrong replay is never
//! published), no host line, or a host line of other tics than the demo's or of no time.
def run_problem(run : DemoRun) : string {
    if (!empty(run.error)) {
        return run.error
    }
    if (run.speed && !in_sync(run)) {
        return "{speed_summary(run)} (exit {run.rc})"
    }
    if (!in_sync(run)) {
        let unended = empty(run.sync.desync) ? ", then the run did not end in `timed {run.sync.compared} gametics` (exit {run.rc})" : ""
        return "{sync_summary(run.sync)}{unended}"
    }
    if (run.timing.tics < 0) {
        return "no `host: timed N gametics in S s` line"
    }
    if (run.timing.tics != run.sync.compared) {
        return "the host timed {run.timing.tics} gametics, the demo has {run.sync.compared}"
    }
    if (run.timing.seconds <= 0.0lf) {
        return "the host timed {run.timing.tics} gametics in no time"
    }
    return ""
}

//! `run` added to `cell`: its fps a sample, the median and spread recomputed; false with the cell's
//! error set (`desync` when the run fell out of sync) when the run gives no fps.
def add_run(var cell : FpsCell; run : DemoRun) : bool {
    let problem = run_problem(run)
    if (!empty(problem)) {
        cell.error = problem
        cell.desync = !empty(run.sync.desync)
        return false
    }
    cell.tics = run.timing.tics
    cell.samples |> push(double(run.timing.tics) / run.timing.seconds)
    cell.seconds |> push(run.timing.seconds)
    cell.fps = median_of(cell.samples)
    cell.spread = spread_of(cell.samples, cell.fps)
    return true
}

//! The command one run of `lane` is: the native build at `native` under `prlimit`, or `daslang`
//! over the converted entry module `entry`, `<N>` standing for the demo.
def lane_command(lane, native, entry : string) : string {
    if (lane == NATIVE_LANE) {
        return "prlimit --as={NATIVE_MEMORY} {native} -timedemo demo<N>"
    }
    if (lane == "interp" || lane == "jit") {
        let jit = lane == "jit" ? " -jit" : ""
        return "daslang -load_module c_runtime -load_module dasCRuntime{jit} {entry} -- -timedemo demo<N>"
    }
    return "run_tier {lane} {entry} -- -timedemo demo<N>"
}

//! The `run.das` command a capture records: `--fps` over `layout` and `tiers`, `samples` runs a
//! cell, and `--demo <demo>` when one demo was timed (`demo` 0 for all three).
def fps_command(layout : string; tiers : array<string>; samples, demo : int) : string {
    let one = demo != 0 ? " --demo {demo}" : ""
    return "daslang -load_module dasCRuntime -load_module c_runtime doom/run.das -- --run --fps --layout {layout} --tiers {join(tiers, ",")} --samples {samples}{one}"
}

//! The cell of `workload` under `lane`, null when the capture has none.
def find_fps_cell(c : FpsCapture; workload, lane : string) : FpsCell const? {
    for (cell in c.cells) {
        if (cell.workload == workload && cell.lane == lane) {
            return unsafe(addr(cell))
        }
    }
    return null
}

// the cell of `workload` under `lane` when it stands and is not suspect, null otherwise
def private trusted(c : FpsCapture; workload, lane : string) : FpsCell const? {
    let cell = find_fps_cell(c, workload, lane)
    return cell != null && empty(cell.error) && cell.spread <= SUSPECT_SPREAD ? cell : null
}

def private suspect_cell(c : FpsCapture; workload, lane : string) : bool {
    let cell = find_fps_cell(c, workload, lane)
    return cell != null && empty(cell.error) && cell.spread > SUSPECT_SPREAD
}

//! The native fps of `workload` over `lane`'s: how many times slower the lane plays the demo; 0
//! when either cell is missing, failed or suspect.
def slowdown(c : FpsCapture; workload, lane : string) : double {
    let native = trusted(c, workload, NATIVE_LANE)
    let cell = trusted(c, workload, lane)
    return native != null && cell != null ? native.fps / cell.fps : 0.0lf
}

// the fps of a cell with its spread, `suspect` with the spread alone above `SUSPECT_SPREAD`,
// `desync` or `failed` for a cell that does not stand, n/a without one
def private fps_text(c : FpsCapture; workload, lane : string) : string {
    let cell = find_fps_cell(c, workload, lane)
    if (cell == null) {
        return MISSING
    }
    if (!empty(cell.error)) {
        return cell.desync ? "desync" : "failed"
    }
    let percent = cell.spread * 100.0lf
    return cell.spread > SUSPECT_SPREAD ? "{SUSPECT} (±{percent:.1f}%)" : "{cell.fps:.1f} ±{int(round(percent))}%"
}

// the lane's slowdown to one decimal, `suspect` when either cell is, n/a when either does not stand
def private slowdown_text(c : FpsCapture; workload, lane : string) : string {
    if (suspect_cell(c, workload, lane) || suspect_cell(c, workload, NATIVE_LANE)) {
        return SUSPECT
    }
    let r = slowdown(c, workload, lane)
    return r > 0.0lf ? "{r:.1f}" : MISSING
}

// PureDOOM's name in `UPSTREAM_CELLS`, the ports directory's
let private DOOM_PROGRAM = "puredoom"

//! The fps table: one row per demo, the fps of each lane, then each das lane's native fps over its
//! own; the provenance line above it and one line per cell that does not stand below it.
def render_fps(c : FpsCapture) : string {
    let das_lanes <- [for (lane in c.lanes); lane.name; where lane.name != NATIVE_LANE]
    var headers <- ["Workload"]
    headers |> push_from([for (lane in c.lanes); "{fps_title(lane.name)} fps"], [for (lane in das_lanes); "{fps_title(lane)} / native"])
    var rows : array<array<string>>
    rows |> reserve(length(c.workloads))
    for (w in c.workloads) {
        var inscope row <- [w]
        row |> push_from([for (lane in c.lanes); fps_text(c, w, lane.name)], [for (lane in das_lanes); upstream_marked(slowdown_text(c, w, lane), DOOM_PROGRAM, lane)])
        rows |> emplace(row)
    }
    let machine = box_label(capture_box(c.box, c.cpu), c.cpu)
    var text = "Box {machine}, {c.platform}; c2das-re `{c.commit}`, captured {c.timestamp}; {c.clang}; daslang {c.daslang}.\n\n"
    text += "PureDOOM `-timedemo demoN` on freedoom2.wad. fps is the demo's gametics over {FPS_CLOCK} in the speed build, which leaves the patch's per-tic checksums and tic lines out: the playback alone, the module load, the JIT compile and `doom_init` outside it. Per demo and lane one run of the sync build first holds every tic to the reference log; a cell is then the median of {c.samples} speed runs, each its own process ending in the demo's `timed N gametics`, ± half the range over the median; above {int(SUSPECT_SPREAD * 100.0lf)}% it is `{SUSPECT}`, without a ratio. `X / native` is native fps over X's.\n\n"
    let failed <- [for (cell in c.cells); "\n- {cell.workload}, {fps_title(cell.lane)}: {cell.error}"; where !empty(cell.error)]
    let notes <- upstream_footnotes([DOOM_PROGRAM], das_lanes)
    return text + table_of(headers, rows, 1) + join(failed, "") + "\n" + (empty(notes) ? "" : "\n" + join(notes, "\n") + "\n")
}
