options gen2
require dastest/testing_boost public
require strings
require daslib/strings_boost
require daslib/json_boost
require ../harness.das
require ../demo_run.das
require ../fps.das

//! `fps.das` over fixed runs and captures: a run's fps from the host's line and every reason it
//! gives none (a desync among them), the median and spread of a cell, the suspect bar, the table
//! rendered from a capture and the capture's JSON shape.

// a run of `tics` tics held to the whole demo, in sync and ended, the host timing `seconds`
def private good_run(tics : int; seconds : double) : DemoRun => DemoRun(whole = true, ended = true, rc = 255, tics = tics, sync = TicSync(compared = tics, in_sync = tics), timing = HostTiming(tics = tics, seconds = seconds))

// a cell of `workload` under `lane` from runs of 1000 tics timed `seconds` each
def private cell_of_runs(workload, lane : string; seconds : array<double>) : FpsCell {
    var cell = FpsCell(workload = workload, lane = lane)
    for (s in seconds) {
        add_run(cell, good_run(1000, s))
    }
    return <- cell
}

// a capture of demo1 and demo2 under native, interp and jit, three runs a cell
def private stand_in_capture : FpsCapture {
    var c = FpsCapture(commit = "0123456789ab", timestamp = "2026-11-04 12:00 UTC", platform = "linux x86_64", cpu = "AMD Ryzen 7 7435HS", clang = "clang version 22.1.8", daslang = "0.6.4", samples = 3, clock = FPS_CLOCK)
    c.lanes <- [for (lane in ["native", "interp", "jit"]); FpsLane(name = lane, command = lane_command(lane, "doom/work/native/doom", "doom/work/source/doom_main.das"))]
    c.workloads <- ["demo1", "demo2"]
    var desynced = FpsCell(workload = "demo2", lane = "jit")
    var run = good_run(1000, 1.0lf)
    run.sync = TicSync(compared = 1000, in_sync = 25, desync = "expected `tic=25 cs=1`, got `tic=25 cs=2`", fields = "cs")
    add_run(desynced, run)
    c.cells <- [cell_of_runs("demo1", "native", [1.0lf, 1.0lf, 1.0lf]), cell_of_runs("demo1", "interp", [40.0lf, 39.0lf, 41.0lf]), cell_of_runs("demo1", "jit", [4.0lf, 4.0lf, 4.0lf]), cell_of_runs("demo2", "native", [2.0lf, 2.0lf, 2.0lf]), cell_of_runs("demo2", "interp", [50.0lf, 100.0lf, 75.0lf]), desynced]
    return <- c
}

[test]
def test_run_fps(t : T?) {
    t |> run("a run in sync to the demo's end gives the demo's tics over the host's seconds") @(t : T?) {
        var cell = FpsCell(workload = "demo1", lane = "interp")
        t |> success(add_run(cell, good_run(2664, 26.64lf)))
        t |> equal(cell.error, "")
        t |> equal(cell.tics, 2664)
        t |> equal(cell.fps, 100.0lf)
        t |> equal(cell.spread, 0.0lf)
        t |> equal(length(cell.seconds), 1)
    }
    t |> run("a desync fails the run: no fps, the cell a desync") @(t : T?) {
        var cell = FpsCell()
        var run = good_run(4, 1.0lf)
        run.sync = TicSync(compared = 4, in_sync = 2, desync = "expected `tic=2 cs=2`, got `tic=2 cs=9`", fields = "cs")
        t |> success(!add_run(cell, run))
        t |> success(cell.desync)
        t |> success(cell.error |> starts_with("desync after 2 tics in sync on cs"), cell.error)
        t |> equal(length(cell.samples), 0)
    }
    t |> run("a run in sync that did not end in the timedemo line gives none, not a desync") @(t : T?) {
        var cell = FpsCell()
        var run = good_run(4, 1.0lf)
        run.ended = false
        run.rc = 0
        t |> success(!add_run(cell, run))
        t |> success(!cell.desync)
        t |> equal(cell.error, "4 tics in sync, then the run did not end in `timed 4 gametics` (exit 0)")
    }
    t |> run("a run that did not start, no host line, other tics, no time: none") @(t : T?) {
        var errored = good_run(4, 1.0lf)
        errored.error = "no wad w.wad"
        t |> equal(run_problem(errored), "no wad w.wad")
        var unlined = good_run(4, 1.0lf)
        unlined.timing = HostTiming()
        t |> equal(run_problem(unlined), "no `host: timed N gametics in S s` line")
        var other = good_run(4, 1.0lf)
        other.timing.tics = 3
        t |> equal(run_problem(other), "the host timed 3 gametics, the demo has 4")
        let instant = good_run(4, 0.0lf)
        t |> equal(run_problem(instant), "the host timed 4 gametics in no time")
        var cell = FpsCell()
        t |> success(!add_run(cell, errored))
        t |> success(!cell.desync)
    }
}

