options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require math
require daslib/json_boost
require ../ports_render.das
require ../variants.das
require ../../metrics/criteria_file.das

//! The renderer over fixed captures: the times, ratio and not-yet text, the geometric means of
//! the projects table, the top-level README's marker, the license block and the VERSIONS.md pin.

def private cell(workload, lane : string; time : double) : LaneCell => <- LaneCell(workload = workload, lane = lane, time = time, spread = 0.02lf, samples <- [time])

// a cell of a run under the wrapper: `time` the whole run, `work` the seconds it measured inside
def private timed_cell(workload, lane : string; time, work : double) : LaneCell {
    var c <- cell(workload, lane, time)
    c.work_samples <- [work]
    c.work_time = work
    c.work_time_spread = 0.02lf
    return <- c
}

// capture `c` as one made before the wrapper: no cell carries in-process seconds
def private subtracted(var c : Capture) : Capture {
    for (cl in c.cells) {
        cl.work_samples |> clear()
        cl.work_time = 0.0lf
        cl.work_time_spread = 0.0lf
    }
    return <- c
}

def private failed(workload, lane, error : string) : LaneCell => <- LaneCell(workload = workload, lane = lane, error = error)

// the cells after the first of the row of markdown table `text` whose first cell is `first`,
// stripped; empty when the table has no such row
def private row_of(text, first : string) : array<string> {
    for (line in split(text, "\n")) {
        var inscope cells <- [for (part in split(line, "|")); strip(part)]
        if (length(cells) > 2 && cells[1] == first) {
            return <- [for (idx in range(2, length(cells) - 1)); cells[idx]]
        }
    }
    return <- array<string>()
}

// two workloads and the startup row; interp everywhere, jit on one workload, aot a lane error,
// exe a failed cell and no startup cell; each work time a round number timed inside the run, and
// the same number by subtraction, the startup cell taken out (`subtracted`)
def private fixture : Capture => <- Capture(
    program = "lua", commit = "abc123", command = "scripts/publish_ports.sh --program lua --perf --samples 3", timestamp = "2026-10-22 10:00 UTC", samples = 3, timeout = 60,
    machine = Machine(arch = "x86_64", cpu = "CPU", clang = "clang version 22", clang_path = "/opt/clang/bin/clang", daslang = "0.6.4"),
    lanes <- [for (lane in ["native", "interp", "jit", "exe", "jit-goto"]); Lane(name = lane, command = "run {lane}", error = lane == "jit-goto" ? "no arguments" : "")],
    workloads <- [
        Workload(name = "startup", args = "-e \"print(1)\"", startup = true),
        Workload(name = "fib", args = "bench/fib.lua"),
        Workload(name = "nbody", args = "bench/nbody.lua")
    ],
    cells <- [
        cell("startup", "native", 0.5lf),
        cell("startup", "interp", 10.0lf),
        cell("startup", "jit", 2.0lf),
        timed_cell("fib", "native", 1.5lf, 1.0lf),
        timed_cell("fib", "interp", 210.0lf, 200.0lf),
        timed_cell("fib", "jit", 10.0lf, 8.0lf),
        failed("fib", "exe", "exited 3"),
        failed("fib", "jit-goto", "no arguments"),
        timed_cell("nbody", "native", 2.5lf, 2.0lf),
        timed_cell("nbody", "interp", 110.0lf, 100.0lf),
        failed("nbody", "jit", "prints `x`")
    ])

