options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require daslib/json_boost
require ../demo_run.das
require ../fps.das
require ../../perf/samples.das
require ../fps_run.das
require ../../converter/tiers.das
require _stand_in

//! `fps_run.das` over the stand-ins of `_stand_in.das`: the flag check, the demos, the capture's
//! head, a cell's runs (the entry each lane takes, the stop at the first run without fps, a native
//! desync), the capture written or not, the README section; and `run.das` itself as a child
//! process, the `--fps` switch against the plain `--run` and a refusal.

// a plan over the stand-ins in a fresh folder: the native scripts and the das entries, sync and
// speed, demo1, `samples` runs a cell, the capture beside them
def private stand_in_plan(samples : int) : FpsPlan {
    let spec <- stand_in_spec(0)
    let root = dir_name(spec.wad)
    write_native_stand_in(path_join(root, "doom"))
    write_native_stand_in(path_join(root, "doom-speed"))
    fwrite(path_join(root, "doom_main_speed.das"), STAND_IN)
    set_env_variable("DOOM_STAND_IN", "4,-1,255,0,-1,-1")
    set_env_variable("DOOM_NATIVE_DESYNC", "")
    set_env_variable("DOOM_NATIVE_SPEED_FAIL", "")
    return <- FpsPlan(sync_native = path_join(root, "doom"), sync_entry = spec.entry, native = path_join(root, "doom-speed"), entry = path_join(root, "doom_main_speed.das"), wad = spec.wad, work = spec.work, ref_dirs <- clone_to_move(spec.ref_dirs), tiers <- ["interp"], demos <- [1], samples = samples, timeout = 60, capture_path = path_join(root, "results.json"))
}

// the native stand-ins' run count, sync and speed, from the `runs` file beside them
def private native_runs(plan : FpsPlan) : int {
    let path = path_join(dir_name(plan.native), "runs")
    return stat(path).is_reg ? length(split(strip(fread(path)), "\n")) : 0
}

[test]
def test_refusal(t : T?) {
    t |> equal(fps_refusal(false, false, ["bogus"], 0, 5, true), "")
    t |> equal(fps_refusal(true, true, ["interp", "jit"], 3, 0, false), "")
    t |> equal(fps_refusal(true, true, ["interp", "bogus"], 3, 0, false), "--tiers takes interp, jit, exe and aot, not `bogus`")
    t |> equal(fps_refusal(true, true, ["interp"], 0, 0, false), "--samples takes at least 1, not 0")
    t |> equal(fps_refusal(true, false, ["interp"], 3, 0, false), "--fps goes with --run")
    t |> equal(fps_refusal(true, true, ["interp"], 3, 10, false), "--fps times the whole demo, not --tics 10")
    t |> equal(fps_refusal(true, true, ["interp"], 3, 0, true), "--fps does not go with --trace")
}

[test]
def test_demos_and_head(t : T?) {
    t |> equal(join([for (d in fps_demos(0)); "{d}"], ","), "1,2,3")
    t |> equal(join([for (d in fps_demos(2)); "{d}"], ","), "2")
    t |> equal(commit_label("0123456789ab", ""), "0123456789ab")
    t |> equal(commit_label("0123456789ab", " M doom/run.das\n"), "0123456789ab-dirty")
    let c <- new_capture("0123456789ab", " M x", "cmd", "AMD Ryzen 7 7435HS", "linux x86_64", "clang 22", "0.6.4", 3)
    t |> equal(c.commit, "0123456789ab-dirty")
    t |> equal(c.box, "PC")
    t |> equal(c.cpu, "AMD Ryzen 7 7435HS")
    t |> equal(c.samples, 3)
    t |> equal(c.spread_rule, RANGE_SPREAD)
    t |> equal(c.pinned_core, -1)
    t |> equal(new_capture("a", "", "cmd", "cpu", "p", "c", "d", 5).spread_rule, TRIMMED_SPREAD)
    t |> equal(c.clock, FPS_CLOCK)
    t |> equal(new_capture("a", "", "cmd", "some other cpu", "p", "c", "d", 1).box, "")
}

// `samples` speed runs of `cell` after its sync run, the first refused ending them
def private sampled(plan : FpsPlan; var cell : FpsCell; samples : int) {
    for (_ in range(samples)) {
        break if (!empty(cell.error) || !fps_sample(plan, 1, cell))
    }
}