[test]
def test_cell(t : T?) {
    t |> run("the median of the runs' fps, the spread half their range over it") @(t : T?) {
        let cell <- cell_of_runs("demo1", "interp", [10.0lf, 8.0lf, 12.5lf])
        t |> equal(cell.samples[0], 100.0lf)
        t |> equal(cell.fps, 100.0lf)
        t |> equal(cell.spread, (125.0lf - 80.0lf) * 0.5lf / 100.0lf)
    }
    t |> run("a failed run keeps the runs before it") @(t : T?) {
        var cell <- cell_of_runs("demo1", "interp", [10.0lf])
        t |> success(!add_run(cell, DemoRun(error = "boom")))
        t |> equal(length(cell.samples), 1)
        t |> equal(cell.fps, 100.0lf)
    }
}

[test]
def test_slowdown(t : T?) {
    t |> run("native fps over the lane's, none for a suspect or failed cell") @(t : T?) {
        let c <- stand_in_capture()
        t |> equal(slowdown(c, "demo1", "interp"), 40.0lf)
        t |> equal(slowdown(c, "demo1", "jit"), 4.0lf)
        t |> equal(slowdown(c, "demo2", "interp"), 0.0lf)
        t |> equal(slowdown(c, "demo2", "jit"), 0.0lf)
        t |> equal(slowdown(c, "demo3", "jit"), 0.0lf)
    }
    t |> run("a spread at 20% stands, above it is suspect") @(t : T?) {
        var c <- stand_in_capture()
        c.cells[1].spread = 0.2lf
        t |> equal(slowdown(c, "demo1", "interp"), 40.0lf)
        c.cells[1].spread = 0.21lf
        t |> equal(slowdown(c, "demo1", "interp"), 0.0lf)
        c.cells[1].spread = 0.0lf
        c.cells[0].spread = 0.21lf
        t |> equal(slowdown(c, "demo1", "interp"), 0.0lf)
    }
}

[test]
def test_render(t : T?) {
    t |> run("the provenance, the table and a line per cell that does not stand") @(t : T?) {
        let text = render_fps(stand_in_capture())
        let want = "Box PC (AMD Ryzen 7 7435HS), linux x86_64; c2das-re `0123456789ab`, captured 2026-11-04 12:00 UTC; clang version 22.1.8; daslang 0.6.4.\n\nPureDOOM `-timedemo demoN` on freedoom2.wad. fps is the demo's gametics over the process CPU time (`clock()`) of the host's update loop in the speed build, which leaves the patch's per-tic checksums and tic lines out: the playback alone, the module load, the JIT compile and `doom_init` outside it. Per demo and lane one run of the sync build first holds every tic to the reference log; a cell is then the median of 3 speed runs, each its own process ending in the demo's `timed N gametics`, ± half the range over the median; above 20% it is `suspect`, without a ratio. `X / native` is native fps over X's.\n\n| Workload |  native fps |        interp fps |    JIT fps | interp / native | JIT / native |\n| :------- | ----------: | ----------------: | ---------: | --------------: | -----------: |\n| demo1    | 1000.0 ±0% |         25.0 ±3% | 250.0 ±0% |            40.0 |          4.0 |\n| demo2    |  500.0 ±0% | suspect (±37.5%) |     desync |         suspect |          n/a |\n\n- demo2, JIT: desync after 25 tics in sync on cs: expected `tic=25 cs=1`, got `tic=25 cs=2`\n"
        t |> equal(text, want)
    }
    t |> run("a suspect cell shows its spread alone, a ratio over it `suspect`, a desync `desync`") @(t : T?) {
        let text = render_fps(stand_in_capture())
        let row <- [for (line in split(text, "\n")); line; where line |> starts_with("| demo2")]
        t |> equal(length(row), 1)
        let cells <- [for (cell in split(row[0], "|")); strip(cell)]
        t |> equal(join(cells, ","), ",demo2,500.0 ±0%,suspect (±37.5%),desync,suspect,n/a,")
        t |> success(text |> ends_with("\n- demo2, JIT: desync after 25 tics in sync on cs: expected `tic=25 cs=1`, got `tic=25 cs=2`\n"), text)
    }
    t |> run("an AOT ratio a fork issue slows carries the issue, the footnote under the table; the other lanes none") @(t : T?) {
        var c <- stand_in_capture()
        c.lanes |> push(FpsLane(name = "aot-fast", command = "a"))
        c.cells |> emplace(cell_of_runs("demo1", "aot-fast", [5.0lf, 5.0lf, 5.0lf]))
        let text = render_fps(c)
        t |> equal(row_cells(text, "demo1"), ",demo1,1000.0 ±0%,25.0 ±3%,250.0 ±0%,200.0 ±0%,40.0,4.0,5.0 (#48),")
        t |> success(text |> ends_with(" runs puredoom 1.14 (readable, demo1) x native: [lookibed/daScript#48](https://github.com/lookibed/daScript/issues/48).\n"), text)
        t |> success(!(render_fps(stand_in_capture()) |> contains("#48")))
    }
    t |> run("a lane without a cell is n/a") @(t : T?) {
        var c <- stand_in_capture()
        c.workloads |> push("demo3")
        let row <- [for (line in split(render_fps(c), "\n")); line; where line |> starts_with("| demo3")]
        t |> equal(join([for (cell in split(row[0], "|")); strip(cell)], ","), ",demo3,n/a,n/a,n/a,n/a,n/a,")
    }
}