[test]
def test_tables(t : T?) {
    t |> run("the times table: the raw medians, the startup row too, `not yet` for a failed cell, n/a for a missing one") @(t : T?) {
        let c <- fixture()
        t |> equal(render_times(c), "| Workload | Arguments         |    clang -O3 |    interpreter |           JIT |     exe | JIT, goto dispatch |\n| :------- | :---------------- | -----------: | -------------: | ------------: | ------: | -----------------: |\n| startup  | `-e \"print(1)\"`   | 0.500 s ±2% |  10.000 s ±2% |  2.000 s ±2% |     n/a |                n/a |\n| fib      | `bench/fib.lua`   | 1.500 s ±2% | 210.000 s ±2% | 10.000 s ±2% | not yet |            not yet |\n| nbody    | `bench/nbody.lua` | 2.500 s ±2% | 110.000 s ±2% |       not yet |     n/a |                n/a |\n")
    }
    t |> run("the ratio table: each das lane over native, then the lane pairs") @(t : T?) {
        let c <- fixture()
        let text = render_ratios(c)
        t |> success(text |> starts_with("| Workload | Arguments         | interpreter / native | JIT / native | exe / native | JIT, goto dispatch / native | interpreter / JIT | interpreter / exe | interpreter / JIT, goto dispatch | JIT / JIT, goto dispatch |"), text)
        t |> success(text |> contains("| fib      | `bench/fib.lua`   |               200.00 |         8.00 |          n/a |                         n/a |             25.00 |               n/a |                              n/a |                      n/a |"), text)
        t |> success(!(text |> contains("startup")), text)
        // a capture made before the wrapper: every ratio over a work time by subtraction is marked
        let old = render_ratios(subtracted(fixture()))
        t |> equal(join(row_of(old, "fib"), ","), "`bench/fib.lua`,200.00 (by subtraction),8.00 (by subtraction),n/a,n/a,25.00 (by subtraction),n/a,n/a,n/a")
    }
    t |> run("not yet: a lane error once for every workload, a failed cell of a working lane on its own line") @(t : T?) {
        let c <- fixture()
        let lines <- render_not_yet(c)
        t |> equal(join(lines, "\n"), "- nbody, JIT: not yet: prints `x`\n- fib, exe: not yet: exited 3\n- JIT, goto dispatch, every workload: not yet: no arguments")
    }
    t |> run("the Captured line names the box: the capture's, else its CPU's; the command reproduces a recorded box") @(t : T?) {
        var boxed <- fixture()
        boxed.machine.box = "fx"
        t |> success(render_perf(boxed) |> starts_with("Captured 2026-10-22 10:00 UTC on x86_64, fx (CPU); clang version 22"), render_perf(boxed))
        t |> success(render_perf(boxed) |> contains("Reproduced by `scripts/publish_ports.sh --program lua --perf --samples 3 --box fx`. "), render_perf(boxed))
        t |> success(render_perf(fixture()) |> contains("Reproduced by `scripts/publish_ports.sh --program lua --perf --samples 3`. "), render_perf(fixture()))
        var known <- fixture()
        known.machine.cpu = "AMD Ryzen 3 1200 Quad-Core Processor"
        t |> success(render_perf(known) |> starts_with("Captured 2026-10-22 10:00 UTC on x86_64, bench (AMD Ryzen 3 1200 Quad-Core Processor); "), render_perf(known))
    }
    t |> run("the perf section names the machine, the samples and every lane's command") @(t : T?) {
        let c <- fixture()
        let text = render_perf(c)
        t |> success(text |> starts_with("Captured 2026-10-22 10:00 UTC on x86_64, CPU; clang version 22 at `/opt/clang/bin/clang`, the native lane's compiler; daslang 0.6.4; c2das-re `abc123`. Reproduced by `scripts/publish_ports.sh --program lua --perf --samples 3`. A sample is one run of the whole program"), text)
        t |> success(text |> contains("a cell is the median of 3 samples"), text)
        t |> success(text |> contains("a run past 60 s fails its cell"), text)
        t |> success(text |> contains("Every speed number is the work alone, timed inside the process: a workload runs under `bench/timed.lua`, which reads `os.clock()` (C `clock()`, the process's CPU time, under every lane) before and after the script"), text)
        t |> success(text |> contains("A cell without them (a capture made before the wrapper) is `(by subtraction)`, its work time the cell less the same lane's `startup` cell"), text)
        // the tables in order: startup, work, the work ratios, the raw times
        let order <- [for (head in ["Startup:\n\n| Lane ", "Work:\n\n| Workload ", "Ratios, a lane's work time over another's", "Times, the raw medians of whole runs, the start included:\n\n| Workload ", "Lanes:\n\n"]); find(text, head)]
        t |> success(order[0] > 0 && order[0] < order[1] && order[1] < order[2] && order[2] < order[3] && order[3] < order[4], "{order}\n{text}")
        t |> success(text |> contains("- JIT: `run jit`\n"), text)
        t |> success(text |> ends_with("Not yet:\n\n- nbody, JIT: not yet: prints `x`\n- fib, exe: not yet: exited 3\n- JIT, goto dispatch, every workload: not yet: no arguments\n"), text)
    }
    t |> run("a capture where every cell stands has no not-yet list") @(t : T?) {
        var c <- fixture()
        c.lanes |> resize(2)
        c.cells <- [cell("startup", "native", 0.001lf), cell("startup", "interp", 1.0lf), cell("fib", "native", 1.0lf), cell("fib", "interp", 2.0lf), cell("nbody", "native", 1.0lf), cell("nbody", "interp", 2.0lf)]
        let text = render_perf(c)
        t |> success(!(text |> contains("Not yet")), text)
        t |> success(text |> ends_with("- interpreter: `run interp`\n"), text)
    }
    t |> run("a lane the capture's --lanes left out is `not measured`, in the ratio table and the projects table") @(t : T?) {
        var c <- fixture()
        c.lanes |> resize(2)
        let ratios = render_ratios(c)
        t |> success(ratios |> contains("| fib      | `bench/fib.lua`   |               200.00 | not measured | not measured |      not measured |      not measured |"), ratios)
        var captures : array<Capture>
        captures |> emplace(c)
        let projects = render_projects(captures)
        t |> success(projects |> ends_with("| x86_64, CPU |         2 |      100.00 | not measured | not measured |\n"), projects)
    }
}

