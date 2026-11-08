options gen2

module ports_render public

require math
require strings
require daslib/strings_boost
require daslib/md_boost
require ../perf/boxes.das

//! The text of the ports repository: a program's perf tables rendered from its capture, the
//! projects table of the top-level README from every program's latest capture, the license block
//! of an upstream header, and the `VERSIONS.md` pin of a program. It measures nothing and reads
//! no file, so the tests feed it fixed captures.

//! One lane of a capture: the command it runs (its flags), and its error when the lane as a whole
//! does not work yet, which every workload's cell then shares.
struct Lane {
    name : string
    command : string
    error : string
}

//! One workload: its name, the program arguments as a reader types them, and whether it is the
//! startup row, which times the program's load and no work.
struct Workload {
    name : string
    args : string
    startup : bool
}

//! One workload under one lane: the median of the samples (whole runs) and their spread, the
//! in-process work seconds each sample reported (`work_samples`, empty for the startup row and in
//! a capture made before the wrapper) with their median and spread, or the error that kept the
//! cell from standing; a failed cell keeps the samples it took, the failing one last.
struct LaneCell {
    workload : string
    lane : string
    time : double
    spread : double
    samples : array<double>
    work_samples : array<double>
    work_time : double
    work_time_spread : double
    error : string
}

//! The machine of a capture: `uname -m`, the CPU model, the box (`perf/boxes.das`), the clang
//! version line with the path of the clang the native lane ran (the lane's command names that
//! path), and daslang's version line.
struct Machine {
    arch : string
    cpu : string
    box : string
    clang : string
    clang_path : string
    daslang : string
}

//! Every number one publish measured, with the c2das-re commit of the conversion it timed, the
//! command that reproduces it (its `--samples`, `--timeout` and `--lanes`), and the end of the
//! run as its timestamp; the cells are flat, one per workload and lane.
struct Capture {
    program : string
    commit : string
    command : string
    timestamp : string
    samples : int
    timeout : int
    machine : Machine
    lanes : array<Lane>
    workloads : array<Workload>
    cells : array<LaneCell>
}

//! The upstream release a program converts: its version and each tarball with its sha256.
struct Release {
    version : string
    tarballs : array<tuple<url : string; sha256 : string>>
}

let LANE_TITLES <- {"native" => "clang -O3", "interp" => "interpreter", "jit" => "JIT", "exe" => "exe", "jit-goto" => "JIT, goto dispatch", "aot" => "AOT", "interp-source-cut" => "interpreter, source-cut layout", "jit-source-cut" => "JIT, source-cut layout", "interp-single" => "interpreter, single module", "jit-single" => "JIT, single module"}
//! the das lanes, each a column of every table, with a ratio to native and a column of the
//! projects table; `not measured` where a capture left one out
let DAS_LANES <- ["interp", "jit", "exe", "jit-goto"]
//! the lane-to-lane ratios of the ratio table, slower lane first
let LANE_PAIRS <- [("interp", "jit"), ("interp", "exe"), ("interp", "jit-goto"), ("jit", "jit-goto")]
//! the lanes over the source-cut layout's modules and the single layout's module, where the others run the
//! source layout's: a column of the ratio table and of the projects table only where a capture
//! measured them
let LAYOUT_LANES <- ["interp-source-cut", "jit-source-cut", "interp-single", "jit-single"]
//! the AOT lane, asked for only by name: a column only where a capture measured it and its build
//! stood, so a lane that does not build is a not-yet line, never a column of `not yet`
let AOT_LANE = "aot"
//! the pairs of the lanes a table shows only when a capture has them: the AOT lane under the
//! interpreter and the JIT, each layout lane over its source-layout twin; a ratio-table column
//! where both lanes are shown
let OPTIONAL_PAIRS <- [("interp", "aot"), ("jit", "aot"), ("interp-source-cut", "interp"), ("jit-source-cut", "jit"), ("interp-single", "interp"), ("jit-single", "jit")]
//! the line above which the top-level README is the charter's; the publisher owns the rest
let README_MARKER = "<!-- generated below: c2das-re's scripts/publish_ports.sh renders everything under this line from each program's latest capture -->"
//! the perf section of a program without a capture, and the projects table when no program has one
let PERF_NOT_YET = "not yet: the publisher measures only under `--perf`, off by default because a capture takes hours and runs only on an idle machine"
let MISSING = "n/a"
let NOT_YET = "not yet"
//! a das lane the capture's `--lanes` left out
let NOT_MEASURED = "not measured"
//! a work time not above 0: the cell's median at or below the startup cell's
let WITHIN_START = "within the start"
//! why a lane whose startup cell does not stand has no work times by subtraction
let NO_STARTUP = "no startup cell"
//! the marker of a work time, a ratio or a mean that subtracts the startup cell from a cell with
//! no in-process seconds, so it never looks like one timed inside the process
let BY_SUBTRACTION = "(by subtraction)"

