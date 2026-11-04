options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack
options stack = 1048576

require strings
require daslib/fio
require daslib/strings_boost
require daslib/clargs
require daslib/json_boost
require ../converter/pipeline.das
require ../converter/dumper_a.das
require ../converter/sidecar.das
require ../converter/tiers.das
require sources
require harness
require convert_check
require demo_run
require fps
require ../perf/boxes.das
require ../perf/perf_lanes.das
require ../perf/perf_cli.das

//! The PureDOOM harness: `--fetch-check` checks `doom/fetch.sh`'s tree and wad against the pins,
//! `--native` builds the multi-file form with the patches natively into `doom/work/native/doom`,
//! and `--demo <N> --wad <path>` runs `-timedemo demo<N>` on the native build, writing the
//! reference log `doom/work/ref/<wad>_demo<N>.log`; `--run` runs the converted program's demo and
//! holds its tic lines to the reference log. Run from the repository root.

let WORK = "doom/work"
let NATIVE = "doom/work/native/doom"
let PATCHES <- ["doom/patches/0001-per-tic-checksum.patch", "doom/patches/0002-tic-trace.patch", "doom/patches/0003-signed-ticcmd.patch", "doom/patches/0004-fine-table-overruns.patch"]
// the define of the patch's trace lines, the folder of the traces --trace runs write
let TRACE_DEFINE = "DOOM_TIC_TRACE"
let TRACES = "doom/work/trace"
let FREEDOOM2 = "doom/fetch/wads/freedoom2.wad"
let NATIVE_FLAGS <- ["-O2", "-w"]
// the seconds a native demo run may take
let DEMO_TIMEOUT = 600.0
// the folders a converted run's reference log is looked for in: the committed ones, then the local
let REF_DIRS <- ["doom/ref", "doom/work/ref"]
// the capture --fps writes and --readme renders, the README and the markers of its fps section
let FPS_CAPTURE = "doom/results_linux.json"
let README = "README.md"
let FPS_BEGIN = "<!-- doom-fps:begin -->"
let FPS_END = "<!-- doom-fps:end -->"