[test]
def test_work(t : T?) {
    t |> run("the startup table: a row per lane, its startup cell and that over native's") @(t : T?) {
        let c <- fixture()
        t |> equal(render_startup(c), "| Lane               |       Startup | Over native |\n| :----------------- | ------------: | ----------: |\n| clang -O3          |  0.500 s ±2% |        1.00 |\n| interpreter        | 10.000 s ±2% |       20.00 |\n| JIT                |  2.000 s ±2% |        4.00 |\n| exe                |           n/a |         n/a |\n| JIT, goto dispatch |           n/a |         n/a |\n")
    }
    t |> run("the work table: each cell's in-process seconds, the startup row aside, their own spread") @(t : T?) {
        let c <- fixture()
        t |> equal(render_work(c), "| Workload | Arguments         |    clang -O3 |    interpreter |          JIT |     exe | JIT, goto dispatch |\n| :------- | :---------------- | -----------: | -------------: | -----------: | ------: | -----------------: |\n| fib      | `bench/fib.lua`   | 1.000 s ±2% | 200.000 s ±2% | 8.000 s ±2% | not yet |            not yet |\n| nbody    | `bench/nbody.lua` | 2.000 s ±2% | 100.000 s ±2% |      not yet |     n/a |                n/a |\n")
        t |> equal(work_of(c, "fib", "interp"), 200.0lf)
        // the in-process seconds stand even where the whole run says otherwise
        var other <- fixture()
        other.cells[4].time = 500.0lf
        t |> equal(row_of(render_work(other), "fib")[2], "200.000 s ±2%")
    }
    t |> run("a capture made before the wrapper: each cell less its lane's startup cell, marked, the spread both half ranges over the work time") @(t : T?) {
        let c <- subtracted(fixture())
        t |> equal(render_work(c), "| Workload | Arguments         |                     clang -O3 |                     interpreter |                           JIT |     exe | JIT, goto dispatch |\n| :------- | :---------------- | ----------------------------: | ------------------------------: | ----------------------------: | ------: | -----------------: |\n| fib      | `bench/fib.lua`   | 1.000 s ±4% (by subtraction) | 200.000 s ±2% (by subtraction) | 8.000 s ±3% (by subtraction) | not yet |            not yet |\n| nbody    | `bench/nbody.lua` | 2.000 s ±3% (by subtraction) | 100.000 s ±2% (by subtraction) |                       not yet |     n/a |                n/a |\n")
        t |> equal(work_of(c, "fib", "interp"), 200.0lf)
        // half of 210's 5% range and half of 10's 10% range, 10.5 + 1 s over the 200 s of work
        var spread <- subtracted(fixture())
        for (cl in spread.cells) {
            if (cl.lane == "interp") {
                cl.spread = cl.workload == "startup" ? 0.1lf : 0.05lf
            }
        }
        t |> success(render_work(spread) |> contains("| 200.000 s ±6% (by subtraction) |"), render_work(spread))
    }
    t |> run("by subtraction, a lane without a startup cell has no work times, no ratios, and a not-yet line") @(t : T?) {
        var c <- subtracted(fixture())
        c.cells |> erase(2) // the JIT's startup cell
        t |> equal(work_of(c, "fib", "jit"), 0.0lf)
        t |> equal(join(row_of(render_work(c), "fib"), ","), "`bench/fib.lua`,1.000 s ±4% (by subtraction),200.000 s ±2% (by subtraction),not yet,not yet,not yet")
        t |> equal(join(row_of(render_ratios(c), "fib"), ","), "`bench/fib.lua`,200.00 (by subtraction),n/a,n/a,n/a,n/a,n/a,n/a,n/a")
        t |> success(has_value(render_not_yet(c), "- JIT, every work time: not yet: no startup cell"), join(render_not_yet(c), "\n"))
        var count = 0
        geomean_ratio(c, "jit", count)
        t |> equal(count, 0)
    }
    t |> run("timed inside the process, a lane without a startup cell keeps its work times and ratios, with no not-yet line") @(t : T?) {
        var c <- fixture()
        c.cells |> erase(2) // the JIT's startup cell
        t |> equal(work_of(c, "fib", "jit"), 8.0lf)
        t |> equal(join(row_of(render_work(c), "fib"), ","), "`bench/fib.lua`,1.000 s ±2%,200.000 s ±2%,8.000 s ±2%,not yet,not yet")
        t |> equal(join(row_of(render_ratios(c), "fib"), ","), "`bench/fib.lua`,200.00,8.00,n/a,n/a,25.00,n/a,n/a,n/a")
        t |> success(!has_value(render_not_yet(c), "- JIT, every work time: not yet: no startup cell"), join(render_not_yet(c), "\n"))
    }
    t |> run("by subtraction, a failed startup cell: the lane's work times and ratios are not yet, the cell and the lane each named") @(t : T?) {
        var c <- subtracted(fixture())
        c.cells[1] <- failed("startup", "interp", "exited 9")
        t |> equal(join(row_of(render_work(c), "fib"), ","), "`bench/fib.lua`,1.000 s ±4% (by subtraction),not yet,8.000 s ±3% (by subtraction),not yet,not yet")
        t |> equal(join(row_of(render_ratios(c), "fib"), ","), "`bench/fib.lua`,n/a,8.00 (by subtraction),n/a,n/a,n/a,n/a,n/a,n/a")
        t |> equal(join(row_of(render_startup(c), "interpreter"), ","), "not yet,n/a")
        let lines <- render_not_yet(c)
        t |> success(has_value(lines, "- startup, interpreter: not yet: exited 9") && has_value(lines, "- interpreter, every work time: not yet: no startup cell"), join(lines, "\n"))
    }
    t |> run("by subtraction, a cell at or below its lane's startup cell is within the start, with no ratio") @(t : T?) {
        var c <- subtracted(fixture())
        c.cells[5].time = 2.0lf // the JIT's fib, equal to its startup
        t |> equal(row_of(render_work(c), "fib")[3], "within the start (by subtraction)")
        t |> equal(row_of(render_ratios(c), "fib")[2], "n/a")
    }
    t |> run("a ratio with one side by subtraction is marked, and so is a mean over it") @(t : T?) {
        var c <- fixture()
        c.cells[3].work_samples |> clear() // native fib: 1.5 s less native's 0.5 s startup
        t |> equal(row_of(render_ratios(c), "fib")[1], "200.00 (by subtraction)")
        t |> equal(row_of(render_ratios(c), "fib")[5], "25.00")
        var captures : array<Capture>
        captures |> emplace(c)
        t |> success(render_projects(captures) |> contains("| 100.00 (by subtraction) |"), render_projects(captures))
    }
    t |> run("a mean is marked only over a ratio by subtraction that enters it") @(t : T?) {
        var c <- fixture()
        c.cells[9].work_samples |> clear() // the interpreter's nbody by subtraction
        c.cells[8] <- failed("nbody", "native", "exited 1") // so its ratio is missing, out of the mean
        var captures : array<Capture>
        captures |> emplace(c)
        t |> equal(row_of(render_projects(captures), "[lua](lua/README.md)")[3], "200.00 (1 of 2)")
    }
}

[test]
def test_suspect(t : T?) {
    t |> run("an in-process work time whose spread is above 20% is suspect: its spread alone, no ratio, out of the geometric mean") @(t : T?) {
        var c <- fixture()
        c.cells[4].work_time_spread = 0.3lf // the interpreter's fib
        t |> equal(row_of(render_times(c), "fib")[2], "210.000 s ±2%")
        t |> equal(row_of(render_work(c), "fib")[2], "suspect (±30.0%)")
        t |> equal(join(row_of(render_ratios(c), "fib"), ","), "`bench/fib.lua`,suspect,8.00,n/a,n/a,suspect,suspect,suspect,n/a")
        var count = 0
        t |> equal(round(geomean_ratio(c, "interp", count) * 1000.0lf), 50000.0lf)
        t |> equal(count, 1)
    }
    t |> run("by subtraction, a cell whose spread is above 20% is suspect: its spread alone, no ratio, out of the geometric mean") @(t : T?) {
        var c <- subtracted(fixture())
        c.cells[4].spread = 0.3lf // the interpreter's fib: 63 s of its 210 s, 63.2 s of its 200 s of work
        t |> equal(row_of(render_times(c), "fib")[2], "suspect (±30.0%)")
        t |> equal(render_work(c), "| Workload | Arguments         |                     clang -O3 |                        interpreter |                           JIT |     exe | JIT, goto dispatch |\n| :------- | :---------------- | ----------------------------: | ---------------------------------: | ----------------------------: | ------: | -----------------: |\n| fib      | `bench/fib.lua`   | 1.000 s ±4% (by subtraction) | suspect (±31.6%) (by subtraction) | 8.000 s ±3% (by subtraction) | not yet |            not yet |\n| nbody    | `bench/nbody.lua` | 2.000 s ±3% (by subtraction) |    100.000 s ±2% (by subtraction) |                       not yet |     n/a |                n/a |\n")
        t |> equal(join(row_of(render_ratios(c), "fib"), ","), "`bench/fib.lua`,suspect (by subtraction),8.00 (by subtraction),n/a,n/a,suspect (by subtraction),suspect (by subtraction),suspect (by subtraction),n/a")
        var count = 0
        t |> equal(round(geomean_ratio(c, "interp", count) * 1000.0lf), 50000.0lf)
        t |> equal(count, 1)
    }
    t |> run("by subtraction, a suspect startup cell makes every work time of its lane suspect: no number, no ratio, out of the geometric mean") @(t : T?) {
        var c <- subtracted(fixture())
        c.cells[1].spread = 0.25lf // the interpreter's startup: 2.5 s of 10 s; fib's own work spread stays 3%
        t |> equal(join(row_of(render_startup(c), "interpreter"), ","), "suspect (±25.0%),suspect")
        t |> equal(row_of(render_work(c), "fib")[2], "suspect (startup) (by subtraction)")
        t |> equal(row_of(render_ratios(c), "fib")[1], "suspect (by subtraction)")
        var count = 0
        t |> equal(geomean_ratio(c, "interp", count), 0.0lf)
        t |> equal(count, 0)
    }
    t |> run("timed inside the process, a suspect startup cell leaves the lane's work times and ratios standing") @(t : T?) {
        var c <- fixture()
        c.cells[1].spread = 0.25lf
        t |> equal(join(row_of(render_startup(c), "interpreter"), ","), "suspect (±25.0%),suspect")
        t |> equal(row_of(render_work(c), "fib")[2], "200.000 s ±2%")
        t |> equal(row_of(render_ratios(c), "fib")[1], "200.00")
        var count = 0
        t |> equal(round(geomean_ratio(c, "interp", count) * 1000.0lf), round(sqrt(200.0lf * 50.0lf) * 1000.0lf))
        t |> equal(count, 2)
    }
}

