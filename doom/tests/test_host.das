options gen2
// the pipeline parses clang's JSON dump below its own frames
options stack = 1048576
require dastest/testing_boost public
require strings
require daslib/fio
require daslib/strings_boost
require ../convert_check.das
require ../../converter/pipeline.das
require ../../converter/tiers.das

//! `doom/host/doom_main.c` converted over a stand-in Doom and run under every tier: the
//! timedemo's exit callback, `-tics N`, and `-return-from-main`, under which each exit is a return
//! from `main` with the same exit code and daslang's instrumenting profiler prints its summary.

// the stand-in Doom: the four calls the host makes and `gametic`; each update is a tic, the
// fourth ends in the timedemo's line and the exit callback with -1, as I_Error does
let STAND_IN_H = "typedef void (*doom_gettime_fn)(int *sec, int *usec);\ntypedef void (*doom_exit_fn)(int code);\nvoid doom_set_gettime(doom_gettime_fn fn);\nvoid doom_set_exit(doom_exit_fn fn);\nvoid doom_init(int argc, char **argv, int flags);\nvoid doom_force_update(void);\n"
let STAND_IN_C = "#include <stdio.h>\n#include \"DOOM.h\"\nint gametic = 0;\nstatic doom_exit_fn exit_fn;\nvoid doom_set_gettime(doom_gettime_fn fn) \{ (void)fn; \}\nvoid doom_set_exit(doom_exit_fn fn) \{ exit_fn = fn; \}\nvoid doom_init(int argc, char **argv, int flags) \{ (void)argc; (void)argv; (void)flags; \}\nvoid doom_force_update(void) \{\n    gametic++;\n    if (gametic == 4) \{\n        printf(\"Error: timed 4 gametics in 4 realtics\\n\");\n        exit_fn(-1);\n    \}\n\}\n"

// the host and the stand-in converted into a fresh folder: its `doom_main.das`, "" on failure
def private converted_host(t : T?) : string {
    var error : string
    let root = test_temp_dir()
    mkdir_rec(path_join(root, "src"))
    fwrite(path_join(root, "src/DOOM.h"), STAND_IN_H)
    fwrite(path_join(root, "src/stand.c"), STAND_IN_C)
    let c_paths <- stage_program(path_join(root, "src"), "doom/host/doom_main.c", path_join(root, "work/src"), ["stand"], error)
    t |> equal(error, "", "staged")
    let out = path_join(root, "work/source")
    let res <- convert_program(c_paths, out, TARGET, "", "", "", "", "main", "source")
    t |> equal(res.error, "", "converted")
    return empty(res.error) ? path_join(out, "doom_main.das") : ""
}

// `entry` run under `tier`, with `--das-profiler` when `profiled`, `args` its argv
def private host_run(entry, tier : string; profiled : bool; args : array<string>; var out : string&) : int {
    var flags : array<string>
    if (profiled) {
        flags |> push("--das-profiler")
    }
    if (tier == "jit") {
        // compiled afresh each run: a cached build never prints the JIT's compile-time warnings (F82)
        flags |> push("-jit-no-cache")
    }
    let level = get_env_variable("DAS_LOG_LEVEL")
    // the profiler's summary is a LOG_INFO line
    set_env_variable("DAS_LOG_LEVEL", "info")
    let rc = run_tier(entry, tier, path_join(dir_name(entry), "run_{tier}"), out, CONVERTED_MODULES, 300.0, flags, args)
    set_env_variable("DAS_LOG_LEVEL", level)
    return rc
}

// the profiler summary's root row, `main 1 <time>`, behind the log's `[I] ` or bare
def private has_summary(out : string) : bool {
    for (ln in split(out, "\n")) {
        let row = strip(ln) |> starts_with("[I] ") ? slice(strip(ln), 4) : strip(ln)
        if (row |> starts_with("main 1 ")) {
            return true
        }
    }
    return false
}

let HOST_TIERS = fixed_array("interp", "jit", "exe", "aot")

[test]
def test_host_exits(tt : T?) {
    let entry = converted_host(tt)
    return if (empty(entry))
    for (tier in HOST_TIERS) {
        tt |> run("{tier}: the timedemo's exit leaves through C exit with -1 after the host's timing line") @(t : T?) {
            var out : string
            t |> equal(host_run(entry, tier, false, ["-timedemo", "demo1"], out), 255, out)
            t |> success(out |> contains("host: timed 4 gametics in "), out)
        }
        tt |> run("{tier}: -return-from-main returns the same exit code from main, the timing line the same") @(t : T?) {
            var out : string
            t |> equal(host_run(entry, tier, false, ["-timedemo", "demo1", "-return-from-main"], out), 255, out)
            t |> success(out |> contains("host: timed 4 gametics in "), out)
            t |> success(!(out |> contains("leaves the try arm")), out)
        }
        tt |> run("{tier}: -tics with -return-from-main ends with exit code 0 after the capped tics") @(t : T?) {
            var out : string
            t |> equal(host_run(entry, tier, false, ["-return-from-main", "-tics", "2", "-timedemo", "demo1"], out), 0, out)
            t |> success(out |> contains("host: stopped after 2 tics"), out)
            t |> success(out |> contains("host: timed 2 gametics in "), out)
        }
    }
    tt |> run("the instrumenting profiler prints its summary under -return-from-main, none through C exit") @(t : T?) {
        var out : string
        t |> equal(host_run(entry, "interp", true, ["-timedemo", "demo1", "-return-from-main"], out), 255, out)
        t |> success(has_summary(out), out)
        var exited : string
        host_run(entry, "interp", true, ["-timedemo", "demo1"], exited)
        t |> success(!has_summary(exited), exited)
    }
}
