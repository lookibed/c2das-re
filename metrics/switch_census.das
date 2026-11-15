options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack
options stack = 1048576

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require ../suites/suite_runner.das
require ../suites/suite_files.das
require ../converter/pipeline.das
require ../converter/cir.das
require readability_inputs
require criteria_file
require switch_census_count

//! The switch census (`metrics/ARCHITECTURE_SWITCH.md`): every `switch` of the C programs the
//! project converts, read from their C-IR and never from the emitted das. A program converts
//! through `convert_input`, as the readability metrics convert it, one worker process at a time,
//! and the worker reads every C-IR file the conversion wrote; a suite's files are dumped alone,
//! in `SUITE_CHUNKS` workers. The run prints the class table, the feature tables, the switches
//! that are not `S1` or stand in a hot function, and what was not read.

let WORK = "metrics/work/switch_census"

// seconds a worker may live before the driver kills it
let WORKER_TIMEOUT = 1500.0

// the workers a suite's files are split over, so that no process holds every dump
let SUITE_CHUNKS = 8

let SUITE_PREFIX = "suite/"

// a row of the tables: its name, the inputs whose switches it pools, and the functions that a
// profile of the program under `perf/profiles/` lists in its ten rows with 1% or more of the lane
// (doomgeneric has none and takes PureDOOM's names; wasm3 and quakegeneric have none)
struct private Row {
    name : string
    keys : array<string>
    hot : array<string>
}

let private DOOM_HOT <- ["R_DrawColumn", "R_DrawSpan", "R_MakeSpans", "R_RenderSegLoop", "R_MapPlane", "FixedMul", "W_CheckNumForName", "R_DrawPlanes", "R_DrawVisSprite", "W_CacheLumpNum", "R_StoreWallRange", "R_AddLine", "R_Subsector", "P_GroupLines", "R_FindPlane"]

def private program_rows : array<Row> {
    return <- [Row(name = "Lua (lua + luac)", keys <- ["lua/lua", "lua/luac"], hot <- ["luaV_execute", "luaD_precall", "luaH_getshortstr", "math_sqrt", "lua_tonumberx", "prepCallInfo", "forprep"]),
        Row(name = "PureDOOM", keys <- [PUREDOOM_ROW], hot := DOOM_HOT),
        Row(name = "doomgeneric", keys <- ["project/doomgeneric"], hot := DOOM_HOT),
        Row(name = "quakegeneric", keys <- ["project/quakegeneric"]),
        Row(name = "binjgb", keys <- ["project/binjgb"], hot <- ["ppu_mode3_synchronize", "main", "execute_instruction", "ppu_synchronize", "apu_synchronize", "write_audio_frame", "emulator_run_until", "mode3_tick_count", "do_ppu_mode2", "apu_update_channels"]),
        Row(name = "wasm3", keys <- ["project/wasm3"]),
        Row(name = "h264bsd-mp4", keys <- ["project/h264bsd-mp4"], hot <- ["h264mp4_frames_next", "h264bsdFilterPicture", "h264bsdDecodeResidualBlockCavlc", "FilterVerLumaEdge", "h264bsdInterPrediction", "FilterHorLumaEdge", "h264bsdInterpolateHorVerQuarter", "h264bsdWriteOutputBlocks", "h264bsdInterpolateVerQuarter", "h264bsdFillBlock", "FilterLuma", "FilterHorLuma", "GetBoundaryStrengths", "h264bsdInterpolateChromaHorVer"]),
        Row(name = "plmpeg-stream", keys <- ["project/plmpeg-stream"], hot <- ["plmpeg_frames_next", "plm_frame_to_rgb", "plm_video_decode_block", "plm_video_process_macroblock", "plm_video_idct", "plm_video_decode_macroblock"])]
}

def private suite_rows : array<Row> {
    return <- [Row(name = "c-testsuite", keys <- [for (k in range(SUITE_CHUNKS)); "{SUITE_PREFIX}c_testsuite@{k}"]),
        Row(name = "gcc-torture", keys <- [for (k in range(SUITE_CHUNKS)); "{SUITE_PREFIX}gcc_torture@{k}"])]
}