[test]
def test_suspect_edges(t : T?) {
    t |> run("an in-process spread of exactly 20% is a number, above it suspect") @(t : T?) {
        var c <- fixture()
        c.cells[4].work_time_spread = 0.2lf
        t |> equal(row_of(render_work(c), "fib")[2], "200.000 s ±20%")
        t |> equal(row_of(render_ratios(c), "fib")[1], "200.00")
        c.cells[4].work_time_spread = 0.21lf
        t |> equal(row_of(render_work(c), "fib")[2], "suspect (±21.0%)")
        t |> equal(row_of(render_ratios(c), "fib")[1], "suspect")
    }
    t |> run("by subtraction, a spread of exactly 20% is a number, above it suspect: a cell and its work time") @(t : T?) {
        var c <- subtracted(fixture())
        // the interpreter's startup at 0 s without spread, so fib's work spread is its cell's
        c.cells[1].time = 0.0lf
        c.cells[1].spread = 0.0lf
        c.cells[4].spread = 0.2lf
        t |> equal(row_of(render_times(c), "fib")[2], "210.000 s ±20%")
        t |> equal(row_of(render_work(c), "fib")[2], "210.000 s ±20% (by subtraction)")
        t |> equal(row_of(render_ratios(c), "fib")[1], "210.00 (by subtraction)")
        c.cells[4].spread = 0.21lf
        t |> equal(row_of(render_times(c), "fib")[2], "suspect (±21.0%)")
        t |> equal(row_of(render_work(c), "fib")[2], "suspect (±21.0%) (by subtraction)")
        t |> equal(row_of(render_ratios(c), "fib")[1], "suspect (by subtraction)")
    }
    t |> run("by subtraction, a startup cell of exactly 20% is a number with its ratio, above it suspect") @(t : T?) {
        var c <- subtracted(fixture())
        c.cells[1].spread = 0.2lf
        t |> equal(join(row_of(render_startup(c), "interpreter"), ","), "10.000 s ±20%,20.00")
        t |> equal(row_of(render_work(c), "fib")[2], "200.000 s ±3% (by subtraction)")
        t |> equal(row_of(render_ratios(c), "fib")[1], "200.00 (by subtraction)")
        c.cells[1].spread = 0.21lf
        t |> equal(join(row_of(render_startup(c), "interpreter"), ","), "suspect (±21.0%),suspect")
        t |> equal(row_of(render_work(c), "fib")[2], "suspect (startup) (by subtraction)")
    }
    t |> run("a suspect native work time, the base of a ratio: the das lanes' ratios over it are suspect, out of the mean") @(t : T?) {
        var c <- fixture()
        c.cells[3].work_time_spread = 0.3lf // native fib
        t |> equal(ratio_of(c, "fib", "interp", "native"), 0.0lf)
        t |> equal(join(row_of(render_ratios(c), "fib"), ","), "`bench/fib.lua`,suspect,suspect,suspect,suspect,25.00,n/a,n/a,n/a")
        var count = 0
        t |> equal(round(geomean_ratio(c, "interp", count) * 1000.0lf), 50000.0lf)
        t |> equal(count, 1)
    }
    t |> run("a suspect native startup cell: every lane's startup ratio is suspect") @(t : T?) {
        var c <- fixture()
        c.cells[0].spread = 0.3lf
        t |> equal(join(row_of(render_startup(c), "clang -O3"), ","), "suspect (±30.0%),suspect")
        t |> equal(join(row_of(render_startup(c), "interpreter"), ","), "10.000 s ±2%,suspect")
    }
    t |> run("no standing native startup cell: the startup ratios are missing") @(t : T?) {
        var c <- fixture()
        c.cells[0] <- failed("startup", "native", "exited 1")
        t |> equal(join(row_of(render_startup(c), "clang -O3"), ","), "not yet,n/a")
        t |> equal(join(row_of(render_startup(c), "interpreter"), ","), "10.000 s ±2%,n/a")
    }
    t |> run("by subtraction, a capture without a startup row has no startup cell under any lane") @(t : T?) {
        var c <- subtracted(fixture())
        c.workloads |> erase(0)
        t |> equal(startup_of(c), "")
        t |> equal(join(row_of(render_startup(c), "clang -O3"), ","), "n/a,n/a")
        t |> equal(join(row_of(render_work(c), "fib"), ","), "`bench/fib.lua`,not yet,not yet,not yet,not yet,not yet")
        t |> success(has_value(render_not_yet(c), "- clang -O3, every work time: not yet: no startup cell"), join(render_not_yet(c), "\n"))
    }
}

