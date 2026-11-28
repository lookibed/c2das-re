options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../demo_run.das
require ../../converter/tiers.das
require _stand_in

//! The converted program's demo run of `run.das --run` over the stand-ins of `_stand_in.das`, held
//! to their four-tic reference log.

// the stand-in run in `mode` against `spec`
def private run_stand_in(spec : DemoSpec; mode : string) : DemoRun {
    set_env_variable("DOOM_STAND_IN", mode)
    return run_converted(spec)
}

[test]
def test_sync(t : T?) {
    t |> run("every tic of the reference in sync, the wad and argv passed") @(t : T?) {
        let spec <- stand_in_spec(0)
        let run = run_stand_in(spec, "4,-1,255,0,-1,-1")
        let lines <- run_report(spec, run)
        t |> equal(run.error, "")
        t |> equal(run.rc, 255)
        t |> equal(run.error_line, "")
        t |> success(in_sync(run))
        t |> success(lines[0] |> contains(": 4 tics in sync against "), lines[0])
        t |> success(lines[0] |> ends_with("ref/stand_demo1.log"), lines[0])
        t |> success(lines[1] |> ends_with(": exit 255"), lines[1])
        t |> success(lines[2] |> contains(" s per 35 tics (4 tics in "), lines[2])
        t |> equal(run.timing.tics, 4)
        t |> equal(run.timing.seconds, 0.25lf)
    }
    t |> run("--tics bounds the comparison: a desync past it is not held") @(t : T?) {
        let spec <- stand_in_spec(2)
        let run = run_stand_in(spec, "4,3,255,0,-1,-1")
        let lines <- run_report(spec, run)
        t |> success(in_sync(run))
        t |> success(lines[0] |> contains(": 2 tics in sync"), lines[0])
    }
    t |> run("--tics stops the program: -tics N goes before -timedemo") @(t : T?) {
        let spec <- stand_in_spec(2)
        t |> equal(join(program_argv(spec), " "), "-tics 2 -timedemo demo1")
        let run = run_stand_in(spec, "4,-1,255,0,-1,-1")
        t |> equal(run.tics, 2)
        t |> equal(run.rc, 0)
        t |> equal(run.error_line, "")
        t |> success(in_sync(run))
        t |> equal(join(program_argv(stand_in_spec(0)), " "), "-timedemo demo1")
    }
}

[test]
def test_native(t : T?) {
    t |> run("the native lane runs the build alone, held to the reference as a tier is") @(t : T?) {
        var spec <- stand_in_spec(0)
        spec.entry = path_join(dir_name(spec.wad), "doom")
        t |> success(write_native_stand_in(spec.entry))
        spec.tier = NATIVE_LANE
        set_env_variable("DOOM_NATIVE_DESYNC", "")
        let run = run_converted(spec)
        t |> equal(run.error, "")
        t |> equal(run.rc, 255)
        t |> success(in_sync(run))
        t |> equal(run.timing.tics, 4)
        t |> equal(run.timing.seconds, 0.125lf)
    }
    t |> run("a native tic line off the reference is a desync") @(t : T?) {
        var spec <- stand_in_spec(0)
        spec.entry = path_join(dir_name(spec.wad), "doom")
        t |> success(write_native_stand_in(spec.entry))
        spec.tier = NATIVE_LANE
        set_env_variable("DOOM_NATIVE_DESYNC", "1")
        let run = run_converted(spec)
        set_env_variable("DOOM_NATIVE_DESYNC", "")
        t |> success(!in_sync(run))
        t |> equal(run.sync.in_sync, 2)
        t |> equal(run.sync.fields, "cs")
    }
    t |> run("no native build") @(t : T?) {
        var spec <- stand_in_spec(0)
        spec.entry = path_join(dir_name(spec.wad), "doom")
        spec.tier = NATIVE_LANE
        let run = run_converted(spec)
        t |> success(run.error |> ends_with("/doom; run --native"), run.error)
    }
}