def lane_title(lane : string) : string => LANE_TITLES?[lane] ?? lane

//! The cell of `workload` under `lane`, null when the capture has none.
def find_cell(c : Capture; workload, lane : string) : LaneCell const? {
    for (cell in c.cells) {
        if (cell.workload == workload && cell.lane == lane) {
            return unsafe(addr(cell))
        }
    }
    return null
}

//! The median seconds of a cell that stands, 0 for a missing or failed one.
def time_of(c : Capture; workload, lane : string) : double {
    let cell = find_cell(c, workload, lane)
    return cell != null && empty(cell.error) ? cell.time : 0.0lf
}

//! The name of the capture's startup row, "" when it has none.
def startup_of(c : Capture) : string {
    for (w in c.workloads) {
        if (w.startup) {
            return w.name
        }
    }
    return ""
}

// the cell of `workload` under `lane` when it stands, null for a missing or failed one
def private standing(c : Capture; workload, lane : string) : LaneCell const? {
    let cell = find_cell(c, workload, lane)
    return cell != null && empty(cell.error) ? cell : null
}

//! Whether the cell of `workload` under `lane` carries in-process work seconds.
def timed_inside(c : Capture; workload, lane : string) : bool {
    let cell = find_cell(c, workload, lane)
    return cell != null && !empty(cell.work_samples)
}

//! Whether the work time of `workload` under `lane` is by subtraction: its cell stands without
//! in-process work seconds.
def by_subtraction(c : Capture; workload, lane : string) : bool => standing(c, workload, lane) != null && !timed_inside(c, workload, lane)

//! The work seconds of `workload` under `lane`: the median of its cell's in-process seconds, else
//! its cell's median less the median of the same lane's startup cell; 0 when a cell it needs does
//! not stand.
def work_of(c : Capture; workload, lane : string) : double {
    let cell = standing(c, workload, lane)
    if (cell == null) {
        return 0.0lf
    }
    if (!empty(cell.work_samples)) {
        return cell.work_time
    }
    let start = standing(c, startup_of(c), lane)
    return start != null ? cell.time - start.time : 0.0lf
}

//! The spread of the work time of `workload` under `lane`: its in-process seconds' own, else the
//! half ranges (spread times median) of its cell and of the lane's startup cell over the work
//! time; 0 when it has no work time above 0.
def work_spread(c : Capture; workload, lane : string) : double {
    let cell = standing(c, workload, lane)
    let work = work_of(c, workload, lane)
    if (work <= 0.0lf) {
        return 0.0lf
    }
    if (!empty(cell.work_samples)) {
        return cell.work_time_spread
    }
    let start = standing(c, startup_of(c), lane)
    return (cell.spread * cell.time + start.spread * start.time) / work
}

//! Whether the work time of `workload` under `lane` is suspect: its spread above `SUSPECT_SPREAD`,
//! or, for a cell without in-process seconds, the lane's startup cell suspect, whose noise every
//! work time by subtraction inherits.
def work_suspect(c : Capture; workload, lane : string) : bool => is_suspect(work_spread(c, workload, lane)) || (!timed_inside(c, workload, lane) && cell_suspect(c, startup_of(c), lane))

//! `lane`'s work time over `base`'s, 0 when either is not above 0 or is suspect.
def ratio_of(c : Capture; workload, lane, base : string) : double {
    let t = work_of(c, workload, lane)
    let b = work_of(c, workload, base)
    let suspect = work_suspect(c, workload, lane) || work_suspect(c, workload, base)
    return t > 0.0lf && b > 0.0lf && !suspect ? t / b : 0.0lf
}

