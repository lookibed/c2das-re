options gen2
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../demo_run.das
require ../../converter/tiers.das

//! The converted program's demo run of `run.das --run` over a stand-in program: a das module
//! that checks its C `argv` and `$DOOMWADDIR/doom2.wad`, then prints the tic lines
//! `$DOOM_STAND_IN` (`<tics>,<desynced tic>,<exit code>,<sleep ms>,<missing tic>,<doubled tic>`)
//! asks for, held to a four-tic stand-in reference log; exit code 255 ends in the timedemo line,
//! any other in a decoy line, an `Error:` line and a later lowercase error line, then the sleep.
//! Like the host, it stops with exit code 0 after `-tics N` tics when N is fewer.

let STAND_IN = "options gen2\nrequire daslib/fio\nrequire strings\nrequire daslib/strings_boost\n[export]\ndef main : int \{\n    let args <- get_command_line_arguments()\n    if (length(args) < 2 || args[length(args) - 2] != \"-timedemo\" || args[length(args) - 1] != \"demo1\" || !stat(get_env_variable(\"DOOMWADDIR\") + \"/doom2.wad\").is_reg) \{\n        print(\"error: no -timedemo demo1 or no doom2.wad\\n\")\n        return 2\n    \}\n    let mode <- [for (field in split(get_env_variable(\"DOOM_STAND_IN\"), \",\")); to_int(field)]\n    let at = find_index(args, \"-tics\")\n    let cap = at >= 0 ? to_int(args[at + 1]) : mode[0]\n    for (tic in range(cap < mode[0] ? cap : mode[0])) \{\n        if (tic != mode[4]) \{\n            print(\"tic=\{tic\} cs=0000000\{tic == mode[1] ? 9 : tic\}\\n\")\n        \}\n        if (tic == mode[5]) \{\n            print(\"tic=\{tic\} cs=0000000\{tic\}\\n\")\n        \}\n    \}\n    if (cap < mode[0]) \{\n        print(\"host: stopped after \{cap\} tics\\n\")\n        return 0\n    \}\n    print(mode[2] == 255 ? \"Error: timed \{mode[0]\} gametics in \{mode[0]\} realtics\\n\" : \"Z_Init: decoy\\nError: boom\\nerror: later\\n\")\n    if (mode[3] > 0) \{\n        sleep(uint(mode[3]))\n    \}\n    return mode[2]\n\}\n"

// a fresh scratch folder, "" when none can be made
def private scratch(name : string) : string {
    var error : string
    let dir = create_temp_directory(name, error)
    return empty(error) ? dir : ""
}

// the spec of a run of the stand-in under a fresh folder: the program, a wad, the four-tic
// reference log in the second of two reference folders, `tics` tic lines compared
def private stand_in_spec(tics : int) : DemoSpec {
    let root = scratch("doom_demo_run")
    fwrite(path_join(root, "doom_main.das"), STAND_IN)
    fwrite(path_join(root, "stand.wad"), "IWAD")
    mkdir_rec(path_join(root, "ref"))
    fwrite(path_join(root, "ref/stand_demo1.log"), "# stand-in\n" + join([for (tic in range(4)); "tic={tic} cs=0000000{tic}"], "\n") + "\n")
    return <- DemoSpec(entry = path_join(root, "doom_main.das"), tier = "interp", wad = path_join(root, "stand.wad"), demo = 1, tics = tics, timeout = 60.0, work = path_join(root, "work"), ref_dirs <- [path_join(root, "none"), path_join(root, "ref")])
}

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