[test]
def test_cell(t : T?) {
    t |> run("native runs the native builds, a tier the converted entries: one sync run, then each sample a speed run") @(t : T?) {
        let plan <- stand_in_plan(2)
        var native <- fps_sync(plan, NATIVE_LANE, 1)
        sampled(plan, native, 2)
        t |> equal(native.error, "")
        t |> equal(length(native.samples), 2)
        t |> equal(native.fps, 32.0lf)
        t |> equal(native_runs(plan), 3)
        var interp <- fps_sync(plan, "interp", 1)
        sampled(plan, interp, 2)
        t |> equal(interp.error, "")
        t |> equal(interp.fps, 16.0lf)
        t |> equal(native_runs(plan), 3)
    }
    t |> run("a sync run out of sync is no cell: no speed run follows") @(t : T?) {
        let plan <- stand_in_plan(3)
        set_env_variable("DOOM_NATIVE_DESYNC", "1")
        var cell <- fps_sync(plan, NATIVE_LANE, 1)
        sampled(plan, cell, 3)
        set_env_variable("DOOM_NATIVE_DESYNC", "")
        t |> success(cell.desync)
        t |> success(cell.error |> starts_with("sync build: desync after 2 tics in sync on cs"), cell.error)
        t |> equal(length(cell.samples), 0)
        t |> equal(native_runs(plan), 1)
    }
    t |> run("the first speed run without fps ends the cell, not a desync") @(t : T?) {
        let plan <- stand_in_plan(3)
        set_env_variable("DOOM_NATIVE_SPEED_FAIL", "1")
        var cell <- fps_sync(plan, NATIVE_LANE, 1)
        sampled(plan, cell, 3)
        set_env_variable("DOOM_NATIVE_SPEED_FAIL", "")
        t |> success(!cell.desync)
        t |> equal(cell.error, "speed build did not end in `timed 4 gametics` (exit 0)")
        t |> equal(length(cell.samples), 0)
        t |> equal(native_runs(plan), 2)
    }
}

[test]
def test_time_demos(t : T?) {
    t |> run("the capture written: the head, a lane per tier after native, a cell per demo and lane") @(t : T?) {
        let plan <- stand_in_plan(1)
        var c <- new_capture("0123456789ab", "", "cmd", "AMD Ryzen 7 7435HS", "linux x86_64", "clang 22", "0.6.4", 1)
        t |> success(time_demos(plan, c, "2026-11-04 12:00 UTC"))
        var error : string
        let js = read_json(fread(plan.capture_path), error)
        t |> equal(error, "")
        let back <- from_JV(js, type<FpsCapture>)
        t |> equal(back.commit, "0123456789ab")
        t |> equal(back.box, "PC")
        t |> equal(back.timestamp, "2026-11-04 12:00 UTC")
        t |> equal(join([for (lane in back.lanes); lane.name], ","), "native,interp")
        t |> equal(join(back.workloads, ","), "demo1")
        t |> equal(join([for (cell in back.cells); "{cell.lane}={cell.fps}"], ","), "native=32,interp=16")
    }
    t |> run("every lane's sync run first, then the speed runs in rounds: native first, the tiers forward, then backward") @(t : T?) {
        var plan <- stand_in_plan(3)
        plan.tiers <- ["interp", "jit"]
        var c <- new_capture("a", "", "cmd", "cpu", "p", "c", "d", 3)
        t |> success(time_demos(plan, c, "now"))
        let order = join([for (ln in split(fread(path_join(plan.work, "run/stand/order")), "\n")); ln; where !empty(ln)], ",")
        t |> equal(order, "native 0,interp 0,jit 0,native 1,interp 1,jit 1,native 1,jit 1,interp 1,native 1,interp 1,jit 1")
        t |> equal(join([for (cell in c.cells); "{cell.lane}={length(cell.samples)}"], ","), "native=3,interp=3,jit=3")
    }
    t |> run("a cell that does not stand fails the run, the capture still written") @(t : T?) {
        let plan <- stand_in_plan(1)
        set_env_variable("DOOM_NATIVE_DESYNC", "1")
        var c <- new_capture("a", "", "cmd", "cpu", "p", "c", "d", 1)
        let ok = time_demos(plan, c, "now")
        set_env_variable("DOOM_NATIVE_DESYNC", "")
        t |> success(!ok)
        t |> success(stat(plan.capture_path).is_reg)
    }
    t |> run("a capture that cannot be written fails the run") @(t : T?) {
        var plan <- stand_in_plan(1)
        plan.capture_path = path_join(plan.work, "no/such/folder/results.json")
        var c <- new_capture("a", "", "cmd", "cpu", "p", "c", "d", 1)
        t |> success(!time_demos(plan, c, "now"))
    }
}

// a capture timed over the stand-ins into `c`, its path returned
def private timed_capture(var c : FpsCapture) : string {
    let plan <- stand_in_plan(1)
    delete c
    c <- new_capture("0123456789ab", "", "cmd", "AMD Ryzen 7 7435HS", "linux x86_64", "clang 22", "0.6.4", 1)
    time_demos(plan, c, "now")
    return plan.capture_path
}