// seconds with their spread, or `suspect` with the spread alone, to a tenth of a percent, when it
// is above `SUSPECT_SPREAD`
def private seconds_text(time, spread : double) : string => is_suspect(spread) ? suspect_text(spread) : "{time:.3f} s ±{int(round(spread * 100.0lf))}%"

def private time_text(c : Capture; workload, lane : string) : string {
    if (!has_lane(c, lane)) {
        return NOT_MEASURED
    }
    let cell = find_cell(c, workload, lane)
    if (cell == null) {
        return MISSING
    }
    if (!empty(cell.error)) {
        return NOT_YET
    }
    return seconds_text(cell.time, cell.spread)
}

// the work time of a cell: `not measured` when the capture left its lane out, n/a without the
// cell, `not yet` when it does not stand; its in-process seconds when it has them, else, marked,
// its median less the lane's startup cell (`not yet` when that does not stand), its spread the two
// cells' half ranges (spread times median) over it
def private work_text(c : Capture; workload, lane : string) : string {
    if (!has_lane(c, lane)) {
        return NOT_MEASURED
    }
    let cell = find_cell(c, workload, lane)
    if (cell == null) {
        return MISSING
    }
    if (!empty(cell.error)) {
        return NOT_YET
    }
    if (!empty(cell.work_samples)) {
        return seconds_text(cell.work_time, cell.work_time_spread)
    }
    let start = standing(c, startup_of(c), lane)
    if (start == null) {
        return NOT_YET
    }
    let work = cell.time - start.time
    if (work <= 0.0lf) {
        return "{WITHIN_START} {BY_SUBTRACTION}"
    }
    // a work time over a suspect startup cell is suspect whatever its own spread
    let text = cell_suspect(c, startup_of(c), lane) ? "{SUSPECT} (startup)" : seconds_text(work, work_spread(c, workload, lane))
    return "{text} {BY_SUBTRACTION}"
}

def private ratio_text(r : double) : string => r > 0.0lf ? "{r:.2f}" : MISSING

//! Whether the capture measured `lane`.
def has_lane(c : Capture; lane : string) : bool {
    for (l in c.lanes) {
        if (l.name == lane) {
            return true
        }
    }
    return false
}

// whether the capture measured `lane` and its build stood
def private lane_stood(c : Capture; lane : string) : bool {
    for (l in c.lanes) {
        if (l.name == lane) {
            return empty(l.error)
        }
    }
    return false
}

// `lane` over `base` for `workload`, `not measured` when the capture left either lane out,
// `suspect` when either work time is, marked when either is by subtraction
def private pair_text(c : Capture; workload, lane, base : string) : string {
    if (!has_lane(c, lane) || !has_lane(c, base)) {
        return NOT_MEASURED
    }
    let text = work_suspect(c, workload, lane) || work_suspect(c, workload, base) ? SUSPECT : ratio_text(ratio_of(c, workload, lane, base))
    return text != MISSING && (by_subtraction(c, workload, lane) || by_subtraction(c, workload, base)) ? "{text} {BY_SUBTRACTION}" : text
}

// whether the cell of `workload` under `lane` stands with a spread above `SUSPECT_SPREAD`
def private cell_suspect(c : Capture; workload, lane : string) : bool {
    let cell = standing(c, workload, lane)
    return cell != null && is_suspect(cell.spread)
}

//! A markdown table whose first `text_columns` columns are text, aligned left, the rest numbers.
def table_of(headers : array<string>; rows : array<array<string>>; text_columns : int) : string {
    let aligns <- [for (idx in range(length(headers))); idx < text_columns ? ColAlign.left : ColAlign.right]
    return render_md_table(headers, aligns, rows) + "\n"
}

//! The times table: the raw medians, the start included, one row per workload (the startup row
//! too), one column per lane of `table_lanes`.
def render_times(c : Capture) : string {
    let lanes <- table_lanes(c)
    var headers <- ["Workload", "Arguments"]
    headers |> push_from([for (lane in lanes); lane_title(lane)])
    var rows : array<array<string>>
    rows |> reserve(length(c.workloads))
    for (w in c.workloads) {
        var inscope row <- [w.name, "`{w.args}`"]
        row |> push_from([for (lane in lanes); time_text(c, w.name, lane)])
        rows |> emplace(row)
    }
    return table_of(headers, rows, 2)
}

