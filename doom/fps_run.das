options gen2

module fps_run public

require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../converter/tiers.das
require ../converter/sidecar.das
require ../perf/boxes.das
require ../perf/perf_cli.das
require ../perf/perf_lanes.das
require demo_run
require fps

//! The runs of `run.das --run --fps` (`ARCHITECTURE_RUN.md` section 9) over the inputs `FpsPlan`
//! names: the flag check, the demos, each cell's runs, the capture written and the README section
//! rewritten from it. `run.das` fills the plan from its flags and the machine; the tests fill it
//! with stand-ins.

//! One `--fps` run: the sync builds (the native one and the converted entry module, which print the
//! tic lines) and the speed builds (the same without the per-tic checksum), the wad, the work folder, the
//! reference folders and the converted program's module folders, the tiers after native, the demos,
//! the runs a cell, the seconds a run may take and the path the capture is written to.
struct FpsPlan {
    sync_native : string
    sync_entry : string
    native : string
    entry : string
    wad : string
    work : string
    ref_dirs : array<string>
    module_dirs : array<string>
    tiers : array<string>
    demos : array<int>
    samples : int
    timeout : int
    capture_path : string
}

//! Why `--fps` refuses its flags, "" when it does not or `fps` is off: it goes with `run`, without
//! `tics` or `trace`, `tiers` among `run_tier`'s, `samples` at least 1.
def fps_refusal(fps, run : bool; tiers : array<string>; samples, tics : int; trace : bool) : string {
    if (!fps) {
        return ""
    }
    let bad <- [for (tier in tiers); tier; where !key_exists(TIERS, tier)]
    if (!empty(bad)) {
        return "--tiers takes interp, jit, exe and aot, not `{join(bad, ",")}`"
    }
    if (samples < 1) {
        return "--samples takes at least 1, not {samples}"
    }
    if (!run) {
        return "--fps goes with --run"
    }
    if (tics != 0) {
        return "--fps times the whole demo, not --tics {tics}"
    }
    return trace ? "--fps does not go with --trace" : ""
}

//! The demos `--fps` times: `demo` alone, all three when it is 0.
def fps_demos(demo : int) : array<int> => <- demo == 0 ? [1, 2, 3] : [demo]

//! The commit a capture records: `sha`, then `-dirty` when `status` (`git status --porcelain`
//! of the tracked files) is not empty.
def commit_label(sha, status : string) : string => empty(strip(status)) ? sha : "{sha}-dirty"

//! A capture before its runs: the commit of `sha` and `status`, the command, the machine (the box
//! of `cpu`), the tools' version lines and the runs a cell.
def new_capture(sha, status, command, cpu, platform, clang, daslang : string; samples : int) : FpsCapture => FpsCapture(commit = commit_label(sha, status), command = command, cpu = cpu, box = box_of(cpu), platform = platform, clang = clang, daslang = daslang, samples = samples, spread_rule = spread_rule_of(samples), pinned_core = pinned_core(), clock = FPS_CLOCK)

// the run of `demo` under `lane`: the native build under the lane `NATIVE_LANE` (`sync_native`
// or `native`), else the converted entry (`sync_entry` or `entry`) under the tier `lane`, the speed
// build, pinned when asked (`timing_prefix`), when `speed`
def private lane_spec(plan : FpsPlan; lane : string; demo : int; speed : bool) : DemoSpec {
    let native = lane == NATIVE_LANE
    let entry = speed ? (native ? plan.native : plan.entry) : (native ? plan.sync_native : plan.sync_entry)
    return <- DemoSpec(entry = entry, tier = lane, wad = plan.wad, demo = demo, timeout = float(plan.timeout), work = plan.work, ref_dirs <- clone_to_move(plan.ref_dirs), module_dirs <- clone_to_move(plan.module_dirs), speed = speed, pin <- speed ? timing_prefix() : array<string>())
}

