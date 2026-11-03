options gen2

module demo_run public

require strings
require daslib/fio
require daslib/strings_boost
require ../converter/tiers.das
require harness
require convert_check

//! The demo runs `run.das` starts (`ARCHITECTURE.md` section 8): the folder a run opens its wad
//! in, the reference log a run is held to, and the converted program's `-timedemo` run under one
//! tier, its tic lines compared with that log.

//! The stem of `wad`'s file name, which names its run folder and its reference logs.
def wad_stem(wad : string) : string => base_name(wad) |> replace(".wad", "")

//! The folder a run over `wad` opens it in: `<work>/run/<wad stem>/`, where `doom2.wad` links to
//! `wad`, since PureDOOM opens `$DOOMWADDIR/doom2.wad`; "" when the link cannot be made.
def wad_dir(work, wad : string) : string {
    let dir = path_join(work, "run/{wad_stem(wad)}")
    mkdir_rec(dir)
    var out : string
    return run_and_capture(["ln", "-sfn", get_full_file_name(wad), path_join(dir, "doom2.wad")], out, 30.0) == 0 ? dir : ""
}

//! `<dir>/<stem>_demo<demo>.log` for the first of `dirs` holding one, "" when none does.
def reference_log(dirs : array<string>; stem : string; demo : int) : string {
    for (dir in dirs) {
        let path = path_join(dir, "{stem}_demo{demo}.log")
        if (stat(path).is_reg) {
            return path
        }
    }
    return ""
}

//! A converted program's demo run: `entry` its entry module under `tier`, `-timedemo demo<demo>`
//! over `wad`, held to the first `tics` tic lines of the reference log (all of them when 0) found
//! in `ref_dirs`; `work` takes the run folder and the tier's builds, `timeout` bounds each process.
struct DemoSpec {
    entry : string
    tier : string
    wad : string
    demo : int
    tics : int
    timeout : float
    work : string
    ref_dirs : array<string>
    module_dirs : array<string>
}

//! A run's outcome: `error` why the program did not run; else its exit code (`popen_timed_out` past
//! the timeout), the seconds it took, the tic lines it printed, the first error line of a run that
//! did not end in the timedemo line and the sync with the reference log `ref_log`. `whole` when the
//! run is held to the whole demo, `ended` when it ended in time in `timed N gametics` with N the
//! reference's tics.
struct DemoRun {
    error : string
    ref_log : string
    whole : bool
    ended : bool
    rc : int
    seconds : double
    tics : int
    error_line : string
    sync : TicSync
}

//! The C `argv` of `spec`'s program: `-timedemo demo<demo>`, after the host's `-tics <tics>` when
//! the comparison is bounded, so the program stops once it has printed the compared tics.
def program_argv(spec : DemoSpec) : array<string> {
    var argv <- spec.tics > 0 ? ["-tics", "{spec.tics}"] : array<string>()
    argv |> push_from(["-timedemo", "demo{spec.demo}"])
    return <- argv
}

//! `spec`'s run: the program run by `run_tier` from the current folder, `DOOMWADDIR` set in this
//! process to the wad's run folder, which the program inherits, the exe and aot builds in its
//! `<entry's folder name>/`; its tic lines, a timed-out run's included, compared with the reference.
def run_converted(spec : DemoSpec) : DemoRun {
    var run = DemoRun()
    let stem = wad_stem(spec.wad)
    run.ref_log = reference_log(spec.ref_dirs, stem, spec.demo)
    if (!stat(spec.entry).is_reg) {
        run.error = "no {spec.entry}; run --convert"
    } elif (empty(run.ref_log)) {
        run.error = "no reference log {stem}_demo{spec.demo}.log in {join(spec.ref_dirs, " or ")}"
    } elif (!stat(spec.wad).is_reg) {
        run.error = "no wad {spec.wad}"
    }
    if (!empty(run.error)) {
        return run
    }
    let dir = wad_dir(spec.work, spec.wad)
    if (empty(dir)) {
        let link = path_join(spec.work, "run/{stem}/doom2.wad")
        run.error = "cannot link {spec.wad} as {link}"
        return run
    }
    set_env_variable("DOOMWADDIR", get_full_file_name(dir))
    let build_dir = path_join(dir, base_name(dir_name(spec.entry)))
    mkdir_rec(build_dir)
    var output : string
    let started = ref_time_ticks()
    run.rc = run_tier(spec.entry, spec.tier, build_dir, output, spec.module_dirs, spec.timeout, array<string>(), program_argv(spec))
    run.seconds = double(get_time_usec(started)) / 1000000.0lf
    let got <- tic_lines(output)
    let expected <- tic_lines(fread(run.ref_log))
    let gametics = timed_gametics(output)
    run.tics = length(got)
    run.whole = spec.tics <= 0
    run.ended = gametics == length(expected) && run.rc != popen_timed_out
    if (gametics < 0) {
        run.error_line = first_error_line(join(non_tic_lines(output), "\n"))
    }
    run.sync = tic_sync(expected, got, spec.tics)
    return run
}

// whether every compared tic of `run` is in sync, the run's end aside
def private tics_in_sync(run : DemoRun) : bool => empty(run.sync.desync) && run.sync.compared > 0 && run.sync.in_sync == run.sync.compared

//! Whether `run` ran and held every compared tic in sync and, held to the whole demo, ended in it.
def in_sync(run : DemoRun) : bool => empty(run.error) && tics_in_sync(run) && (run.ended || !run.whole)

//! The lines `run.das` logs on `spec`'s `run`: the sync, the exit, the first error line and the
//! seconds per 35 tics, a sanity number that counts the program's start.
def run_report(spec : DemoSpec; run : DemoRun) : array<string> {
    let what = "{spec.tier} demo{spec.demo} on {base_name(spec.wad)}"
    if (!empty(run.error)) {
        return <- ["{what}: {run.error}"]
    }
    let unended = run.whole && !run.ended && tics_in_sync(run) ? ", then the run did not end in `timed {run.sync.compared} gametics`" : ""
    var lines <- ["{what}: {sync_summary(run.sync)}{unended} against {run.ref_log}"]
    lines |> push(run.rc == popen_timed_out ? "{what}: timed out after {spec.timeout} s" : "{what}: exit {run.rc}")
    if (!empty(run.error_line)) {
        lines |> push("{what}: first error: {run.error_line}")
    }
    if (run.tics > 0) {
        lines |> push("{what}: {fmt(":.3f", run.seconds * 35.0lf / double(run.tics))} s per 35 tics ({run.tics} tics in {fmt(":.1f", run.seconds)} s)")
    }
    return <- lines
}