[test]
def test_layout_lanes(t : T?) {
    t |> run("a layout lane (source-cut or single) the capture measured adds its column and its ratio to its source-layout twin; without one the tables keep their columns") @(t : T?) {
        var c <- fixture()
        c.lanes |> push(Lane(name = "interp-single", command = "run interp-single"))
        c.cells |> emplace(cell("startup", "interp-single", 10.0lf)) // nolint:STYLE012 - appends to the fixture's cells
        c.cells |> emplace(timed_cell("fib", "interp-single", 410.0lf, 400.0lf))
        c.cells |> emplace(timed_cell("nbody", "interp-single", 60.0lf, 50.0lf))
        let ratios = render_ratios(c)
        t |> success(ratios |> contains("| interpreter, single module / native | interpreter / JIT | interpreter / exe | interpreter / JIT, goto dispatch | JIT / JIT, goto dispatch | interpreter, single module / interpreter |"), ratios)
        t |> success(ratios |> contains(" 400.00 |             25.00 |"), ratios)
        t |> success(ratios |> contains(" 2.00 |\n") && ratios |> contains(" 0.50 |\n"), ratios)
        t |> success(!(ratios |> contains("JIT, single module")), ratios)
        var captures : array<Capture>
        captures |> emplace(c)
        let projects = render_projects(captures)
        t |> success(projects |> contains("| JIT, goto dispatch | interpreter, single module |"), projects)
        t |> success(projects |> contains("|                     100.00 |\n"), projects)
        t |> success(!(render_ratios(fixture()) |> contains("single module")))
    }
}

// the fixture with its `jit-goto` lane replaced: `aot` measured with `aot_error` as its lane error
// (none: its cells stand), so the capture has no `jit-goto` lane, as one made before that lane
def private with_aot(aot_error : string) : Capture {
    var c <- fixture()
    c.lanes |> resize(4)
    c.lanes |> push(Lane(name = "aot", command = "run aot", error = aot_error))
    c.cells <- [for (cl in c.cells); cl; where cl.lane != "jit-goto"]
    if (empty(aot_error)) {
        c.cells |> emplace(timed_cell("fib", "aot", 3.0lf, 2.0lf)) // nolint:STYLE012 - appends to the fixture's cells
    } else {
        c.cells |> emplace(failed("fib", "aot", aot_error))
    }
    return <- c
}

[test]
def test_goto_lane(t : T?) {
    t |> run("the goto lane that stands: its column, its ratio to native, and the interpreter and the JIT each over it") @(t : T?) {
        var c <- fixture()
        c.lanes[4].error = ""
        c.cells[7] <- timed_cell("fib", "jit-goto", 5.0lf, 4.0lf)
        t |> equal(row_of(render_work(c), "fib")[5], "4.000 s ±2%")
        t |> equal(join(row_of(render_ratios(c), "fib"), ","), "`bench/fib.lua`,200.00,8.00,n/a,4.00,25.00,n/a,50.00,2.00")
        var captures : array<Capture>
        captures |> emplace(c)
        t |> equal(row_of(render_projects(captures), "[lua](lua/README.md)")[6], "4.00 (1 of 2)")
    }
    t |> run("a capture without the goto lane, its AOT lane a build error: no goto column and no AOT column in any table, the AOT not-yet line kept") @(t : T?) {
        var c <- with_aot("the build exited 1")
        t |> equal(render_work(c), "| Workload | Arguments         |    clang -O3 |    interpreter |          JIT |     exe |\n| :------- | :---------------- | -----------: | -------------: | -----------: | ------: |\n| fib      | `bench/fib.lua`   | 1.000 s ±2% | 200.000 s ±2% | 8.000 s ±2% | not yet |\n| nbody    | `bench/nbody.lua` | 2.000 s ±2% | 100.000 s ±2% |      not yet |     n/a |\n")
        t |> equal(length(row_of(render_startup(c), "JIT, goto dispatch")), 0)
        t |> equal(length(row_of(render_times(c), "fib")), 5)
        let ratios = render_ratios(c)
        t |> equal(join(row_of(ratios, "fib"), ","), "`bench/fib.lua`,200.00,8.00,n/a,25.00,n/a")
        t |> success(!(ratios |> contains("goto")), ratios)
        for (text in [render_work(c), render_startup(c), render_times(c), ratios]) {
            t |> success(!(text |> contains("AOT")), text)
        }
        var captures : array<Capture>
        captures |> push_clone(c)
        let projects = render_projects(captures)
        t |> success(!(projects |> contains("AOT")) && projects |> ends_with("| not yet |\n"), projects)
        t |> success(has_value(render_not_yet(c), "- AOT, every workload: not yet: the build exited 1"), join(render_not_yet(c), "\n"))
        t |> success(render_perf(c) |> contains("- AOT: `run aot`\n"), render_perf(c))
    }
    t |> run("an AOT lane asked for whose build stood: its column after exe's, its ratio to native, the interpreter and the JIT each over it") @(t : T?) {
        var c <- with_aot("")
        let ratios = render_ratios(c)
        t |> success(ratios |> starts_with("| Workload | Arguments         | interpreter / native | JIT / native | exe / native | AOT / native | interpreter / JIT | interpreter / exe | interpreter / AOT | JIT / AOT |"), ratios)
        t |> equal(join(row_of(ratios, "fib"), ","), "`bench/fib.lua`,200.00,8.00,n/a,2.00,25.00,n/a,100.00,4.00")
        t |> equal(join(row_of(render_work(c), "fib"), ","), "`bench/fib.lua`,1.000 s ±2%,200.000 s ±2%,8.000 s ±2%,not yet,2.000 s ±2%")
        var captures : array<Capture>
        captures |> emplace(c)
        t |> equal(row_of(render_projects(captures), "[lua](lua/README.md)")[6], "2.00 (1 of 2)")
        // the ratio heading names the pairs the table renders, the AOT ones included
        let text = render_perf(with_aot(""))
        t |> success(text |> contains("; interpreter over exe; interpreter over AOT; JIT over AOT):"), text)
        t |> success(!(text |> contains("goto dispatch")), text)
    }
    t |> run("the perf section names the goto lane's conversion and its pairs, and the AOT lane only when asked for") @(t : T?) {
        let text = render_perf(fixture())
        t |> success(text |> contains("The JIT, goto dispatch lane runs the JIT over the source layout converted with c2das-re's `--switch-dispatch goto`"), text)
        t |> success(text |> contains("The AOT lanes are measured only when asked for and have a column only where their build stood."), text)
        t |> success(!(text |> contains("A lane `, fast` runs")), text)
        t |> success(text |> contains("(each das lane over native, then interpreter over JIT; interpreter over exe; interpreter over JIT, goto dispatch; JIT over JIT, goto dispatch):"), text)
        t |> success(!(text |> contains("interpreter over AOT")) && !(text |> contains("JIT over AOT")), text)
    }
}