[test]
def test_speed(t : T?) {
    t |> run("a speed build is held to the demo's end alone, printing no tic line") @(t : T?) {
        var spec <- stand_in_spec(0)
        spec.entry = path_join(dir_name(spec.wad), "doom_main_speed.das")
        fwrite(spec.entry, STAND_IN)
        spec.speed = true
        let run = run_stand_in(spec, "4,-1,255,0,-1,-1")
        let lines <- run_report(spec, run)
        t |> equal(run.tics, 0)
        t |> success(in_sync(run))
        t |> equal(run.timing.tics, 4)
        t |> equal(run.final, "tic=3 cs=00000003")
        t |> success(lines[0] |> contains(": speed build ended in `timed 4 gametics`, its `final` line the reference's last tic against "), lines[0])
    }
    t |> run("a speed run whose final line is not the reference's last tic is out of sync") @(t : T?) {
        var spec <- stand_in_spec(0)
        spec.entry = path_join(dir_name(spec.wad), "doom_main_speed.das")
        fwrite(spec.entry, STAND_IN)
        spec.speed = true
        let run = run_stand_in(spec, "4,3,255,0,-1,-1")
        t |> success(!in_sync(run))
        t |> equal(run.sync.fields, "cs")
        t |> equal(speed_summary(run), "speed build ended in `timed 4 gametics`, expected the final `tic=3 cs=00000003`, got `tic=3 cs=00000009`")
    }
    t |> run("a speed run that prints tic lines is the sync build in its place") @(t : T?) {
        var spec <- stand_in_spec(0)
        spec.speed = true
        let run = run_stand_in(spec, "4,-1,255,0,-1,-1")
        t |> success(!in_sync(run))
        t |> equal(speed_summary(run), "speed build ended in `timed 4 gametics`, yet printed 4 tic lines, expected the final `tic=3 cs=00000003`, got no `final` line")
    }
    t |> run("a speed run that does not end in the timedemo line") @(t : T?) {
        var spec <- stand_in_spec(0)
        spec.entry = path_join(dir_name(spec.wad), "doom_main_speed.das")
        fwrite(spec.entry, STAND_IN)
        spec.speed = true
        let run = run_stand_in(spec, "4,-1,0,0,-1,-1")
        t |> success(!in_sync(run))
        t |> equal(speed_summary(run), "speed build did not end in `timed 4 gametics`")
    }
}

[test]
def test_desync(t : T?) {
    t |> run("the first desynced tic, expected against got") @(t : T?) {
        let spec <- stand_in_spec(0)
        let run = run_stand_in(spec, "4,2,255,0,-1,-1")
        let lines <- run_report(spec, run)
        t |> success(!in_sync(run))
        t |> equal(run.sync.in_sync, 2)
        t |> success(lines[0] |> contains("desync after 2 tics in sync on cs: expected `tic=2 cs=00000002`, got `tic=2 cs=00000009`"), lines[0])
    }
    t |> run("a run past the demo's end desyncs there") @(t : T?) {
        let spec <- stand_in_spec(0)
        let run = run_stand_in(spec, "5,-1,255,0,-1,-1")
        let lines <- run_report(spec, run)
        t |> success(!in_sync(run))
        t |> success(lines[0] |> contains("expected the demo's end after 4 tics, got `tic=4 cs=00000004`"), lines[0])
    }
}

[test]
def test_early_exit(t : T?) {
    let spec <- stand_in_spec(0)
    let run = run_stand_in(spec, "2,-1,3,0,-1,-1")
    let lines <- run_report(spec, run)
    t |> success(!in_sync(run))
    t |> equal(run.rc, 3)
    t |> equal(run.error_line, "Error: boom")
    t |> success(lines[0] |> contains("the run printed 2 of 4 tics, all in sync"), lines[0])
    t |> success(lines[1] |> ends_with(": exit 3"), lines[1])
    t |> success(lines[2] |> ends_with(": first error: Error: boom"), lines[2])
}

[test]
def test_unended(t : T?) {
    t |> run("every tic in sync, then exit 1 without the timedemo line") @(t : T?) {
        let spec <- stand_in_spec(0)
        let run = run_stand_in(spec, "4,-1,1,0,-1,-1")
        let lines <- run_report(spec, run)
        t |> success(!in_sync(run))
        t |> success(lines[0] |> contains(": 4 tics in sync, then the run did not end in `timed 4 gametics` against "), lines[0])
    }
    t |> run("every tic in sync, then a timeout") @(t : T?) {
        var spec <- stand_in_spec(0)
        spec.timeout = 5.0
        let run = run_stand_in(spec, "4,-1,255,60000,-1,-1")
        t |> equal(run.rc, popen_timed_out)
        t |> success(!in_sync(run))
    }
    t |> run("under --tics an exit after the compared tics passes") @(t : T?) {
        let spec <- stand_in_spec(2)
        let run = run_stand_in(spec, "2,-1,1,0,-1,-1")
        let lines <- run_report(spec, run)
        t |> success(in_sync(run))
        t |> success(lines[0] |> contains(": 2 tics in sync against "), lines[0])
        t |> success(lines[1] |> ends_with(": exit 1"), lines[1])
    }
}