// the cells of `workload`'s row in `text`, trimmed
def private row_cells(text, workload : string) : string {
    let rows <- [for (line in split(text, "\n")); line; where line |> starts_with("| {workload} ")]
    return length(rows) == 1 ? join([for (cell in split(rows[0], "|")); strip(cell)], ",") : ""
}

[test]
def test_rendered_bars(t : T?) {
    t |> run("a lane cell at a 20% spread renders its fps and ratio, above it `suspect`") @(t : T?) {
        var c <- stand_in_capture()
        c.cells[1].spread = 0.2lf
        t |> equal(row_cells(render_fps(c), "demo1"), ",demo1,1000.0 ±0%,25.0 ±20%,250.0 ±0%,40.0,4.0,")
        c.cells[1].spread = 0.21lf
        t |> equal(row_cells(render_fps(c), "demo1"), ",demo1,1000.0 ±0%,suspect (±21.0%),250.0 ±0%,suspect,4.0,")
    }
    t |> run("a suspect native cell makes every ratio of its row `suspect`") @(t : T?) {
        var c <- stand_in_capture()
        c.cells[0].spread = 0.2lf
        t |> equal(row_cells(render_fps(c), "demo1"), ",demo1,1000.0 ±20%,25.0 ±3%,250.0 ±0%,40.0,4.0,")
        c.cells[0].spread = 0.21lf
        t |> equal(row_cells(render_fps(c), "demo1"), ",demo1,suspect (±21.0%),25.0 ±3%,250.0 ±0%,suspect,suspect,")
    }
    t |> run("a cell whose run failed other than by a desync renders `failed`") @(t : T?) {
        var c <- stand_in_capture()
        c.cells[2].error = "no `host: timed N gametics in S s` line"
        t |> equal(row_cells(render_fps(c), "demo1"), ",demo1,1000.0 ±0%,25.0 ±3%,failed,40.0,n/a,")
    }
}

[test]
def test_lane_command(t : T?) {
    t |> equal(lane_command("native", "doom/work/native/doom", "e.das"), "prlimit --as=3221225472 doom/work/native/doom -timedemo demo<N>")
    t |> equal(lane_command("interp", "n", "e.das"), "daslang -load_module c_runtime -load_module dasCRuntime e.das -- -timedemo demo<N>")
    t |> equal(lane_command("jit", "n", "e.das"), "daslang -load_module c_runtime -load_module dasCRuntime -jit e.das -- -timedemo demo<N>")
    t |> equal(lane_command("exe", "n", "e.das"), "run_tier exe e.das -- -timedemo demo<N>")
}

[test]
def test_fps_command(t : T?) {
    t |> equal(fps_command("source", ["interp", "jit"], 3, 0), "daslang -load_module dasCRuntime -load_module c_runtime doom/run.das -- --run --fps --layout source --tiers interp,jit --samples 3")
    t |> equal(fps_command("source", ["jit"], 5, 2), "daslang -load_module dasCRuntime -load_module c_runtime doom/run.das -- --run --fps --layout source --tiers jit --samples 5 --demo 2")
}

[test]
def test_capture_json(t : T?) {
    t |> run("the capture's keys, a cell's samples, and the capture back from its JSON") @(t : T?) {
        let c <- stand_in_capture()
        let text = write_json(JV(c))
        var error : string
        let js = read_json(text, error)
        t |> equal(error, "")
        for (key in ["commit", "command", "timestamp", "platform", "cpu", "box", "clang", "daslang", "samples", "clock", "lanes", "workloads", "cells"]) {
            t |> success(js?[key] != null, key)
        }
        t |> equal(js?["lanes"]?[0]?["command"] ?? "", "prlimit --as=3221225472 doom/work/native/doom -timedemo demo<N>")
        t |> equal(js?["cells"]?[1]?["samples"]?[0] ?? 0.0lf, 25.0lf)
        let back <- from_JV(js, type<FpsCapture>)
        t |> equal(render_fps(back), render_fps(c))
    }
}