[test]
def test_projects(t : T?) {
    t |> run("the geometric mean skips the startup row and the cells that do not stand") @(t : T?) {
        let c <- fixture()
        var count = 0
        t |> equal(round(geomean_ratio(c, "interp", count) * 1000.0lf), round(sqrt(200.0lf * 50.0lf) * 1000.0lf))
        t |> equal(count, 2)
        t |> equal(round(geomean_ratio(c, "jit", count) * 1000.0lf), 8000.0lf)
        t |> equal(count, 1)
        t |> equal(geomean_ratio(c, "jit-goto", count), 0.0lf)
        t |> equal(count, 0)
    }
    t |> run("a projects row: all workloads bare, some named, none `not yet`") @(t : T?) {
        var captures : array<Capture>
        captures |> emplace(fixture())
        t |> equal(render_projects(captures), "| Program              | Captured             | Machine     | Workloads | interpreter |           JIT |     exe | JIT, goto dispatch |\n| :------------------- | :------------------- | :---------- | --------: | ----------: | ------------: | ------: | -----------------: |\n| [lua](lua/README.md) | 2026-10-22 10:00 UTC | x86_64, CPU |         2 |      100.00 | 8.00 (1 of 2) | not yet |            not yet |\n")
        // a capture made before the wrapper: each mean over ratios by subtraction is marked
        var old : array<Capture>
        old |> emplace(subtracted(fixture()))
        t |> equal(join(row_of(render_projects(old), "[lua](lua/README.md)"), ","), "2026-10-22 10:00 UTC,x86_64, CPU,2,100.00 (by subtraction),8.00 (1 of 2) (by subtraction),not yet,not yet")
    }
    t |> run("the Machine column names the box: the capture's, else its CPU's, else the CPU alone") @(t : T?) {
        var captures : array<Capture>
        captures |> emplace(fixture())
        captures[0].machine.box = "PC"
        t |> success(render_projects(captures) |> contains(" | x86_64, PC (CPU) | "), render_projects(captures))
        captures[0].machine.box = ""
        captures[0].machine.cpu = "AMD FX(tm)-6300 Six-Core Processor"
        t |> success(render_projects(captures) |> contains(" | x86_64, fx (AMD FX(tm)-6300 Six-Core Processor) | "), render_projects(captures))
    }
    t |> run("a capture written before the box field reads with an empty box") @(t : T?) {
        var error : string
        let js = read_json("\{\"program\": \"lua\", \"machine\": \{\"arch\": \"x86_64\", \"cpu\": \"AMD Ryzen 3 1200\"\}\}", error)
        t |> equal(error, "")
        let c <- from_JV(js, type<Capture>)
        t |> equal(c.machine.box, "")
        t |> equal(machine_label(c.machine), "bench (AMD Ryzen 3 1200)")
    }
    t |> run("a capture written before the wrapper reads with no in-process seconds, so it renders by subtraction") @(t : T?) {
        var error : string
        let js = read_json("\{\"program\": \"lua\", \"workloads\": [\{\"name\": \"startup\", \"startup\": true\}, \{\"name\": \"fib\"\}], \"lanes\": [\{\"name\": \"native\"\}], \"cells\": [\{\"workload\": \"startup\", \"lane\": \"native\", \"time\": 0.5, \"samples\": [0.5]\}, \{\"workload\": \"fib\", \"lane\": \"native\", \"time\": 1.5, \"samples\": [1.5]\}]\}", error)
        t |> equal(error, "")
        let c <- from_JV(js, type<Capture>)
        t |> success(empty(c.cells[1].work_samples) && by_subtraction(c, "fib", "native"))
        t |> equal(row_of(render_work(c), "fib")[1], "1.000 s ±0% (by subtraction)")
    }
    t |> run("the top-level README keeps the charter above the marker and replaces what is under it") @(t : T?) {
        var captures : array<Capture>
        captures |> emplace(fixture())
        let none : array<string>
        let first = render_top_readme("# ports\n\ncharter\n", captures, none)
        t |> success(first |> starts_with("# ports\n\ncharter\n\n{README_MARKER}\n\n## Programs\n\n"), first)
        t |> success(first |> contains("[lua](lua/README.md)"), first)
        let again = render_top_readme(first + "stale\n", captures, none)
        t |> equal(again, first)
        // without a capture the projects section is the perf method's one line
        var none_captures : array<Capture>
        t |> equal(render_top_readme(first, none_captures, none), "# ports\n\ncharter\n\n{README_MARKER}\n\n## Programs\n\n{PERF_NOT_YET}\n")
        // a README without the marker is the charter whole, its trailing blanks trimmed
        t |> equal(render_top_readme("# ports\ncharter", none_captures, none), "# ports\ncharter\n\n{README_MARKER}\n\n## Programs\n\n{PERF_NOT_YET}\n")
        // the raw captures copied beside the README, named in one line after the programs
        let raw <- ["compare/results_linux.json", "perf/results_linux.json"]
        t |> equal(render_top_readme("# ports\ncharter", none_captures, raw), "# ports\ncharter\n\n{README_MARKER}\n\n## Programs\n\n{PERF_NOT_YET}\n\nRaw captures beside this README, each copied whole from c2das-re when its tree holds it: `compare/results_linux.json`, `perf/results_linux.json`.\n")
    }
}

