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
require doom_sources
require harness
require convert_check
require demo_run
require fps
require fps_run
require ../ports/variants.das
require ../perf/perf_lanes.das

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
// the define of the patch's tic lines and checksums, which the speed builds leave out
let CHECKSUM_DEFINE = "DOOM_TIC_CHECKSUM"
let TRACES = "doom/work/trace"
let FREEDOOM2 = "doom/fetch/wads/freedoom2.wad"
let NATIVE_FLAGS <- ["-O2", "-w"]
// the seconds a native demo run may take
let DEMO_TIMEOUT = 600.0
// the folders a converted run's reference log is looked for in: the committed ones, then the local
let REF_DIRS <- ["doom/ref", "doom/work/ref"]
// the capture --fps writes and --readme renders, and the README it renders into
let FPS_CAPTURE = "doom/results_linux.json"
let README = "README.md"

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
    @clarg_doc = "without DOOM_TIC_CHECKSUM, the speed build --fps times: --native builds doom/work/native/doom-speed, --convert and --compile-check take doom/work/<layout>-speed/"
    speed : bool
    @clarg_doc = "with --run: for every demo (or --demo's), natively and under each of --tiers, one run of the sync build held to the reference log, then --samples runs of the speed build timed; writes doom/results_linux.json"
    fps : bool
    @clarg_doc = "the tiers --fps times after native, comma-separated"
    tiers : string = "interp,jit"
    @clarg_doc = "the runs --fps takes per demo and lane, each its own process"
    samples : int = 3
    @clarg_doc = "rewrite README.md's Doom fps section from doom/results_linux.json"
    readme : bool
    @clarg_name = "variant"
    @clarg_doc = "a variant file of PureDOOM (ports/variants/puredoom.<variant>.json): convert under doom/doom.c2das with the variant's knobs set, written to doom/work/variants/<variant>/doom.c2das; the conversions, the runs of them and --fps's capture then under doom/work/variants/<variant>/"
    variant_file : string = ""
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

// the fetch check against VERSIONS.md's pins, each problem logged; true when there is none
def private fetch_check : bool {
    let versions = fexist("VERSIONS.md") ? fread("VERSIONS.md") : ""
    var problems <- fetch_problems("doom/fetch/PureDOOM", puredoom_pin(versions), PATCHES, FREEDOOM2, freedoom2_sha256(versions))
    problems |> push_from([for (unit in missing_units(SOURCES, UNITS)); "doom_sources.das lists {unit}, which {SOURCES} lacks"])
    for (problem in problems) {
        to_log(LOG_ERROR, "doom: {problem}\n")
    }
    return empty(problems)
}

// the build form of `--trace` and `--speed`, "" for the sync build
def private form_of(trace, speed : bool) : string => trace ? "trace" : speed ? "speed" : ""

// the native build of `form`
def private native_path(form : string) : string => empty(form) ? NATIVE : "{NATIVE}-{form}"

// the native build's command line: the pinned clang, the flags, the sidecar's defines
def private native_command(defines : array<string>; form : string) : array<string> {
    var argv <- [default_clang()]
    argv |> push_from(::NATIVE_FLAGS, [for (define in defines); "-D{define}"], ["-o", native_path(form)], program_sources())
    argv |> push("-lm")
    return <- argv
}

// the sidecar's defines for `form`: TRACE_DEFINE after them for the traced build, CHECKSUM_DEFINE
// left out for the speed build; `error` set when the sidecar does not read
def private sidecar_defines(form : string; var error : string&) : array<string> {
    let side = read_sidecar(SIDECAR, error)
    var defines <- [for (define in side.defines); define; where form != "speed" || define != CHECKSUM_DEFINE]
    if (form == "trace") {
        defines |> push(TRACE_DEFINE)
    }
    return <- defines
}

// the sidecar a conversion of `form` takes: `base` (SIDECAR or the variant's) itself for the sync
// build, else written into `root`, with TRACE_DEFINE first among its defines for the traced build, without CHECKSUM_DEFINE for
// the speed build; "" with `error` set when it cannot be written
def private form_sidecar(root, base, form : string; var error : string&) : string {
    if (empty(form)) {
        return base
    }
    mkdir_rec(root)
    let path = path_join(root, "doom-{form}.c2das")
    let text = form == "trace" ? with_define(fread(base), TRACE_DEFINE, error) : without_define(fread(base), CHECKSUM_DEFINE, error)
    if (!empty(error)) {
        error = "{base}: {error}"
    } elif (!fwrite(path, text)) {
        error = "cannot write {path}"
    }
    return empty(error) ? path : ""
}

// the native build of `form`; false with the compiler's text logged when it fails
def private build_native(form : string) : bool {
    var error : string
    let defines <- sidecar_defines(form, error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "doom: {error}\n")
        return false
    }
    mkdir_rec(dir_name(NATIVE))
    var output : string
    if (run_and_capture(native_command(defines, form), output, 600.0) != 0) {
        to_log(LOG_ERROR, "doom: native build failed:\n{output}\n")
        return false
    }
    to_log(LOG_INFO, "doom: {native_path(form)}: {int64(stat(native_path(form)).size)} bytes\n")
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
    let native = native_path(form_of(trace, false))
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
    let defines <- sidecar_defines("", error)
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

// the folder a conversion of `form` in `layout` writes under `root`
def private form_dir(root, layout, form : string) : string => path_join(root, empty(form) ? layout : "{layout}-{form}")

// the folder the conversions sit in: WORK, or under `--variant` its `variants/<variant>/`
def private root_of(args : Args) : string {
    let stem = trim_suffix(base_name(args.variant_file), ".json")
    return empty(args.variant_file) ? WORK : path_join(WORK, "variants/{slice(stem, rfind(stem, ".") + 1)}")
}