//! The startup table: one row per lane of `table_lanes`, its startup cell and that over native's.
def render_startup(c : Capture) : string {
    let start = startup_of(c)
    let native = time_of(c, start, "native")
    let lanes <- table_lanes(c)
    var rows : array<array<string>>
    rows |> reserve(length(lanes))
    for (lane in lanes) {
        let t = time_of(c, start, lane)
        let ratio = !has_lane(c, lane) ? NOT_MEASURED : cell_suspect(c, start, lane) || cell_suspect(c, start, "native") ? SUSPECT : ratio_text(native > 0.0lf ? t / native : 0.0lf)
        rows |> emplace([lane_title(lane), time_text(c, start, lane), ratio])
    }
    return table_of(["Lane", "Startup", "Over native"], rows, 1)
}

//! The work table: one row per workload but the startup row, one column per lane of
//! `table_lanes`, each cell its work time.
def render_work(c : Capture) : string {
    let lanes <- table_lanes(c)
    var headers <- ["Workload", "Arguments"]
    headers |> push_from([for (lane in lanes); lane_title(lane)])
    var rows : array<array<string>>
    rows |> reserve(length(c.workloads))
    for (w in c.workloads) {
        if (w.startup) {
            continue
        }
        var inscope row <- [w.name, "`{w.args}`"]
        row |> push_from([for (lane in lanes); work_text(c, w.name, lane)])
        rows |> emplace(row)
    }
    return table_of(headers, rows, 2)
}

// the das lanes a table shows for `captures`: every one of `DAS_LANES`, the AOT lane when one of
// them measured it and its build stood, then each layout lane one of them measured
def private shown_lanes(captures : array<Capture>) : array<string> {
    var lanes <- clone_to_move(DAS_LANES)
    if (has_value([for (c in captures); lane_stood(c, AOT_LANE)], true)) {
        lanes |> push(AOT_LANE)
    }
    for (lane in LAYOUT_LANES) {
        if (has_value([for (c in captures); has_lane(c, lane)], true)) {
            lanes |> push(lane)
        }
    }
    return <- lanes
}

//! The lanes of a capture's startup, work and times tables: native, then `shown_lanes`.
def table_lanes(c : Capture) : array<string> {
    var one : array<Capture>
    one |> push_clone(c)
    var lanes <- ["native"]
    lanes |> push_from(shown_lanes(one))
    return <- lanes
}

// the lane-to-lane pairs of the ratio table over the das lanes `lanes` it shows: `LANE_PAIRS`,
// then each of `OPTIONAL_PAIRS` whose two lanes are shown
def private ratio_pairs(lanes : array<string>) : array<tuple<string; string>> {
    var pairs <- clone_to_move(LANE_PAIRS)
    for (pair in OPTIONAL_PAIRS) {
        if (has_value(lanes, pair._0) && has_value(lanes, pair._1)) {
            pairs |> push(pair)
        }
    }
    return <- pairs
}

//! The ratio table of the work times, the startup row aside: each das lane over native, then the
//! lane-to-lane pairs; an AOT lane that stood or a layout lane the capture measured adds its column
//! and its pairs.
def render_ratios(c : Capture) : string {
    var one : array<Capture>
    one |> push_clone(c)
    let lanes <- shown_lanes(one)
    let pairs <- ratio_pairs(lanes)
    var headers <- ["Workload", "Arguments"]
    headers |> push_from([for (lane in lanes); "{lane_title(lane)} / native"], [for (pair in pairs); "{lane_title(pair._0)} / {lane_title(pair._1)}"])
    var rows : array<array<string>>
    rows |> reserve(length(c.workloads))
    for (w in c.workloads) {
        if (w.startup) {
            continue
        }
        var inscope row <- [w.name, "`{w.args}`"]
        row |> push_from([for (lane in lanes); pair_text(c, w.name, lane, "native")], [for (pair in pairs); pair_text(c, w.name, pair._0, pair._1)])
        rows |> emplace(row)
    }
    return table_of(headers, rows, 2)
}

//! The box label of machine `m`, a capture written before captures recorded a box showing its CPU's.
def machine_label(m : Machine) : string => box_label(capture_box(m.box, m.cpu), m.cpu)

//! The command that reproduces capture `c`, with `--box` when the capture recorded a box, so a
//! rerun records the same label.
def reproduce_command(c : Capture) : string => empty(c.machine.box) ? c.command : "{c.command} --box {c.machine.box}"