//! The cell of `demo` under `lane` before its samples: one run of the sync build held to every tic
//! of the reference log; a run out of sync or refused leaves the cell its error, and it takes no
//! speed run.
def fps_sync(plan : FpsPlan; lane : string; demo : int) : FpsCell {
    let spec <- lane_spec(plan, lane, demo, false)
    var cell = FpsCell(workload = "demo{demo}", lane = lane)
    let synced = run_converted(spec)
    log_run(spec, synced)
    let problem = run_problem(synced)
    if (!empty(problem)) {
        cell.error = "sync build: {problem}"
        cell.desync = !empty(synced.sync.desync)
        to_log(LOG_ERROR, "doom: {cell.workload}, {lane}: {cell.error}\n")
    } else {
        to_log(LOG_INFO, "doom: {timed_evidence(spec, synced)}\n")
    }
    return <- cell
}

//! One run of the speed build of `cell`'s demo under its lane, held to the demo's end, added to
//! `cell`; false when the run has no fps, which ends the cell with its error.
def fps_sample(plan : FpsPlan; demo : int; var cell : FpsCell) : bool {
    let spec <- lane_spec(plan, cell.lane, demo, true)
    let run = run_converted(spec)
    log_run(spec, run)
    if (!add_run(cell, run)) {
        to_log(LOG_ERROR, "doom: {cell.workload}, {cell.lane}: {cell.error}\n")
        return false
    }
    to_log(LOG_INFO, "doom: {timed_evidence(spec, run)}\n")
    return true
}

// `run_report`'s lines on `run`, logged
def private log_run(spec : DemoSpec; run : DemoRun) {
    for (line in run_report(spec, run)) {
        to_log(LOG_INFO, "doom: {line}\n")
    }
}

//! Every demo of `plan` under native and each of its tiers into `c`: per demo each lane's sync run
//! (`fps_sync`), then `plan.samples` rounds of speed runs, one of each lane still standing a round in
//! `sample_order`; stamped `timestamp` and
//! written to `plan.capture_path`, its table logged; false when a cell does not stand or the capture is
//! not written.
def time_demos(plan : FpsPlan; var c : FpsCapture; timestamp : string) : bool {
    var lanes <- [NATIVE_LANE]
    lanes |> push_from(plan.tiers)
    c.lanes <- [for (lane in lanes); FpsLane(name = lane, command = lane_command(lane, plan.native, plan.entry))]
    var ok = true
    c.workloads |> reserve(length(plan.demos))
    c.cells |> reserve(length(plan.demos) * length(lanes))
    for (demo in plan.demos) {
        c.workloads |> push("demo{demo}")
        var inscope cells <- [for (lane in lanes); fps_sync(plan, lane, demo)]
        // the speed runs interleave: each round takes one of every lane still standing
        for (round in range(plan.samples)) {
            for (i in sample_order(length(lanes), round)) {
                if (empty(cells[i].error)) {
                    fps_sample(plan, demo, cells[i])
                }
            }
        }
        for (cell in cells) {
            ok = ok && empty(cell.error)
            c.cells |> emplace(cell)
        }
    }
    c.timestamp = timestamp
    if (!fwrite(plan.capture_path, write_json(JV(c)) + "\n")) {
        to_log(LOG_ERROR, "doom: cannot write {plan.capture_path}\n")
        return false
    }
    to_log(LOG_INFO, "doom: {plan.capture_path}:\n{render_fps(c)}")
    return ok
}

//! the markers of README's fps section
let FPS_BEGIN = "<!-- doom-fps:begin -->"
let FPS_END = "<!-- doom-fps:end -->"

//! The fps section of `readme` rewritten from the capture at `capture_path`; "" when done, else why not:
//! the capture does not read, or `readme` has no markers.
def write_fps_readme(capture_path, readme : string) : string {
    var error : string
    let js = read_json_file(capture_path, error)
    if (js == null) {
        return "{capture_path}: {error}"
    }
    let c <- from_JV(js, type<FpsCapture>)
    return update_readme(readme, render_fps(c), FPS_BEGIN, FPS_END) ? "" : "{readme} has no doom-fps markers"
}