// the sidecar the conversions take: SIDECAR, or under `--variant` the variant's, written by `main`
def private sidecar_of(args : Args) : string => empty(args.variant_file) ? SIDECAR : path_join(root_of(args), "doom.c2das")

// the variant's sidecar written where `sidecar_of` names it; true without `--variant`, false with
// the refusal logged
def private write_variant_sidecar(args : Args) : bool {
    if (empty(args.variant_file)) {
        return true
    }
    var error : string
    let v <- read_variant(args.variant_file, error)
    if (empty(error) && v.program != "puredoom") {
        error = "{args.variant_file} is a variant of {v.program}, not of puredoom"
    }
    if (empty(error)) {
        variant_sidecar(v, SIDECAR, sidecar_of(args), error)
    }
    if (!empty(error)) {
        to_log(LOG_ERROR, "doom: --variant: {error}\n")
    }
    return empty(error)
}

// the converted program of `layout` run under `tier` on `demo` over `wad` and held to its reference
// log; true when every compared tic is in sync. With `trace` the traced conversion runs, its trace
// lines written to TRACES and held to the native run's as its tic lines are to the reference: a
// missing native trace or a traced desync fails the run too.
def private run_converted_demo(root, layout, tier : string; demo, tics, timeout : int; wad : string; trace : bool) : bool {
    let spec <- DemoSpec(entry = path_join(form_dir(root, layout, form_of(trace, false)), "doom_main.das"), tier = tier, wad = wad, demo = demo, tics = tics, timeout = float(timeout), work = WORK, ref_dirs <- clone_to_move(REF_DIRS), module_dirs <- [for (dir in CONVERTED_MODULES); get_full_file_name(dir)])
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

// `--fps`: the plan of `args` over `demos`, the capture stamped with this tree's commit and this
// machine, timed by `time_demos` into FPS_CAPTURE
def private time_flags(args : Args; tiers : array<string>; demos : array<int>; wad : string) : bool {
    let plan <- FpsPlan(sync_native = NATIVE, sync_entry = path_join(form_dir(root_of(args), args.layout, ""), "doom_main.das"), native = native_path("speed"), entry = path_join(form_dir(root_of(args), args.layout, "speed"), "doom_main.das"), wad = wad, work = WORK, ref_dirs <- clone_to_move(REF_DIRS), module_dirs <- [for (dir in CONVERTED_MODULES); get_full_file_name(dir)], tiers <- clone_to_move(tiers), demos <- clone_to_move(demos), samples = args.samples, timeout = args.timeout, capture_path = empty(args.variant_file) ? FPS_CAPTURE : path_join(root_of(args), "results_linux.json"))
    var clang, daslang : string
    tool_versions(clang, daslang)
    let platform = "{get_platform_name()} {strip(captured(["uname", "-m"]))}"
    var c <- new_capture(git_line(["rev-parse", "--short=12", "HEAD"]), git_line(["status", "--porcelain", "--untracked-files=no"]), fps_command(args.layout, tiers, args.samples, args.demo), cpu_name(), platform, clang, daslang, args.samples)
    return time_demos(plan, c, strip(captured(["date", "-u", "+%Y-%m-%d %H:%M UTC"])))
}

// `--readme`: README's fps section rewritten from FPS_CAPTURE; false, logged, when it is not
def private readme_flag : bool {
    let error = write_fps_readme(FPS_CAPTURE, README)
    if (!empty(error)) {
        to_log(LOG_ERROR, "doom: {error}\n")
    }
    return empty(error)
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
def private convert_doom(root, base, layout, form : string) : bool {
    var error : string
    let c_paths <- stage_program(SOURCES, HOST, path_join(WORK, "src"), UNITS, error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "doom: {error}\n")
        return false
    }
    let sidecar = form_sidecar(root, base, form, error)
    let side <- empty(error) ? read_sidecar(sidecar, error) : Sidecar()
    if (!empty(error)) {
        to_log(LOG_ERROR, "doom: {error}\n")
        return false
    }
    let units_ok = report("unit", convert_units(c_paths, side))
    let res <- convert_program(c_paths, form_dir(root, layout, form), TARGET, "", sidecar, "", "", "main", layout)
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
    if (args.speed && (args.trace || args.run || args.demo != 0)) {
        to_log(LOG_ERROR, "doom: --speed goes with --native, --convert and --compile-check alone; --fps runs the speed builds\n")
        return 1
    }
    let form = form_of(args.trace, args.speed)
    if (!write_variant_sidecar(args)) {
        return 1
    }
    let converted = !args.convert || convert_doom(root_of(args), sidecar_of(args), args.layout, form)
    let compiled = !args.compile_check || report("module", compile_modules(form_dir(root_of(args), args.layout, form), CONVERTED_MODULES, 600.0))
    let wad = empty(args.wad) ? FREEDOOM2 : args.wad
    let native_failed = (args.fetch_check && !fetch_check()) || (args.native && !build_native(form)) || (args.demo != 0 && !args.run && !run_demo(args.demo, wad, args.trace))
    let tiers <- [for (tier in split(args.tiers, ",")); strip(tier)]
    let refusal = fps_refusal(args.fps, args.run, tiers, args.samples, args.tics, args.trace)
    if (!empty(refusal)) {
        to_log(LOG_ERROR, "doom: {refusal}\n")
        return 1
    }
    let played = !args.run || (args.fps ? time_flags(args, tiers, fps_demos(args.demo), wad) : run_converted_demo(root_of(args), args.layout, args.tier, args.demo == 0 ? 1 : args.demo, args.tics, args.timeout, wad, args.trace))
    let failed = !converted || !compiled || native_failed || !played || (args.readme && !readme_flag())
    return failed ? 1 : 0
}