//! One line per lane that does not work yet, then one per failed cell of a lane that does, then
//! one for such a lane whose startup cell does not stand while a cell of it stands without
//! in-process seconds, so that cell has no work time.
def render_not_yet(c : Capture) : array<string> {
    var lines : array<string>
    for (lane in c.lanes) {
        if (!empty(lane.error)) {
            lines |> push("- {lane_title(lane.name)}, every workload: not yet: {lane.error}")
            continue
        }
        for (cell in c.cells) {
            if (cell.lane == lane.name && !empty(cell.error)) {
                lines |> push("- {cell.workload}, {lane_title(lane.name)}: not yet: {cell.error}")
            }
        }
        if (standing(c, startup_of(c), lane.name) == null && has_value([for (w in c.workloads); !w.startup && by_subtraction(c, w.name, lane.name)], true)) {
            lines |> push("- {lane_title(lane.name)}, every work time: not yet: {NO_STARTUP}")
        }
    }
    return <- lines
}

//! The perf section of a program's README: the machine, the method, the startup, work, ratio and
//! times tables, the lanes' commands and what does not work yet.
def render_perf(c : Capture) : string {
    return build_string() $(var w) {
        w |> write("Captured {c.timestamp} on {c.machine.arch}, {machine_label(c.machine)}; {c.machine.clang} at `{c.machine.clang_path}`, ")
        w |> write("the native lane's compiler; daslang {c.machine.daslang}; c2das-re `{c.commit}`. Reproduced by `{reproduce_command(c)}`. ")
        w |> write("A sample is one run of the whole program, its own process spawned by the publisher (the spawn included); ")
        w |> write("a cell is the median of {c.samples} samples, ± half their range as a share of the median; a run past ")
        w |> write("{c.timeout} s fails its cell. A das lane's cell stands only when every run prints what the native ")
        w |> write("build prints and exits as it does (the test-suite row compares the exit code and requires the line the ")
        w |> write("suite prints after its last test passes, not the output: it prints its random seeds and timings). ")
        w |> write("A lane the run left out is `{NOT_MEASURED}`. The {lane_title("jit-goto")} lane runs the JIT over the source layout ")
        w |> write("converted with c2das-re's `--switch-dispatch goto`, a dense switch (the interpreter's dispatch among them) as a jump ")
        w |> write("table; the modules published here are the default conversion, and the lane's command below names the one that ")
        w |> write("regenerates its tree. The AOT lane is measured only when asked for and has a column only where its build stood.\n\n")
        w |> write("Every speed number is the work alone, timed inside the process: a workload runs under `bench/timed.lua`, ")
        w |> write("which reads `os.clock()` (C `clock()`, the process's CPU time, under every lane) before and after the ")
        w |> write("script and reports the seconds between, and its work time is the median of those, ± half their range as a ")
        w |> write("share of it. The work seconds are process CPU time (`clock()`, user plus system), not dasProfile's steady wall clock, ")
        w |> write("since stock Lua has no in-process wall clock finer than `os.time()`'s whole seconds. A cell without them (a capture made before the wrapper) is `{BY_SUBTRACTION}`, its work time ")
        w |> write("the cell less the same lane's `startup` cell, the run that loads the program and does no work, ± the two ")
        w |> write("cells' half ranges as a share of the work time, and the mark follows it into every ratio and mean; one not ")
        w |> write("above 0 is `{WITHIN_START}`, and a lane whose startup cell does not stand has none. ")
        w |> write("The startup cells stand alone in the startup table, their ratio to native's with them, in no other ratio or mean; ")
        w |> write("the times table holds the raw medians, the start included. ")
        w |> write("A cell or a work time whose spread is above {int(SUSPECT_SPREAD * 100.0lf)}% is `{SUSPECT}`: its spread alone, no ratio, ")
        w |> write("and out of the projects table's means; a suspect startup cell makes every work time of its lane by subtraction `{SUSPECT} (startup)`.\n\n")
        w |> write("Startup:\n\n{render_startup(c)}\n")
        w |> write("Work:\n\n{render_work(c)}\n")
        // the pairs named as the table renders them, `;` apart since a lane title holds a comma
        var one : array<Capture>
        one |> push_clone(c)
        let pairs <- ratio_pairs(shown_lanes(one))
        let named = join([for (pair in pairs); "{lane_title(pair._0)} over {lane_title(pair._1)}"], "; ")
        w |> write("Ratios, a lane's work time over another's (each das lane over native, then {named}):\n\n{render_ratios(c)}\n")
        w |> write("Times, the raw medians of whole runs, the start included:\n\n{render_times(c)}\n")
        w |> write("Lanes:\n\n")
        for (lane in c.lanes) {
            w |> write("- {lane_title(lane.name)}: `{lane.command}`\n")
        }
        let not_yet <- render_not_yet(c)
        if (!empty(not_yet)) {
            w |> write("\nNot yet:\n\n" + join(not_yet, "\n") + "\n")
        }
    }
}