[test]
def test_missing_and_doubled(t : T?) {
    t |> run("a missing tic desyncs on the tic it lacks") @(t : T?) {
        let spec <- stand_in_spec(0)
        let lines <- run_report(spec, run_stand_in(spec, "4,-1,255,0,1,-1"))
        t |> success(lines[0] |> contains("desync after 1 tics in sync on tic cs: expected `tic=1 cs=00000001`, got `tic=2 cs=00000002`"), lines[0])
    }
    t |> run("a doubled tic desyncs on the tic after it") @(t : T?) {
        let spec <- stand_in_spec(0)
        let lines <- run_report(spec, run_stand_in(spec, "4,-1,255,0,-1,1"))
        t |> success(lines[0] |> contains("desync after 2 tics in sync on tic cs: expected `tic=2 cs=00000002`, got `tic=1 cs=00000001`"), lines[0])
    }
}

[test]
def test_module_dirs(t : T?) {
    var spec <- stand_in_spec(0)
    fwrite(spec.entry, replace(STAND_IN, "require strings\n", "require strings\nrequire c_runtime/c_exit\n"))
    spec.module_dirs <- [for (dir in CONVERTED_MODULES); get_full_file_name(dir)]
    let run = run_stand_in(spec, "4,-1,255,0,-1,-1")
    t |> success(in_sync(run), run.error_line)
    spec.module_dirs |> clear()
    t |> success(!in_sync(run_stand_in(spec, "4,-1,255,0,-1,-1")))
}

[test]
def test_timeout(t : T?) {
    var spec <- stand_in_spec(0)
    spec.timeout = 5.0
    let run = run_stand_in(spec, "1,-1,255,60000,-1,-1")
    let lines <- run_report(spec, run)
    t |> equal(run.rc, popen_timed_out)
    t |> success(!in_sync(run))
    t |> equal(run.tics, 1)
    t |> success(lines[1] |> ends_with(": timed out after 5 s"), lines[1])
}

[test]
def test_refusals(t : T?) {
    t |> run("no reference log in any folder") @(t : T?) {
        var spec <- stand_in_spec(0)
        spec.ref_dirs <- [path_join(spec.work, "none")]
        let run = run_stand_in(spec, "4,-1,255,0,-1,-1")
        let lines <- run_report(spec, run)
        t |> success(!in_sync(run))
        t |> success(run.error |> starts_with("no reference log stand_demo1.log in "), run.error)
        t |> equal(length(lines), 1)
    }
    t |> run("a wad link that fails stops the run") @(t : T?) {
        let spec <- stand_in_spec(0)
        mkdir_rec(path_join(spec.work, "run"))
        fwrite(path_join(spec.work, "run/stand"), "a file where the run folder goes")
        let run = run_stand_in(spec, "4,-1,255,0,-1,-1")
        t |> success(run.error |> starts_with("cannot link "), run.error)
        t |> success(run.error |> ends_with("run/stand/doom2.wad"), run.error)
    }
    t |> run("no entry module") @(t : T?) {
        var spec <- stand_in_spec(0)
        spec.entry = path_join(spec.work, "doom_main.das")
        let run = run_stand_in(spec, "4,-1,255,0,-1,-1")
        let lines <- run_report(spec, run)
        t |> success(run.error |> ends_with("doom_main.das; run --convert"), run.error)
    }
    t |> run("no wad") @(t : T?) {
        var spec <- stand_in_spec(0)
        let ref_dir = dir_name(spec.wad)
        spec.wad = path_join(ref_dir, "missing.wad")
        fwrite(path_join(ref_dir, "ref/missing_demo1.log"), "tic=0 cs=00000000\n")
        let run = run_stand_in(spec, "4,-1,255,0,-1,-1")
        let lines <- run_report(spec, run)
        t |> success(run.error |> starts_with("no wad "), run.error)
    }
    t |> run("an empty reference log holds nothing in sync") @(t : T?) {
        let spec <- stand_in_spec(0)
        fwrite(path_join(dir_name(spec.wad), "ref/stand_demo1.log"), "# empty\n")
        let run = run_stand_in(spec, "0,-1,255,0,-1,-1")
        let lines <- run_report(spec, run)
        t |> equal(run.error, "")
        t |> success(!in_sync(run))
        t |> success(lines[0] |> contains(": 0 tics in sync"), lines[0])
        // no tic printed, no seconds per 35 tics
        t |> equal(length(lines), 2)
    }
}