[test]
def test_readme(t : T?) {
    t |> run("the section between the markers rewritten, the text around it kept") @(t : T?) {
        var c = FpsCapture()
        let capture_path = timed_capture(c)
        let readme = path_join(dir_name(capture_path), "README.md")
        fwrite(readme, "# top\n{FPS_BEGIN}\nold\n{FPS_END}\nafter\n")
        t |> equal(write_fps_readme(capture_path, readme), "")
        t |> equal(fread(readme), "# top\n{FPS_BEGIN}\n{render_fps(c)}{FPS_END}\nafter\n")
    }
    t |> run("a README without the markers") @(t : T?) {
        var c = FpsCapture()
        let capture_path = timed_capture(c)
        let readme = path_join(dir_name(capture_path), "README.md")
        fwrite(readme, "# no markers\n")
        t |> equal(write_fps_readme(capture_path, readme), "{readme} has no doom-fps markers")
        t |> equal(fread(readme), "# no markers\n")
    }
    t |> run("a capture that does not read") @(t : T?) {
        let root = scratch("doom_fps_readme")
        let bad = path_join(root, "bad.json")
        fwrite(bad, "\{")
        t |> success(write_fps_readme(bad, path_join(root, "README.md")) |> starts_with("{bad}: "))
        t |> success(write_fps_readme(path_join(root, "none.json"), path_join(root, "README.md")) |> starts_with(path_join(root, "none.json")))
    }
}

// `doom/run.das` with `args` as a child process in the empty folder `dir`; its exit code, the
// output in `out`
def private run_das(dir : string; args : array<string>; var out : string&) : int {
    var argv <- ["bash", "-c", "cd \"$0\" && DAS_LOG_LEVEL=info exec \"$@\"", dir]
    argv |> push_from(daslang_cmd([for (m in CONVERTED_MODULES); get_full_file_name(m)]))
    argv |> push(get_full_file_name("doom/run.das"))
    argv |> push("--")
    argv |> push_from(args)
    return run_and_capture(argv, out, 300.0)
}

[test]
def test_run_das(t : T?) {
    let dir = scratch("doom_run_das")
    t |> run("--fps times every lane: native first, no native build there") @(t : T?) {
        var out : string
        t |> equal(run_das(dir, ["--run", "--fps", "--demo", "1", "--tiers", "interp", "--samples", "1"], out), 1)
        t |> success(out |> contains("doom: demo1, native: sync build: no doom/work/native/doom; run --native"), out)
        t |> success(out |> contains("doom: cannot write doom/results_linux.json"), out)
    }
    t |> run("--fps without --tiers times all four tiers after native") @(t : T?) {
        var out : string
        t |> equal(run_das(dir, ["--run", "--fps", "--demo", "1", "--samples", "1"], out), 1)
        for (tier in ["interp", "jit", "exe", "aot"]) {
            t |> success(out |> contains("doom: demo1, {tier}: sync build: "), "{tier}: {out}")
        }
    }
    t |> run("--run without --fps runs the converted demo alone") @(t : T?) {
        var out : string
        t |> equal(run_das(dir, ["--run", "--demo", "1"], out), 1)
        t |> success(out |> contains("interp demo1 on freedoom2.wad: no doom/work/source/doom_main.das; run --convert"), out)
        t |> success(!(out |> contains("doom: demo1, native")), out)
    }
    t |> run("a refused --fps stops before any run") @(t : T?) {
        var out : string
        t |> equal(run_das(dir, ["--run", "--fps", "--tiers", "bogus"], out), 1)
        t |> success(out |> contains("doom: --tiers takes interp, jit, exe and aot, not `bogus`"), out)
        t |> success(!(out |> contains("demo1")), out)
    }
}

[test]
def test_variant(t : T?) {
    let dir = scratch("doom_run_variant")
    mkdir_rec(path_join(dir, "doom"))
    fwrite(path_join(dir, "doom/doom.c2das"), "\{\"defines\": [\"DOOM_TIC_CHECKSUM\"]\}\n")
    fwrite(path_join(dir, "puredoom.fast.json"), "\{\"knobs\": \{\"checks\": \{\"value\": \"off\", \"reason\": \"r\"\}\}\}")
    t |> run("--variant writes the variant's sidecar and runs its conversion under work/variants/<variant>/; --fps writes its capture there") @(t : T?) {
        var out : string
        t |> equal(run_das(dir, ["--run", "--demo", "1", "--variant", "puredoom.fast.json"], out), 1)
        t |> success(out |> contains("interp demo1 on freedoom2.wad: no doom/work/variants/fast/source/doom_main.das; run --convert"), out)
        t |> success(fread(path_join(dir, "doom/work/variants/fast/doom.c2das")) |> contains("\"checks\" : \"off\""), out)
        t |> equal(run_das(dir, ["--run", "--fps", "--demo", "1", "--tiers", "interp", "--samples", "1", "--variant", "puredoom.fast.json"], out), 1)
        t |> success(out |> contains("demo1, interp: sync build: no doom/work/variants/fast/source/doom_main.das"), out)
        t |> success(fexist(path_join(dir, "doom/work/variants/fast/results_linux.json")) && !fexist(path_join(dir, "doom/results_linux.json")), out)
    }
    t |> run("a variant of another program is refused before any run") @(t : T?) {
        fwrite(path_join(dir, "lua.fast.json"), "\{\"knobs\": \{\}\}")
        var out : string
        t |> equal(run_das(dir, ["--run", "--demo", "1", "--variant", "lua.fast.json"], out), 1)
        t |> success(out |> contains("doom: --variant: lua.fast.json is a variant of lua, not of puredoom"), out)
        t |> success(!(out |> contains("demo1")), out)
    }
    rmdir_rec(dir)
}