//! The geometric mean over the capture's workloads, the startup row aside, of `lane`'s work time
//! over native's; `count` the workloads it covers, 0 with a result of 0 when none has the lane.
def geomean_ratio(c : Capture; lane : string; var count : int&) : double {
    var log_sum = 0.0lf
    count = 0
    for (w in c.workloads) {
        let r = w.startup ? 0.0lf : ratio_of(c, w.name, lane, "native")
        if (r > 0.0lf) {
            log_sum += log(r)
            count++
        }
    }
    return count == 0 ? 0.0lf : exp(log_sum / double(count))
}

def private lane_mean_text(c : Capture; lane : string; total : int) : string {
    if (!has_lane(c, lane)) {
        return NOT_MEASURED
    }
    var count = 0
    let g = geomean_ratio(c, lane, count)
    if (count == 0) {
        return NOT_YET
    }
    let text = count < total ? "{g:.2f} ({count} of {total})" : "{g:.2f}"
    // a mean over a ratio by subtraction carries its mark
    let subtracted = has_value([for (w in c.workloads); !w.startup && ratio_of(c, w.name, lane, "native") > 0.0lf && (by_subtraction(c, w.name, lane) || by_subtraction(c, w.name, "native"))], true)
    return subtracted ? "{text} {BY_SUBTRACTION}" : text
}

//! The projects table: one row per program, the geometric mean of each lane's work-time ratio to
//! native; a layout lane a capture measured adds its column.
def render_projects(captures : array<Capture>) : string {
    let lanes <- shown_lanes(captures)
    var headers <- ["Program", "Captured", "Machine", "Workloads"]
    headers |> push_from([for (lane in lanes); lane_title(lane)])
    var rows : array<array<string>>
    rows |> reserve(length(captures))
    for (c in captures) {
        let total = length([for (w in c.workloads); w; where !w.startup])
        var inscope row <- ["[{c.program}]({c.program}/README.md)", c.timestamp, "{c.machine.arch}, {machine_label(c.machine)}", "{total}"]
        row |> push_from([for (lane in lanes); lane_mean_text(c, lane, total)])
        rows |> emplace(row)
    }
    return table_of(headers, rows, 3)
}

//! The top-level README: the charter above the marker kept, the projects table of `captures`
//! below it, or the `PERF_NOT_YET` line when no program has a capture, then the line naming the
//! `raw` captures copied beside it when there are any.
def render_top_readme(old_text : string; captures : array<Capture>; raw : array<string>) : string {
    let at = find(old_text, README_MARKER)
    let charter = strip_right(at < 0 ? old_text : slice(old_text, 0, at))
    return build_string() $(var w) {
        w |> write("{charter}\n\n{README_MARKER}\n\n## Programs\n\n")
        if (empty(captures)) {
            w |> write("{PERF_NOT_YET}\n")
        } else {
            w |> write("Each cell is the geometric mean, over the program's workloads (its startup row aside), of the lane's ")
            w |> write("work time over the native build's, a work time being the seconds the workload's run measured inside its ")
            w |> write("process; a mean `{BY_SUBTRACTION}` takes a capture made before that clock, its work times the workload's ")
            w |> write("median less the same lane's startup median. A lane covering only some workloads names how many. A program's README holds its tables, ")
            w |> write("its startup times, its machine and its raw captures.\n\n")
            w |> write(render_projects(captures))
        }
        if (!empty(raw)) {
            w |> write("\nRaw captures beside this README, each copied whole from c2das-re when its tree holds it: " + join([for (rel in raw); "`{rel}`"], ", ") + ".\n")
        }
    }
}

