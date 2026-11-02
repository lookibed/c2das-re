options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack
options stack = 1048576

require strings
require daslib/fio
require daslib/strings_boost
require daslib/clargs
require ../converter/pipeline.das
require ../converter/dumper_a.das
require ../converter/sidecar.das
require ../converter/tiers.das
require sources
require harness
require convert_check

//! The PureDOOM harness: `--fetch-check` checks `doom/fetch.sh`'s tree and wad against the pins,
//! `--native` builds the multi-file form with the patches natively into `doom/work/native/doom`,
//! and `--demo <N> --wad <path>` runs `-timedemo demo<N>` on the native build, writing the
//! reference log `doom/work/ref/<wad>_demo<N>.log`. Run from the repository root.

let WORK = "doom/work"
let NATIVE = "doom/work/native/doom"
let PATCHES <- ["doom/patches/0001-per-tic-checksum.patch"]
let FREEDOOM2 = "doom/fetch/wads/freedoom2.wad"
let NATIVE_FLAGS <- ["-O2", "-w"]
// the address space a demo run gets (3 GiB) and the seconds it may take
let DEMO_MEMORY = "3221225472"
let DEMO_TIMEOUT = 600.0

[CommandLineArgs]
struct Args {
    @clarg_name = "fetch-check"
    @clarg_doc = "check doom/fetch/ against VERSIONS.md: PureDOOM at the pin with the patches applied, freedoom2.wad of the pinned sha256"
    fetch_check : bool
    @clarg_doc = "build the patched multi-file form natively into doom/work/native/doom"
    native : bool
    @clarg_doc = "run -timedemo demo<N> on the native build and write doom/work/ref/<wad>_demo<N>.log"
    demo : int = 0
    @clarg_doc = "the IWAD --demo runs on (default the fetched freedoom2.wad)"
    wad : string = ""
    @clarg_doc = "dump and emit each unit alone, then convert the program in --layout into doom/work/<layout>/, staged in doom/work/src/"
    convert : bool
    @clarg_name = "compile-check"
    @clarg_doc = "compile every module of doom/work/<layout>/ alone with daslang -compile-only"
    compile_check : bool
    @clarg_doc = "the layout --convert and --compile-check take: source, source-cut or single"
    layout : string = "source"
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

// the native build's command line: the pinned clang, the flags, the sidecar's defines
def private native_command(defines : array<string>) : array<string> {
    var argv <- [default_clang()]
    argv |> push_from(NATIVE_FLAGS, [for (define in defines); "-D{define}"], ["-o", NATIVE], program_sources())
    argv |> push("-lm")
    return <- argv
}

// the sidecar's defines, "" in `error` when it reads
def private sidecar_defines(var error : string&) : array<string> {
    let side = read_sidecar(SIDECAR, error)
    return <- clone_to_move(side.defines)
}

// the native build at NATIVE; false with the compiler's text logged when it fails
def private build_native : bool {
    var error : string
    let defines <- sidecar_defines(error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "doom: {error}\n")
        return false
    }
    mkdir_rec(dir_name(NATIVE))
    var output : string
    if (run_and_capture(native_command(defines), output, 600.0) != 0) {
        to_log(LOG_ERROR, "doom: native build failed:\n{output}\n")
        return false
    }
    to_log(LOG_INFO, "doom: {NATIVE}: {int64(stat(NATIVE).size)} bytes\n")
    return true
}

// `-timedemo demo<demo>` on the native build over `wad`, run in `doom/work/run/<stem>/` where
// `doom2.wad` links to it, capped; the reference log written to `doom/work/ref/`
def private run_demo(demo : int; wad : string) : bool {
    let wad_sha = file_sha256(wad)
    if (empty(wad_sha)) {
        to_log(LOG_ERROR, "doom: no wad {wad}\n")
        return false
    }
    if (!stat(NATIVE).is_reg) {
        to_log(LOG_ERROR, "doom: no {NATIVE}; run with --native\n")
        return false
    }
    let stem = base_name(wad) |> replace(".wad", "")
    let dir = path_join(WORK, "run/{stem}")
    mkdir_rec(dir)
    var out : string
    run_and_capture(["ln", "-sfn", get_full_file_name(wad), path_join(dir, "doom2.wad")], out, 30.0)
    let argv <- ["bash", "-c", "cd \"$0\" && DOOMWADDIR=. exec prlimit --as={DEMO_MEMORY} \"$1\" -timedemo \"$2\"", dir, get_full_file_name(NATIVE), "demo{demo}"]
    var output : string
    let rc = run_and_capture(argv, output, DEMO_TIMEOUT)
    var error : string
    let defines <- sidecar_defines(error)
    var clang_version : string
    run_and_capture([default_clang(), "--version"], clang_version, 60.0)
    let versions = fread("VERSIONS.md")
    let build = join([default_clang(), join(NATIVE_FLAGS, " "), join([for (define in defines); "-D{define}"], " ")], " ")
    let header = "PureDOOM {puredoom_pin(versions)} + {join(PATCHES, " ")} (sha256 {file_sha256(PATCHES[0])}); {split(clang_version, "\n")[0]}; build: {build} over sources.das's units and host; wad {base_name(wad)} sha256 {wad_sha}; -timedemo demo{demo}, exit {rc}"
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
def private convert_doom(layout : string) : bool {
    var error : string
    let c_paths <- stage_program(SOURCES, HOST, path_join(WORK, "src"), UNITS, error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "doom: {error}\n")
        return false
    }
    let side <- read_sidecar(SIDECAR, error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "doom: {error}\n")
        return false
    }
    let units_ok = report("unit", convert_units(c_paths, side))
    let res <- convert_program(c_paths, path_join(WORK, layout), TARGET, "", SIDECAR, "", "", "main", layout)
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
    if (!is_layout(args.layout)) {
        to_log(LOG_ERROR, "doom: --layout is source, source-cut or single, not `{args.layout}`\n")
        return 1
    }
    let converted = !args.convert || convert_doom(args.layout)
    let compiled = !args.compile_check || report("module", compile_modules(path_join(WORK, args.layout), CONVERTED_MODULES, 600.0))
    let failed = !converted || !compiled || (args.fetch_check && !fetch_check()) || (args.native && !build_native()) || (args.demo != 0 && !run_demo(args.demo, empty(args.wad) ? FREEDOOM2 : args.wad))
    return failed ? 1 : 0
}
