options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack
options stack = 1048576

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require ../suites/suite_runner.das
require ../converter/pipeline.das
require ../converter/sidecar.das
require ../converter/cir.das
require readability_inputs
require criteria_scan
require criteria_count
require criteria_defines
require criteria_file

//! The readability criteria (`scripts/run_criteria.sh`, `metrics/ARCHITECTURE_CRITERIA.md`): every
//! Lua key and every ratchet suite key of `expected_input_keys` and every compare project of `ROWS`
//! (`project/<name>`), converted by `convert_input` as
//! the readability metric converts it, one worker process per input, its C sources and emitted
//! modules scanned into raw counts, and every hand-written port of `HAND_PORTS` scanned as it is;
//! the rows summed, each criterion's compliance and each density printed, and a
//! complete run recorded in `metrics/criteria_linux.json`. `--report` is the preflight gate.

let CAPTURE = "metrics/criteria_linux.json"
let WORK = "metrics/work"

// seconds a worker may live before the driver kills it: a csmith seed converts in up to a minute
let WORKER_TIMEOUT = 900.0

[CommandLineArgs]
struct CriteriaArgs {
    @clarg_doc = "measure only the inputs whose input key (<group>/<id>) contains this text; nothing is recorded"
    filter : string = ""
    @clarg_doc = "inputs converted at once, one worker process each (the Lua inputs go one at a time)"
    jobs : int = 4
    @clarg_doc = "a criteria capture to print the delta against"
    delta : string = ""
    @clarg_doc = "the preflight gate: print the committed capture, its delta against --delta-ref and the sample's freshness"
    report : bool
    @clarg_doc = "with --report: the git revision whose committed capture the delta is against"
    delta_ref : string = ""
    @clarg_doc = "worker: convert and scan the input with this input key, writing work/<key>/criteria.txt"
    one : string = ""
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

def private result_path(key : string) : string => "{WORK}/{key}/criteria.txt"

// every own header of the program of `c_paths` the units emit a function definition from (a
// single-header library's implementation) scanned into `sources`: C source of the program too
def private header_sources(c_paths, include_dirs : array<string>; units : array<Preprocessed>; var sources : array<CSource>) {
    for (h in own_files(c_paths, include_dirs)) {
        if (!has_value(c_paths, h)) {
            var inscope lines <- emitted_lines(h, units)
            if (!empty(lines)) {
                var header <- scan_c(fread(h), lines)
                if (!empty(header.functions)) {
                    sources |> emplace(header)
                }
            }
        }
    }
}

// the folder of the hand-written port `key`: its environment variable's value, else its default
def private hand_dir(key : string; var error : string&) : string {
    for (port in HAND_PORTS) {
        if (port.row == key) {
            return has_env_variable(port.env) ? get_env_variable(port.env) : port.dir
        }
    }
    error = "no hand-written port {key}"
    return ""
}

//! The raw counts of the hand-written port `key`: every `.das` file of its folder scanned as a
//! module, with no C source and no macro; `error` names a port `HAND_PORTS` lacks or a folder with
//! no `.das` file.
def measure_hand(key : string; var error : string&) : CriteriaRaw {
    let dir = hand_dir(key, error)
    if (!empty(error)) {
        return <- CriteriaRaw()
    }
    var paths : array<string>
    dir(dir) $(name) {
        if (name |> ends_with(".das")) {
            paths |> push(path_join(dir, name))
        }
    }
    sort(paths)
    if (empty(paths)) {
        error = "no .das file under {dir}"
        return <- CriteriaRaw()
    }
    let modules <- [for (path in paths); scan_das(fread(path), file_stem(path), false)]
    let none : table<string; bool>
    return <- count_criteria(array<CSource>(), modules, none, none)
}

//! The raw counts of the input `key`, converted under `dir`; `error` names what failed. A
//! hand-written port is read where it lies.
def measure_input(key, dir : string; var error : string&) : CriteriaRaw {
    if (key |> starts_with(HAND_PREFIX)) {
        return <- measure_hand(key, error)
    }
    let conv <- convert_input(key, dir)
    if (!empty(conv.error)) {
        error = conv.error
        return <- CriteriaRaw()
    }
    var side_error : string
    let side <- empty(conv.sidecar) ? Sidecar() : read_sidecar(conv.sidecar, side_error)
    if (!empty(side_error)) {
        error = side_error
        return <- CriteriaRaw()
    }
    var units : array<Preprocessed>
    var sources : array<CSource>
    units |> reserve(length(conv.c_paths))
    sources |> reserve(length(conv.c_paths))
    for (c in conv.c_paths) {
        units |> emplace(preprocess(c, side.defines, side.include_dirs, side.include_files, error))
        if (!empty(error)) {
            return <- CriteriaRaw()
        }
        sources |> emplace(scan_c(fread(c), units[length(units) - 1].emitted))
    }
    header_sources(conv.c_paths, side.include_dirs, units, sources)
    let constants <- program_constants(conv.c_paths, side.include_dirs, units)
    let macros <- program_function_macros(conv.c_paths, side.include_dirs, units)
    var paths := conv.das_paths
    paths |> push_from(conv.fragments)
    let modules <- [for (path in paths); scan_das(fread(path), file_stem(path), path |> ends_with(".das.inc"))]
    var raw <- count_criteria(sources, modules, constants, macros)
    raw.counts["c_files"] = conv.c_files
    raw.counts["c_files_converted"] = length(conv.c_paths)
    fold_counts(conv.fold_counts, raw.counts)
    return <- raw
}

// what the workers measured: the raw counts, pooled ratios and pooled function lengths per row, the
// sample's raw counts, and a line per input that failed
struct Measured {
    rows : table<string; array<table<string; int>>>
    ratios : table<string; array<int>>
    lengths : table<string; array<int>>
    sample : table<string; table<string; int>>
    failures : array<string>
}

// the worker of `key` spawned, its stale result file removed first
def private spawn_worker(key : string) : process {
    let noenv : array<string>
    remove(result_path(key))
    return unsafe(spawn_process(worker_argv("metrics/criteria.das", key), "", noenv))
}

// `keys` through workers, `jobs` at a time, into `m`
def private run_batch(keys : array<string>; jobs : int; var m : Measured) {
    run_workers(length(keys), jobs, WORKER_TIMEOUT, $(index) => spawn_worker(keys[index])) $(index, killed, rc, output) {
        let key = keys[index]
        var error = killed ? "killed past {int(WORKER_TIMEOUT)} s" : ""
        var raw <- read_result_text(fexist(result_path(key)) ? fread(result_path(key)) : "", error)
        if (!empty(error)) {
            let printed = empty(strip(output)) ? "" : "\n{strip(output)}"
            m.failures |> push("{key}: {error} (worker exit {rc}){printed}")
            return
        }
        let row = row_of(key)
        m.rows[row] |> push_clone(raw.counts)
        m.ratios[row] |> push_from(raw.ratios)
        m.lengths[row] |> push_from(raw.lengths)
        if (has_value(SAMPLE_KEYS, key)) {
            m.sample[key] := raw.counts
        }
    }
}

// the capture of what the workers measured: each row's raw counts summed, its ratios and function
// lengths pooled
def private capture_of(var m : Measured) : CriteriaCapture {
    var cap : CriteriaCapture
    for (row, counts in keys(m.rows), values(m.rows)) {
        var inscope ratios <- clone_to_move(m.ratios?[row] ?? array<int>())
        sort(ratios)
        cap.rows[row] <- sum_raw(counts, ratios, m.lengths?[row] ?? array<int>())
    }
    for (k, v in keys(m.sample), values(m.sample)) {
        cap.sample[k] := v
    }
    return <- cap
}

// the gate: the committed capture's table, its delta against `ref`'s, the sample re-measured
def private report(delta_ref : string) : int {
    var error : string
    let committed <- capture_at(CAPTURE, error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}: run scripts/run_criteria.sh\n")
        return 1
    }
    print("**Readability criteria** ({CAPTURE})\n\n{render_tables(committed)}")
    if (!empty(delta_ref)) {
        var shown : string
        if (run_and_capture(["git", "show", "{delta_ref}:{CAPTURE}"], shown, 60.0) != 0) {
            print("no capture at {delta_ref}: no delta\n")
        } else {
            var base_error : string
            let base <- base_capture_of_text(shown, "{delta_ref}:{CAPTURE}", base_error)
            print(empty(base_error) ? "Delta against {delta_ref}:\n\n{render_deltas(base, committed)}" : "no delta: {base_error}\n")
        }
    }
    if (!fexist(C_TESTSUITE_TESTS)) {
        print("sample: not re-measured, the c-testsuite is not fetched\n")
        return 0
    }
    var fresh : table<string; table<string; int>>
    var failed : table<string; string>
    for (key in SAMPLE_KEYS) {
        var sample_error : string
        let raw <- measure_input(key, "{WORK}/{key}", sample_error)
        if (empty(sample_error)) {
            fresh[key] := raw.counts
        } else {
            failed[key] = headline(sample_error)
        }
    }
    for (line in sample_freshness(committed, fresh, failed)) {
        print("{line}\n")
    }
    return 0
}