[CommandLineArgs]
struct Args {
    @clarg_name = "fetch-check"
    @clarg_doc = "check doom/fetch/ against VERSIONS.md: PureDOOM at the pin with the patches applied, freedoom2.wad of the pinned sha256"
    fetch_check : bool
    @clarg_doc = "build the patched multi-file form natively into doom/work/native/doom"
    native : bool
    @clarg_doc = "run -timedemo demo<N> on the native build and write doom/work/ref/<wad>_demo<N>.log; with --run, the demo the converted program runs (default 1)"
    demo : int = 0
    @clarg_doc = "the IWAD --demo and --run run on (default the fetched freedoom2.wad)"
    wad : string = ""
    @clarg_doc = "dump and emit each unit alone, then convert the program in --layout into doom/work/<layout>/, staged in doom/work/src/"
    convert : bool
    @clarg_name = "compile-check"
    @clarg_doc = "compile every module of doom/work/<layout>/ alone with daslang -compile-only"
    compile_check : bool
    @clarg_doc = "the layout --convert, --compile-check and --run take: source, source-cut or single"
    layout : string = "source"
    @clarg_doc = "run doom/work/<layout>/doom_main.das's -timedemo demo<N> under --tier and compare its tic lines with the reference log of the wad and demo"
    run : bool
    @clarg_doc = "the tier --run runs under: interp, jit, exe or aot"
    tier : string = "interp"
    @clarg_doc = "the tic lines --run compares, 0 for the whole demo"
    tics : int = 0
    @clarg_doc = "the seconds --run's program may take"
    timeout : int = 3600
    @clarg_doc = "with DOOM_TIC_TRACE: --native builds doom/work/native/doom-trace, --demo runs it into doom/work/trace/<wad>_demo<N>.native.log in place of a reference log, --convert converts into doom/work/<layout>-trace/ and --run runs that, writes its trace lines beside the native ones and holds them to those as tic lines are held: a traced desync fails the run"
    trace : bool
    @clarg_doc = "with --run: time every demo (or --demo's) natively and under each of --tiers, --samples runs each, every run held to the reference log, and write doom/results_linux.json"
    fps : bool
    @clarg_doc = "the tiers --fps times after native, comma-separated"
    tiers : string = "interp,jit"
    @clarg_doc = "the runs --fps takes per demo and lane, each its own process"
    samples : int = 3
    @clarg_doc = "rewrite README.md's Doom fps section from doom/results_linux.json"
    readme : bool
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

// the fetch check against VERSIONS.md's pins, each problem logged; true when there is none
def private fetch_check : bool {
    let versions = fexist("VERSIONS.md") ? fread("VERSIONS.md") : ""
    var problems <- fetch_problems("doom/fetch/PureDOOM", puredoom_pin(versions), PATCHES, FREEDOOM2, freedoom2_sha256(versions))
    problems |> push_from([for (unit in missing_units(SOURCES, UNITS)); "sources.das lists {unit}, which {SOURCES} lacks"])
    for (problem in problems) {
        to_log(LOG_ERROR, "doom: {problem}\n")
    }
    return empty(problems)
}

// the native build, the traced one apart
def private native_path(trace : bool) : string => trace ? "{NATIVE}-trace" : NATIVE

// the native build's command line: the pinned clang, the flags, the sidecar's defines
def private native_command(defines : array<string>; trace : bool) : array<string> {
    var argv <- [default_clang()]
    argv |> push_from(::NATIVE_FLAGS, [for (define in defines); "-D{define}"], ["-o", native_path(trace)], program_sources())
    argv |> push("-lm")
    return <- argv
}

// the sidecar's defines, TRACE_DEFINE after them with `trace`, "" in `error` when it reads
def private sidecar_defines(trace : bool; var error : string&) : array<string> {
    let side = read_sidecar(SIDECAR, error)
    var defines <- clone_to_move(side.defines)
    if (trace) {
        defines |> push(TRACE_DEFINE)
    }
    return <- defines
}

// the sidecar a traced conversion takes, written into WORK: SIDECAR with TRACE_DEFINE first among
// its defines; "" with `error` set when it cannot be written
def private trace_sidecar(var error : string&) : string {
    mkdir_rec(WORK)
    let path = path_join(WORK, "doom-trace.c2das")
    let text = with_define(fread(SIDECAR), TRACE_DEFINE, error)
    if (!empty(error)) {
        error = "{SIDECAR}: {error}"
    } elif (!fwrite(path, text)) {
        error = "cannot write {path}"
    }
    return empty(error) ? path : ""
}

// the native build, traced with `trace`; false with the compiler's text logged when it fails
def private build_native(trace : bool) : bool {
    var error : string
    let defines <- sidecar_defines(trace, error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "doom: {error}\n")
        return false
    }
    mkdir_rec(dir_name(NATIVE))
    var output : string
    if (run_and_capture(native_command(defines, trace), output, 600.0) != 0) {
        to_log(LOG_ERROR, "doom: native build failed:\n{output}\n")
        return false
    }
    to_log(LOG_INFO, "doom: {native_path(trace)}: {int64(stat(native_path(trace)).size)} bytes\n")
    return true
}