[test]
def test_sources(t : T?) {
    t |> run("the license block runs from Copyright (C) to DEALINGS IN THE SOFTWARE., the `* ` stripped") @(t : T?) {
        let header = "/*\n* lua.h\n*/\n/***\n* Copyright (C) 1994 Someone.\n*\n* Permission is granted.\n* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.\n****/\n"
        t |> equal(license_block(header), "Copyright (C) 1994 Someone.\n\nPermission is granted.\nSOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.\n")
        t |> equal(license_block("* Copyright (C) 1994\n* never closed\n"), "")
        t |> equal(license_block("int x;\n"), "")
    }
    t |> run("the license block starts at the last Copyright (C) line inside the comment that ends with the terms") @(t : T?) {
        let header = "/*\n* Copyright (C) 1990 Earlier, no terms.\n*/\nint code;\n/***\n* Copyright (C) 1994 Someone.\n*\n* Permission is granted.\n* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.\n****/\n"
        t |> equal(license_block(header), "Copyright (C) 1994 Someone.\n\nPermission is granted.\nSOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.\n")
        // a comment that closes before the terms holds none, and the next comment's block stands
        t |> equal(license_block("/*\n* Copyright (C) 1990 A.\n*/\n* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.\n"), "")
    }
    t |> run("the VERSIONS.md pin: the version and every tarball with its sha256") @(t : T?) {
        let a = repeat("a", 64)
        let b = repeat("b", 64)
        var release : Release
        t |> success(release_of("# pins\nlua: 9.9 (the release https://x.invalid/lua-9.9.tar.gz (sha256 {a}) and https://x.invalid/t.tar.gz (sha256 {b}))\n", "lua", release))
        t |> equal(release.version, "9.9")
        t |> equal(length(release.tarballs), 2)
        t |> equal(release.tarballs[0].url, "https://x.invalid/lua-9.9.tar.gz")
        t |> equal(release.tarballs[0].sha256, a)
        t |> equal(release.tarballs[1].sha256, b)
        var missing : Release
        t |> success(!release_of("doom: 1\n", "lua", missing))
    }
    t |> run("a pin with a bare version, and a sha256 without a URL, name no tarball") @(t : T?) {
        var bare : Release
        t |> success(release_of("lua: 9.9\n", "lua", bare))
        t |> equal(bare.version, "9.9")
        t |> equal(length(bare.tarballs), 0)
        var no_url : Release
        t |> success(release_of("lua: 9.9 (sha256 {repeat("a", 64)})\n", "lua", no_url))
        t |> equal(length(no_url.tarballs), 0)
    }
}

[test]
def test_project_notes(t : T?) {
    t |> run("an SPDX notice runs through the first non-empty line after the SPDX line") @(t : T?) {
        t |> equal(spdx_notice("/*\nPL_MPEG\nSPDX-License-Identifier: MIT\n\nDominic - https://x\n\nrest\n"), "/*\nPL_MPEG\nSPDX-License-Identifier: MIT\n\nDominic - https://x\n")
        t |> equal(spdx_notice("int x;\n"), "")
        t |> equal(spdx_notice("SPDX-License-Identifier: MIT"), "SPDX-License-Identifier: MIT")
    }
    t |> run("the measured-at line names the commit, the date, and that the output changed since only when the converter did") @(t : T?) {
        t |> equal(measured_at_line("0123456789abcdef", "2026-11-07", false), "Measured at c2das-re `0123456789ab` (2026-11-07).\n\n")
        t |> equal(measured_at_line("0123456789abcdef", "", true), "Measured at c2das-re `0123456789ab`, output changed since: the converter changed between that commit and the one this directory was converted at; no new timing yet.\n\n")
    }
    t |> run("the measured-on line names the entry's date and the capture's commit, and the change only when the converter changed") @(t : T?) {
        t |> equal(measured_on_line("2026-11-06 22:11 UTC", "0123456789abcdef", false), "Measured 2026-11-06 22:11 UTC (capture committed at c2das-re `0123456789ab`).\n\n")
        t |> equal(measured_on_line("2026-11-06 22:11 UTC", "0123456789abcdef", true), "Measured 2026-11-06 22:11 UTC (capture committed at c2das-re `0123456789ab`), output changed since: the converter changed after that date; no new timing yet.\n\n")
    }
    t |> run("an MIT SPDX notice becomes the full MIT text under its author's copyright; another notice stays") @(t : T?) {
        let mit = spdx_license("/*\nPL_MPEG\nSPDX-License-Identifier: MIT\n\nDominic Szablewski - https://phoboslab.org\n")
        t |> success(mit |> starts_with("Copyright (c) Dominic Szablewski\n\nPermission is hereby granted"), mit)
        t |> success(mit |> ends_with("DEALINGS IN THE SOFTWARE.\n"), mit)
        t |> equal(spdx_license("SPDX-License-Identifier: Zlib\nme\n"), "SPDX-License-Identifier: Zlib\nme\n")
    }
}

// a criteria capture with the project rows `rows`, each with `converted` of 3 C files measured
def private criteria_capture(rows : array<string>; converted : int) : CriteriaCapture {
    var cap : CriteriaCapture
    for (row in rows) {
        cap.rows[row] <- sum_raw([{"c_files" => 3, "c_files_converted" => converted, "fn_matched" => 4, "fn_stray_braces" => 1, "c_comment_lines" => 2, "das_comments_carried" => 1}], array<int>(), array<int>())
    }
    return <- cap
}

