options gen2

module ports_render public

require math
require strings
require daslib/strings_boost
require daslib/md_boost

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

//! One workload under one lane: the median of the samples and their spread, or the error that
//! kept the cell from standing.
struct LaneCell {
    workload : string
    lane : string
    time : double
    spread : double
    samples : array<double>
    error : string
}

struct Machine {
    arch : string
    cpu : string
    clang : string
    daslang : string
}

//! Every number one publish measured; the cells are flat, one per workload and lane.
struct Capture {
    program : string
    timestamp : string
    samples : int
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

let LANE_TITLES <- {"native" => "clang -O3", "interp" => "interpreter", "jit" => "JIT", "exe" => "exe", "aot" => "AOT"}
//! the das lanes, each with a ratio to native and a column of the projects table
let DAS_LANES <- ["interp", "jit", "exe", "aot"]
//! the lane-to-lane ratios of the ratio table, slower lane first
let LANE_PAIRS <- [("interp", "jit"), ("interp", "exe"), ("interp", "aot"), ("jit", "aot")]
//! the line above which the top-level README is the charter's; the publisher owns the rest
let README_MARKER = "<!-- generated below: c2das-re's scripts/publish_ports.sh renders everything under this line from each program's latest capture -->"
//! the perf section and the projects table while the perf method audit is open
let PERF_NOT_YET = "not yet: the perf method audit (ledger item C, p-perf-method) comes first; the tables are rendered from captures by this publisher once it lands"
let MISSING = "n/a"
let NOT_YET = "not yet"

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

//! `lane`'s time over `base`'s, 0 when either cell does not stand.
def ratio_of(c : Capture; workload, lane, base : string) : double {
    let t = time_of(c, workload, lane)
    let b = time_of(c, workload, base)
    return t > 0.0lf && b > 0.0lf ? t / b : 0.0lf
}

def private time_text(c : Capture; workload, lane : string) : string {
    let cell = find_cell(c, workload, lane)
    if (cell == null) {
        return MISSING
    }
    if (!empty(cell.error)) {
        return NOT_YET
    }
    return "{cell.time:.3f} s ±{int(round(cell.spread * 100.0lf))}%"
}

def private ratio_text(r : double) : string => r > 0.0lf ? "{r:.2f}" : MISSING

def private table_of(headers : array<string>; rows : array<array<string>>) : string {
    let aligns <- [for (idx in range(length(headers))); idx < 2 ? ColAlign.left : ColAlign.right]
    return render_md_table(headers, aligns, rows) + "\n"
}

//! The times table: one row per workload, one column per lane of the capture.
def render_times(c : Capture) : string {
    var headers <- ["Workload", "Arguments"]
    headers |> push_from([for (lane in c.lanes); lane_title(lane.name)])
    var rows : array<array<string>>
    rows |> reserve(length(c.workloads))
    for (w in c.workloads) {
        var inscope row <- [w.name, "`{w.args}`"]
        row |> push_from([for (lane in c.lanes); time_text(c, w.name, lane.name)])
        rows |> emplace(row)
    }
    return table_of(headers, rows)
}

//! The ratio table: each das lane over native, then the lane-to-lane pairs.
def render_ratios(c : Capture) : string {
    var headers <- ["Workload", "Arguments"]
    headers |> push_from([for (lane in DAS_LANES); "{lane_title(lane)} / native"], [for (pair in LANE_PAIRS); "{lane_title(pair._0)} / {lane_title(pair._1)}"])
    var rows : array<array<string>>
    rows |> reserve(length(c.workloads))
    for (w in c.workloads) {
        var inscope row <- [w.name, "`{w.args}`"]
        row |> push_from([for (lane in DAS_LANES); ratio_text(ratio_of(c, w.name, lane, "native"))], [for (pair in LANE_PAIRS); ratio_text(ratio_of(c, w.name, pair._0, pair._1))])
        rows |> emplace(row)
    }
    return table_of(headers, rows)
}

//! One line per lane that does not work yet, then one per failed cell of a lane that does.
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
    }
    return <- lines
}

//! The perf section of a program's README: the machine, the method, both tables, the lanes'
//! commands and what does not work yet.
def render_perf(c : Capture) : string {
    return build_string() $(var w) {
        w |> write("Captured {c.timestamp} on {c.machine.arch}, {c.machine.cpu}; {c.machine.clang}; daslang {c.machine.daslang}. ")
        w |> write("A cell is the median wall time of {c.samples} runs of the whole program, each its own process, ")
        w |> write("± half the range of the samples as a share of the median. The `startup` row runs no work: under a das lane it is ")
        w |> write("the module's compile and load, which every other row of that lane includes, so a workload's own time is ")
        w |> write("its cell less the startup cell. A das lane's cell stands only when every run prints what the native ")
        w |> write("build prints and exits as it does (the test-suite row compares the exit code alone: it prints its random ")
        w |> write("seeds and timings).\n\n")
        w |> write("Times:\n\n{render_times(c)}\n")
        w |> write("Ratios, a lane's time over another's (each das lane over native, then interpreter over JIT, ")
        w |> write("interpreter over exe, interpreter over AOT and JIT over AOT):\n\n{render_ratios(c)}\n")
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

//! The geometric mean over the capture's workloads, the startup row aside, of `lane`'s ratio to
//! native; `count` the workloads it covers, 0 with a result of 0 when none has the lane.
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
    var count = 0
    let g = geomean_ratio(c, lane, count)
    return count == 0 ? NOT_YET : count < total ? "{g:.2f} ({count} of {total})" : "{g:.2f}"
}

//! The projects table: one row per program, the geometric mean of each lane's ratio to native.
def render_projects(captures : array<Capture>) : string {
    var headers <- ["Program", "Captured", "Workloads"]
    headers |> push_from([for (lane in DAS_LANES); lane_title(lane)])
    var rows : array<array<string>>
    rows |> reserve(length(captures))
    for (c in captures) {
        let total = length([for (w in c.workloads); w; where !w.startup])
        var inscope row <- ["[{c.program}]({c.program}/README.md)", c.timestamp, "{total}"]
        row |> push_from([for (lane in DAS_LANES); lane_mean_text(c, lane, total)])
        rows |> emplace(row)
    }
    return table_of(headers, rows)
}

//! The top-level README: the charter above the marker kept, the projects table below it, or the
//! `PERF_NOT_YET` line when the publish measures nothing (`perf` false).
def render_top_readme(old_text : string; captures : array<Capture>; perf : bool) : string {
    let at = find(old_text, README_MARKER)
    let charter = strip_right(at < 0 ? old_text : slice(old_text, 0, at))
    return build_string() $(var w) {
        w |> write("{charter}\n\n{README_MARKER}\n\n## Programs\n\n")
        if (!perf) {
            w |> write("{PERF_NOT_YET}\n")
            return
        }
        w |> write("Each cell is the geometric mean, over the program's workloads (its startup row aside), of the lane's ")
        w |> write("time over the native build's; a lane covering only some workloads names how many. A program's ")
        w |> write("README holds its tables, its machine and its raw captures.\n\n")
        w |> write(empty(captures) ? "No program has a capture yet.\n" : render_projects(captures))
    }
}

//! The license block of an upstream C header: the lines from `* Copyright (C)` to the line ending
//! `DEALINGS IN THE SOFTWARE.`, each without its leading `* `; "" when the header holds none.
def license_block(header : string) : string {
    var lines : array<string>
    var inside = false
    for (line in split(header, "\n")) {
        let body = line |> starts_with("* ") ? slice(line, 2) : line == "*" ? "" : line
        inside = inside || body |> starts_with("Copyright (C)")
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