// `-timedemo demo<demo>` on the native build over `wad`, run in `doom/work/run/<stem>/` where
// `doom2.wad` links to it, capped; the reference log written to `doom/work/ref/`, or with `trace`
// the traced build's trace lines to TRACES
def private run_demo(demo : int; wad : string; trace : bool) : bool {
    let wad_sha = file_sha256(wad)
    if (empty(wad_sha)) {
        to_log(LOG_ERROR, "doom: no wad {wad}\n")
        return false
    }
    let native = native_path(trace)
    if (!stat(native).is_reg) {
        to_log(LOG_ERROR, "doom: no {native}; run with --native\n")
        return false
    }
    let stem = wad_stem(wad)
    let dir = wad_dir(WORK, wad)
    let argv <- ["bash", "-c", "cd \"$0\" && DOOMWADDIR=. exec prlimit --as={NATIVE_MEMORY} \"$1\" -timedemo \"$2\"", dir, get_full_file_name(native), "demo{demo}"]
    var output : string
    let rc = run_and_capture(argv, output, DEMO_TIMEOUT)
    if (trace) {
        return write_traces(path_join(TRACES, "{stem}_demo{demo}.native.log"), trace_lines(output))
    }
    var error : string
    let defines <- sidecar_defines(false, error)
    var clang_version : string
    run_and_capture([default_clang(), "--version"], clang_version, 60.0)
    let versions = fread("VERSIONS.md")
    let build = join([default_clang(), join(::NATIVE_FLAGS, " "), join([for (define in defines); "-D{define}"], " ")], " ")
    let header = "PureDOOM {puredoom_pin(versions)} + {patch_list(PATCHES)}; {split(clang_version, "\n")[0]}; build: {build} over sources.das's units and host; wad {base_name(wad)} sha256 {wad_sha}; -timedemo demo{demo}, exit {rc}"
    let log = demo_log(output, header, error)
    if (empty(log)) {
        to_log(LOG_ERROR, "doom: demo{demo} on {base_name(wad)}: {error}\n")
        return false
    }
    let path = path_join(WORK, "ref/{stem}_demo{demo}.log")
    mkdir_rec(dir_name(path))
    fwrite(path, log)
    to_log(LOG_INFO, "doom: {path}: {length(split(log, "\n")) - 2} tics\n")
    return true
}

// `traces` written to `path`, one per line, its count logged; false when none was printed
def private write_traces(path : string; traces : array<string>) : bool {
    mkdir_rec(dir_name(path))
    fwrite(path, join(traces, "\n") + "\n")
    to_log(LOG_INFO, "doom: {path}: {length(traces)} trace lines\n")
    return !empty(traces)
}

// the folder a conversion in `layout` writes, the traced one apart
def private layout_dir(layout : string; trace : bool) : string => path_join(WORK, trace ? "{layout}-trace" : layout)

// the converted program of `layout` run under `tier` on `demo` over `wad` and held to its reference
// log; true when every compared tic is in sync. With `trace` the traced conversion runs, its trace
// lines written to TRACES and held to the native run's as its tic lines are to the reference: a
// missing native trace or a traced desync fails the run too.
def private run_converted_demo(layout, tier : string; demo, tics, timeout : int; wad : string; trace : bool) : bool {
    let spec <- DemoSpec(entry = path_join(layout_dir(layout, trace), "doom_main.das"), tier = tier, wad = wad, demo = demo, tics = tics, timeout = float(timeout), work = WORK, ref_dirs <- clone_to_move(REF_DIRS), module_dirs <- [for (dir in CONVERTED_MODULES); get_full_file_name(dir)])
    let run = run_converted(spec)
    for (line in run_report(spec, run)) {
        to_log(LOG_INFO, "doom: {line}\n")
    }
    var traced = true
    if (trace) {
        let stem = wad_stem(wad)
        write_traces(path_join(TRACES, "{stem}_demo{demo}.{tier}.log"), trace_lines(run.traces))
        let native = path_join(TRACES, "{stem}_demo{demo}.native.log")
        if (!stat(native).is_reg) {
            to_log(LOG_ERROR, "doom: no {native}; run --trace --demo {demo} first\n")
            traced = false
        } else {
            let sync = tic_sync(trace_lines(fread(native)), trace_lines(run.traces), tics)
            to_log(LOG_INFO, "doom: trace against {native}: {sync_summary(sync)}\n")
            traced = empty(sync.desync)
        }
    }
    return in_sync(run) && traced
}

// one line of `git` in the current folder, stripped
def private git_line(args : array<string>) : string {
    var argv <- ["git"]
    argv |> push_from(args)
    var out : string
    run_and_capture(argv, out, 60.0)
    return strip(out)
}