//! The license block of an upstream C header: the lines from the last `* Copyright (C)` line
//! before the line ending `DEALINGS IN THE SOFTWARE.` inside the same comment (no `*/` between)
//! to that line, each without its leading `* `; "" when the header holds none.
def license_block(header : string) : string {
    var lines : array<string>
    var inside = false
    for (line in split(header, "\n")) {
        let body = line |> starts_with("* ") ? slice(line, 2) : line == "*" ? "" : line
        if (body |> starts_with("Copyright (C)")) {
            lines |> clear()
            inside = true
        } elif (inside && line |> contains("*/")) {
            lines |> clear()
            inside = false
        }
        if (inside) {
            lines |> push(body)
            if (body |> ends_with("DEALINGS IN THE SOFTWARE.")) {
                return join(lines, "\n") + "\n"
            }
        }
    }
    return ""
}

//! The `<program>:` line of `VERSIONS.md` read: the version after the colon and every tarball
//! named as `<url> (sha256 <hash>)`; false when the file has no such line.
def release_of(versions, program : string; var release : Release) : bool {
    let head = "{program}: "
    for (line in split(versions, "\n")) {
        if (!(line |> starts_with(head))) {
            continue
        }
        let rest = slice(line, length(head))
        let space = find(rest, " ")
        release.version = space < 0 ? rest : slice(rest, 0, space)
        // each tarball is `https://<rest of url> (sha256 <hash>)`
        let tag = " (sha256 "
        for (part in split(rest, "https://")) {
            let tag_at = find(part, tag)
            if (tag_at > 0 && part != rest) {
                let hash_at = tag_at + length(tag)
                release.tarballs |> push((url = "https://" + slice(part, 0, tag_at), sha256 = slice(part, hash_at, hash_at + 64)))
            }
        }
        return true
    }
    return false
}

//! The line a table measured at another commit than the published conversion's carries: the
//! commit it was measured at, and when the converter changed between that commit and the
//! published one, that the output changed since, so the numbers are not read as this output's.
def measured_at_line(sha, date : string; changed : bool) : string {
    let at = "Measured at c2das-re `{slice(sha, 0, 12)}`" + (empty(date) ? "" : " ({date})")
    return changed ? "{at}, output changed since: the converter changed between that commit and the one this directory was converted at; no new timing yet.\n\n" : "{at}.\n\n"
}

//! The line a compare project's table carries: the date its entry was measured, the commit that
//! committed the capture holding it (the entries of one capture are measured on different dates),
//! and that the output changed since when the converter changed after that date.
def measured_on_line(date, capture_sha : string; changed : bool) : string {
    let at = "Measured {date} (capture committed at c2das-re `{slice(capture_sha, 0, 12)}`)"
    return changed ? "{at}, output changed since: the converter changed after that date; no new timing yet.\n\n" : "{at}.\n\n"
}

//! The notice of an upstream file that names its license by an SPDX line alone: the file's lines
//! from the first through the first non-empty one after the `SPDX-License-Identifier` line (the
//! author); "" when the file has no such line.
def spdx_notice(text : string) : string {
    let lines <- split(text, "\n")
    var spdx = -1
    for (line, i in lines, count()) {
        if (spdx < 0 && line |> contains("SPDX-License-Identifier")) {
            spdx = i
        } elif (spdx >= 0 && !empty(strip(line))) {
            return join([for (l, j in lines, count()); l; where j <= i], "\n") + "\n"
        }
    }
    return spdx < 0 ? "" : join(lines, "\n")
}

//! The criteria line of a compare project's README: the readability criteria are not computed per
//! project yet.
let PROJECT_CRITERIA_NOT_YET = "not yet: c2das-re's `scripts/run_criteria.sh` measures its own inputs (the Lua programs and the suites) and takes no single project, so `metrics/criteria_linux.json` holds no row for this program."

//! The top-level README's programs section: a link per program directory of the clone, then each
//! failure of the publish that wrote it (`<program>: <why>`), whose directory keeps what an earlier
//! publish left.
def render_programs(programs : array<string>; failures : array<string>) : string {
    return build_string() $(var w) {
        w |> write("\n## Directories\n\n")
        for (name in programs) {
            w |> write("- [{name}]({name}/)\n")
        }
        if (!empty(failures)) {
            w |> write("\nNot republished by the last publish, each directory as an earlier publish left it:\n\n")
            for (f in failures) {
                w |> write("- {f}\n")
            }
        }
    }
}