// the compliance table, the density table and the length table, each under its heading
def private render_tables(cap : CriteriaCapture) : string => "{render_criteria(cap)}\n\n**Densities** (sites per 1000 das code lines; `programs` pools lua/lua and the projects by their lines)\n\n{render_density(cap)}\n\n**Function lengths**\n\n{render_lengths(cap)}\n"

// the compliance delta and the density delta over the `programs` column
def private render_deltas(base, now : CriteriaCapture) : string => "{render_delta(base, now)}\n\nDensity delta over `programs`:\n\n{render_density_delta(base, now)}\n"

// every input the criteria measure whose key holds `filter`: the readability inputs without the
// `perf` group, then the compare projects and the hand-written ports of `ROWS`
def private input_keys(filter : string) : array<string> {
    var every <- [for (k in expected_input_keys()); k; where !(k |> starts_with("perf/"))]
    every |> push_from([for (row in ROWS); row; where row |> starts_with(PROJECT_PREFIX) || row |> starts_with(HAND_PREFIX)])
    return <- [for (k in every); k; where empty(filter) || find(k, filter) >= 0]
}

[export]
def main : int {
    var args = CriteriaArgs()
    let parsed = cli_prologue(args, "run_criteria")
    if (parsed >= 0) {
        return parsed
    }
    if (!empty(args.one)) {
        var error : string
        let raw <- measure_input(args.one, "{WORK}/{args.one}", error)
        mkdir_rec(dir_name(result_path(args.one)))
        fwrite(result_path(args.one), result_text(raw, empty(error) ? "" : headline(error)))
        return 0
    }
    if (args.report) {
        return report(args.delta_ref)
    }
    let keys <- input_keys(args.filter)
    var m : Measured
    // a Lua program or a compare project takes up to 3 GB to convert: one at a time
    let one_by_one <- [for (k in keys); k; where k |> starts_with("lua/") || k |> starts_with(PROJECT_PREFIX)]
    run_batch(one_by_one, 1, m)
    run_batch([for (k in keys); k; where !has_value(one_by_one, k)], args.jobs, m)
    let cap <- capture_of(m)
    print("**Readability criteria**\n\n{length(keys)} inputs attempted, {length(m.failures)} failed\n\n{render_tables(cap)}")
    if (!empty(args.delta)) {
        var error : string
        let base <- fexist(args.delta) ? base_capture_of_text(fread(args.delta), args.delta, error) : capture_at(args.delta, error)
        print(empty(error) ? "Delta against {args.delta}:\n\n{render_deltas(base, cap)}" : "no delta: {error}\n")
    }
    m.failures |> sort()
    for (f in m.failures) {
        to_log(LOG_ERROR, "{f}\n")
    }
    if (!empty(args.filter) || !empty(m.failures)) {
        let why = empty(args.filter) ? "a run with a failed input" : "a --filter run"
        to_log(LOG_ERROR, "not recorded: {why} never records\n")
        return empty(m.failures) ? 0 : 1
    }
    fwrite(CAPTURE, criteria_text(cap))
    to_log(LOG_INFO, "recorded {CAPTURE}\n")
    return 0
}