// the cell of `demo` under `lane`: `samples` runs of the native build or of the conversion in
// `layout`, each held to the whole demo; the first run that gives no fps ends the cell
def private fps_cell(layout, lane : string; demo, samples, timeout : int; wad : string) : FpsCell {
    let entry = lane == NATIVE_LANE ? NATIVE : path_join(layout_dir(layout, false), "doom_main.das")
    let spec <- DemoSpec(entry = entry, tier = lane, wad = wad, demo = demo, timeout = float(timeout), work = WORK, ref_dirs <- clone_to_move(REF_DIRS), module_dirs <- [for (dir in CONVERTED_MODULES); get_full_file_name(dir)])
    var cell = FpsCell(workload = "demo{demo}", lane = lane)
    for (_ in range(samples)) {
        let run = run_converted(spec)
        for (line in run_report(spec, run)) {
            to_log(LOG_INFO, "doom: {line}\n")
        }
        if (!add_run(cell, run)) {
            to_log(LOG_ERROR, "doom: {cell.workload}, {lane}: {cell.error}\n")
            break
        }
        to_log(LOG_INFO, "doom: {cell.workload}, {lane}: {run.timing.tics} gametics in {run.timing.seconds} s\n")
    }
    return <- cell
}

// `--fps`: every demo `demos` names under native and each of `tiers`, the capture written to
// FPS_CAPTURE and its table logged; false when a cell does not stand or the capture is not written
def private time_demos(args : Args; tiers : array<string>; demos : array<int>; wad : string) : bool {
    let dirty = empty(git_line(["status", "--porcelain", "--untracked-files=no"])) ? "" : "-dirty"
    var c = FpsCapture(commit = git_line(["rev-parse", "--short=12", "HEAD"]) + dirty, samples = args.samples, clock = FPS_CLOCK)
    c.command = "daslang -load_module dasCRuntime -load_module c_runtime doom/run.das -- --run --fps --layout {args.layout} --tiers {join(tiers, ",")} --samples {args.samples}"
    c.cpu = cpu_name()
    c.box = box_of(c.cpu)
    c.platform = "{get_platform_name()} {machine_arch()}"
    tool_versions(c.clang, c.daslang)
    let entry = path_join(layout_dir(args.layout, false), "doom_main.das")
    var lanes <- [NATIVE_LANE]
    lanes |> push_from(tiers)
    c.lanes <- [for (lane in lanes); FpsLane(name = lane, command = lane_command(lane, NATIVE, entry))]
    var ok = true
    c.workloads |> reserve(length(demos))
    c.cells |> reserve(length(demos) * length(lanes))
    for (demo in demos) {
        c.workloads |> push("demo{demo}")
        for (lane in lanes) {
            var cell <- fps_cell(args.layout, lane, demo, args.samples, args.timeout, wad)
            ok = ok && empty(cell.error)
            c.cells |> emplace(cell)
        }
    }
    c.timestamp = utc_now()
    if (!fwrite(FPS_CAPTURE, write_json(JV(c)) + "\n")) {
        to_log(LOG_ERROR, "doom: cannot write {FPS_CAPTURE}\n")
        return false
    }
    to_log(LOG_INFO, "doom: {FPS_CAPTURE}:\n{render_fps(c)}")
    return ok
}

// `uname -m`, stripped
def private machine_arch : string => strip(captured(["uname", "-m"]))

// the UTC time now as a capture records it
def private utc_now : string => strip(captured(["date", "-u", "+%Y-%m-%d %H:%M UTC"]))

// `--readme`: README's fps section rewritten from FPS_CAPTURE; false when either does not read
def private write_fps_readme : bool {
    var error : string
    let js = read_json_file(FPS_CAPTURE, error)
    if (js == null) {
        to_log(LOG_ERROR, "doom: {FPS_CAPTURE}: {error}\n")
        return false
    }
    let c <- from_JV(js, type<FpsCapture>)
    if (!update_readme(README, render_fps(c), FPS_BEGIN, FPS_END)) {
        to_log(LOG_ERROR, "doom: {README} has no doom-fps markers\n")
        return false
    }
    return true
}