[CommandLineArgs]
struct CensusArgs {
    @clarg_doc = "read only the rows whose name contains this text"
    filter : string = ""
    @clarg_doc = "suite workers at once (a program's worker runs alone)"
    jobs : int = 4
    @clarg_doc = "print the rows of this C file, dumped with no sidecar, and exit"
    c : string = ""
    @clarg_doc = "print the tables from the rows the workers already wrote, converting nothing"
    reuse : bool
    @clarg_doc = "worker: read the input with this key, writing its rows and failures under metrics/work/switch_census/<key>/"
    one : string = ""
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

def private rows_path(key : string) : string => "{WORK}/{key}/rows.tsv"

def private failures_path(key : string) : string => "{WORK}/{key}/failures.tsv"

// every `.cir.json` file under `folder`, sorted
def private cir_files(folder : string) : array<string> {
    var found, folders : array<string>
    dir(folder) $(name) {
        let path = path_join(folder, name)
        if (name != "." && name != ".." && stat(path).is_dir) {
            folders |> push(path)
        } elif (name |> ends_with(".cir.json")) {
            found |> push(path)
        }
    }
    for (sub in folders) {
        found |> push_from(cir_files(sub))
    }
    sort(found)
    return <- found
}

// the program `key` converted under `folder` and every C-IR file the conversion wrote read into
// `lines`; `failures` takes the conversion's error and each file that does not read back
def private read_program(key, folder : string; var lines, failures : array<string>) {
    let conv <- convert_input(key, folder)
    if (!empty(conv.error)) {
        failures |> push("{key}\t{headline(conv.error)}")
    }
    for (path in cir_files(folder)) {
        var error : string
        var tu <- read_cir(fread(path), error)
        if (empty(error)) {
            lines |> push_from([for (f in census_tu(tu)); facts_line(f)])
        } else {
            failures |> push("{path}\t{error}")
        }
        delete_tu(tu)
    }
}

// chunk `chunk` of the suite `suite`: every `SUITE_CHUNKS`th `.c` file of its tests dumped alone
// into `lines`; `failures` takes each file the dumper refuses, with `switch` after the id when
// its text holds the word
def private read_suite(suite : string; chunk : int; var lines, failures : array<string>) {
    let tests = suite == "c_testsuite" ? C_TESTSUITE_TESTS : GCC_TORTURE_TESTS
    for (idx, id in count(), c_file_ids(tests, "")) {
        if (idx % SUITE_CHUNKS != chunk) {
            continue
        }
        var error : string
        let path = "{tests}/{id}.c"
        lines |> push_from([for (f in census_c_file(path, error)); facts_line(f)])
        lines |> push("file\t{id}")
        if (!empty(error)) {
            failures |> push("{id}\t{find(fread(path), "switch") >= 0 ? "switch" : "-"}\t{headline(error)}")
        }
    }
}

def private run_worker(key : string) {
    var lines, failures : array<string>
    let folder = "{WORK}/{key}"
    if (key |> starts_with(SUITE_PREFIX)) {
        let parts <- split(slice(key, length(SUITE_PREFIX)), "@")
        mkdir_rec(folder)
        read_suite(parts[0], to_int(parts[1]), lines, failures)
    } else {
        read_program(key, folder, lines, failures)
        mkdir_rec(folder)
    }
    fwrite(failures_path(key), join(failures, "\n") + "\n")
    fwrite(rows_path(key), join(lines, "\n") + "\n")
}

// the workers of `keys`, `jobs` at a time; a line per worker that left no rows file into `failed`
def private run_batch(keys : array<string>; jobs : int; var failed : array<string>) {
    run_workers(length(keys), jobs, WORKER_TIMEOUT, $(index) {
        let noenv : array<string>
        remove(rows_path(keys[index]))
        return unsafe(spawn_process(worker_argv("metrics/switch_census.das", keys[index]), "", noenv))
    }) $(index, killed, rc, output) {
        if (killed || !fexist(rows_path(keys[index]))) {
            failed |> push("{keys[index]}\t" + (killed ? "killed past {int(WORKER_TIMEOUT)} s" : "worker exit {rc}: {headline(strip(output))}"))
        }
    }
}

// the rows the workers of `row` wrote, and into `failures` and `files` their failure lines and
// the number of files they read
def private gather(row : Row; var failures : array<string>; var files : int&) : ProgramCensus {
    var rows : array<SwitchFacts>
    for (key in row.keys) {
        for (line in fexist(rows_path(key)) ? split(fread(rows_path(key)), "\n") : array<string>()) {
            var ok : bool
            var f <- read_facts_line(line, ok)
            if (ok) {
                rows |> emplace(f)
            } elif (line |> starts_with("file\t")) {
                files++
            }
        }
        for (line in fexist(failures_path(key)) ? split(fread(failures_path(key)), "\n") : array<string>()) {
            if (!empty(line)) {
                failures |> push(line)
            }
        }
    }
    return <- program_census(row.name, rows, row.hot)
}

// the tables of `programs` and `suites` from the rows their workers wrote, then what was not read,
// `failed` the workers that left no rows
def private print_report(programs, suites : array<Row>; failed : array<string>) {
    var program_failures, suite_failures : array<string>
    var files : int
    let read_programs <- [for (r in programs); gather(r, program_failures, files)]
    print("**Switch census**\n\n{render_classes(read_programs, "programs")}\n")
    print("Features, switches with each:\n\n{render_features(read_programs, "programs", false)}\n")
    print("The same over the hot functions' switches:\n\n{render_features(read_programs, "programs", true)}\n")
    for (r in suites) {
        var inscope failures : array<string>
        var suite_files = 0
        var inscope read <- [gather(r, failures, suite_files)]
        let with_switch = length([for (line in failures); line; where find(line, "\tswitch\t") >= 0])
        print("{r.name}: {suite_files} files, {length(failures)} not dumped, {with_switch} of those name `switch`\n\n{render_classes(read, "")}\n{render_features(read, "", false)}\n")
        suite_failures |> push_from(failures)
    }
    for (p in read_programs) {
        print("{p.name}, not S1 or hot:\n\n{render_sites(p)}\n")
    }
    print("Not read:\n\n")
    for (line in program_failures) {
        print("- {replace(line, "\t", ": ")}\n")
    }
    for (line in failed) {
        print("- {replace(line, "\t", ": ")}\n")
    }
    print("- suite files the dumper refuses: {length(suite_failures)}, listed in {WORK}/suite/*/failures.tsv\n")
}

// the keys of `rows`, in order
def private keys_of(rows : array<Row>) : array<string> {
    var out : array<string>
    for (r in rows) {
        out |> push_from(r.keys)
    }
    return <- out
}

[export]
def main : int {
    var args = CensusArgs()
    let parsed = cli_prologue(args, "switch_census")
    if (parsed >= 0) {
        return parsed
    }
    if (!empty(args.c)) {
        var error : string
        for (f in census_c_file(args.c, error)) {
            print("{facts_line(f)}\n")
        }
        if (!empty(error)) {
            to_log(LOG_ERROR, "{headline(error)}\n")
        }
        return empty(error) ? 0 : 1
    }
    if (!empty(args.one)) {
        run_worker(args.one)
        return 0
    }
    let programs <- [for (r in program_rows()); r; where empty(args.filter) || find(r.name, args.filter) >= 0]
    let suites <- [for (r in suite_rows()); r; where empty(args.filter) || find(r.name, args.filter) >= 0]
    var failed : array<string>
    if (!args.reuse) {
        run_batch(keys_of(programs), 1, failed)
        run_batch(keys_of(suites), args.jobs, failed)
    }
    print_report(programs, suites, failed)
    return empty(failed) ? 0 : 1
}