[test]
def test_project_criteria(t : T?) {
    t |> run("a project's criteria: its row's table under the commit that recorded it, what it measured, the counters' place") @(t : T?) {
        let cap <- criteria_capture(["project/binjgb"], 3)
        let text = project_criteria_text("binjgb", cap, true, "", "0123456789abcdef", false)
        t |> success(text |> starts_with("From c2das-re's `metrics/criteria_linux.json` (`scripts/run_criteria.sh`), its row `project/binjgb`, recorded at c2das-re `0123456789ab`. Measured on the whole program, its 3 C files, converted as this directory's conversion is. "), text)
        t |> success(text |> contains("| Criterion "), text)
        t |> success(text |> contains("project/binjgb |"), text)
        t |> success(text |> contains("| comments "), text)
        t |> success(text |> contains("|           50.0 |"), text)
        t |> success(text |> contains("| stray_braces "), text)
        t |> success(text |> contains("|           75.0 |"), text)
        t |> success(text |> contains("| **total** "), text)
        t |> success(text |> contains("\nThe readability counters of the converted modules (`goto`, `label`, "), text)
        let changed = project_criteria_text("binjgb", cap, true, "", "0123456789abcdef", true)
        t |> success(changed |> contains("recorded at c2das-re `0123456789ab`, output changed since: the converter changed after that commit; not re-measured yet. "), changed)
        let uncommitted = project_criteria_text("binjgb", cap, true, "", "", true)
        t |> success(uncommitted |> contains("its row `project/binjgb`, not committed yet. Measured on "), uncommitted)
        t |> success(!(uncommitted |> contains("changed since")), uncommitted)
    }
    t |> run("a project measured file by file names the files that convert out of all") @(t : T?) {
        let cap <- criteria_capture(["project/wasm3"], 2)
        let text = project_criteria_text("wasm3", cap, true, "", "0123456789abcdef", false)
        t |> success(text |> contains("Measured on the 2 of 3 C files that convert alone, since the program does not convert whole; the other files are in no count, so these criteria describe only the converted files, "), text)
        t |> equal(coverage_text(cap, "project/doomgeneric"), "")
    }
    t |> run("no capture, a capture that does not read and a capture without the row are not-yet lines") @(t : T?) {
        let cap <- criteria_capture(["project/binjgb"], 3)
        t |> equal(project_criteria_text("wasm3", cap, false, "", "", false), "not yet: c2das-re holds no `metrics/criteria_linux.json`, the readability criteria capture.\n")
        t |> equal(project_criteria_text("wasm3", cap, true, "bad: not JSON", "", false), "not yet: bad: not JSON\n")
        t |> equal(project_criteria_text("wasm3", cap, true, "", "0123456789abcdef", false), "not yet: c2das-re's `metrics/criteria_linux.json` holds no row `project/wasm3`; `scripts/run_criteria.sh` records it.\n")
    }
}

// a column of the variant `name` of lua with the knobs `knobs` (key, JSON value) and `lines` das lines
def private column_of(name : string; knobs : array<tuple<string; string>>; lines : int) : VariantColumn {
    var c = VariantColumn(das_lines = lines, execute_lines = lines / 150)
    c.file.program = "lua"
    c.file.name = name
    c.file.knobs |> reserve(length(knobs))
    for (k in knobs) {
        c.file.knobs |> push(VariantKnob(key = k._0, value = k._1, reason = "r"))
    }
    return <- c
}

[test]
def test_variants(t : T?) {
    t |> run("both variants side by side: the knobs, the search's numbers, each fallback numbered by its capture, and where each comes from") @(t : T?) {
        var readable <- column_of("readable", [("fn_macros", "\"fold\""), ("forms_off", "[]")], 120000)
        readable.file.results.has_criteria = true
        readable.file.results.criteria = CriteriaResult(total = 88.94lf, row = "lua", commit = "0123456789abcdef", date = "2026-11-13", command = "scripts/run_criteria.sh")
        readable.criteria_from = "unused"
        readable.speed_fallback["interp"] = 31.0lf
        readable.speed_fallback["jit"] = 2.6lf
        readable.speed_from = "the latest capture, of another conversion"
        var fast <- column_of("fast", [("fn_macros", "\"expand\""), ("checks", "\"off\"")], 130500)
        fast.file.results.has_speed = true
        fast.file.results.notes = "the interpreter is faster under fn_macros expand"
        fast.file.results.speed.over = "the geometric mean of the four benchmarks' work times"
        fast.file.results.speed.commit = "fedcba9876543210"
        fast.file.results.speed.date = "2026-11-14"
        fast.file.results.speed.box = "bench"
        fast.file.results.speed.command = "heavy --exclusive"
        fast.file.results.speed.quiet = true
        fast.file.results.speed.x_native["interp"] = 30.123lf
        fast.file.results.speed.x_native["jit"] = 2.5lf
        fast.criteria_fallback = 80.0lf
        fast.criteria_from = "the row `lua@fn-macros-expand` of metrics/criteria_linux.json"
        fast.speed_fallback["exe"] = 2.8lf
        fast.speed_from = "the latest capture, of another conversion"
        var columns : array<VariantColumn> <- [ <- readable, <- fast]
        let text = render_variants(columns, true)
        t |> success(text |> starts_with("- `readable/` - for reading and changing the code: Boris, and the weak-model add-a-feature check.\n- `fast/` - for running.\n"), text)
        t |> equal(join(row_of(text, "`fn_macros`"), "|"), "`fold`|`expand`")
        t |> equal(join(row_of(text, "`checks`"), "|"), "-|`off`")
        t |> equal(join(row_of(text, "`forms_off`"), "|"), "`[]`|-")
        t |> equal(join(row_of(text, "Criteria total, %"), "|"), "88.9|80.0 (1)")
        t |> equal(join(row_of(text, "x native, interpreter"), "|"), "31.00 (2)|30.12")
        t |> equal(join(row_of(text, "x native, JIT"), "|"), "2.60 (2)|2.50")
        t |> equal(join(row_of(text, "x native, exe"), "|"), "not yet|not yet")
        t |> equal(join(row_of(text, "x native, AOT"), "|"), "not yet|not yet")
        t |> equal(join(row_of(text, "das lines"), "|"), "120000|130500")
        t |> equal(join(row_of(text, "`luaV_execute` lines"), "|"), "800|870")
        t |> success(text |> contains("- `readable/` criteria: its search, row `lua`, at c2das-re `0123456789ab` (2026-11-13), `scripts/run_criteria.sh`.\n"), text)
        t |> success(text |> contains("- `fast/` speed: its search, the geometric mean of the four benchmarks' work times, at c2das-re `fedcba987654` (2026-11-14) on bench, `heavy --exclusive`, an exclusive run on a quiet machine.\n"), text)
        t |> success(text |> contains("- `fast/`: the interpreter is faster under fn_macros expand\n"), text)
        t |> success(text |> contains("- (1) not from a search of the variant: the row `lua@fn-macros-expand` of metrics/criteria_linux.json\n- (2) not from a search of the variant: the latest capture, of another conversion\n"), text)
        t |> success(!(text |> contains("unused")), text)
        // the fast column converts with checks off: its README says what that gives up, once
        t |> success(text |> contains("\n`fast/` is converted with `checks: off`: no null or bounds checks, so C bugs are not caught (a null access is a SIGSEGV; an out-of-bounds index reads neighbour memory; AOT keeps its range checks); use `readable/` to debug.\n"), text)
        t |> success(!(text |> contains("`readable/` is converted with `checks: off`")), text)
        let no_execute = render_variants(columns, false)
        t |> equal(length(row_of(no_execute, "`luaV_execute` lines")), 0)
    }
}