// each verdict logged under `what`, the passed ones counted, then the classification table
def private report(what : string; verdicts : array<Verdict>) : bool {
    var passed = 0
    for (v in verdicts) {
        if (empty(v.error)) {
            passed++
            to_log(LOG_INFO, "doom: {what} {v.name}: ok\n")
        } else {
            to_log(LOG_INFO, "doom: {what} {v.name}: {v.error}\n")
        }
    }
    to_log(LOG_INFO, "doom: {what}: {passed} of {length(verdicts)} pass\n")
    for (row in blocker_table(verdicts)) {
        to_log(LOG_INFO, "doom: {what} blocked by: {row}\n")
    }
    return passed == length(verdicts)
}

// the program staged in `doom/work/src/`, each unit converted alone, then the program in `layout`
def private convert_doom(layout : string; trace : bool) : bool {
    var error : string
    let c_paths <- stage_program(SOURCES, HOST, path_join(WORK, "src"), UNITS, error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "doom: {error}\n")
        return false
    }
    let sidecar = trace ? trace_sidecar(error) : SIDECAR
    let side <- empty(error) ? read_sidecar(sidecar, error) : Sidecar()
    if (!empty(error)) {
        to_log(LOG_ERROR, "doom: {error}\n")
        return false
    }
    let units_ok = report("unit", convert_units(c_paths, side))
    let res <- convert_program(c_paths, layout_dir(layout, trace), TARGET, "", sidecar, "", "", "main", layout)
    if (!res.ok) {
        to_log(LOG_INFO, "doom: program ({layout}): {first_error_line(res.error)}\n")
        to_log(LOG_INFO, "doom: program ({layout}) blocked by: {classify(first_error_line(res.error))}\n")
        return false
    }
    to_log(LOG_INFO, "doom: program ({layout}): {length(res.files)} files, {length(res.partition)} partition lines\n")
    return units_ok
}

[export]
def main : int {
    var args = Args()
    let early = cli_prologue(args, "doom/run.das")
    if (early >= 0) {
        return early
    }
    if (args.demo != 0 && (args.demo < 1 || args.demo > 3)) {
        to_log(LOG_ERROR, "doom: --demo is 1, 2 or 3, not {args.demo}\n")
        return 1
    }
    if (!key_exists(TIERS, args.tier)) {
        to_log(LOG_ERROR, "doom: --tier is interp, jit, exe or aot, not `{args.tier}`\n")
        return 1
    }
    if (!is_layout(args.layout)) {
        to_log(LOG_ERROR, "doom: --layout is source, source-cut or single, not `{args.layout}`\n")
        return 1
    }
    let converted = !args.convert || convert_doom(args.layout, args.trace)
    let compiled = !args.compile_check || report("module", compile_modules(layout_dir(args.layout, args.trace), CONVERTED_MODULES, 600.0))
    let wad = empty(args.wad) ? FREEDOOM2 : args.wad
    let native_failed = (args.fetch_check && !fetch_check()) || (args.native && !build_native(args.trace)) || (args.demo != 0 && !args.run && !run_demo(args.demo, wad, args.trace))
    let tiers <- [for (tier in split(args.tiers, ",")); strip(tier)]
    let bad_tiers <- [for (tier in tiers); tier; where !key_exists(TIERS, tier)]
    if (args.fps && (!empty(bad_tiers) || args.samples < 1 || !args.run || args.tics != 0 || args.trace)) {
        to_log(LOG_ERROR, "doom: --fps goes with --run, without --tics or --trace, --tiers among interp, jit, exe and aot, --samples at least 1\n")
        return 1
    }
    let demos <- args.demo == 0 ? [1, 2, 3] : [args.demo]
    let played = !args.run || (args.fps ? time_demos(args, tiers, demos, wad) : run_converted_demo(args.layout, args.tier, args.demo == 0 ? 1 : args.demo, args.tics, args.timeout, wad, args.trace))
    let failed = !converted || !compiled || native_failed || !played || (args.readme && !write_fps_readme())
    return failed ? 1 : 0
}
