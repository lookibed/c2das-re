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
require ../suites/csmith/generate.das
require ../converter/pipeline.das
require readability_inputs
require criteria_file
require conversion_census_count

//! The conversions census (`metrics/ARCHITECTURE_CONVERSIONS.md`): every cast node of the C-IR of
//! the programs the project converts and of the suites' passing tests, by castKind, operand and
//! result class, context, rule and chain. A program converts through `convert_input` in a worker
//! of its own, one at a time, and the worker counts every C-IR file the conversion wrote; a
//! suite's passing ids are dumped alone, in `suite_chunks` workers. A worker keeps only its counts.

let WORK = "metrics/work/conversion_census"

// seconds a worker may live before the driver kills it
let WORKER_TIMEOUT = 1500.0

// the workers a suite's ids are split over: a csmith seed's dump is a hundred times a test's, and
// a worker's heap grows with every dump it holds, so csmith's are many
def private suite_chunks(suite : string) : int => suite == "csmith" ? 48 : 8

let SUITE_PREFIX = "suite/"

let CSMITH_ROW = "csmith"

// a row of the report: its name and the inputs whose units it pools, a unit two inputs share (a
// file of both Lua programs) counted once
struct private Row {
    name : string
    keys : array<string>
}

def private suite_row(name, suite : string) : Row => Row(name = name, keys <- [for (k in range(suite_chunks(suite))); "{SUITE_PREFIX}{suite}@{k}"])

def private all_rows : array<Row> {
    return <- [suite_row("c-testsuite", "c_testsuite"), suite_row("gcc-torture", "gcc_torture"), suite_row(CSMITH_ROW, "csmith"),
        Row(name = "Lua 5.4.8", keys <- ["lua/lua", "lua/luac"]),
        Row(name = "PureDOOM", keys <- [PUREDOOM_ROW]),
        Row(name = "binjgb", keys <- ["project/binjgb"]),
        Row(name = "h264bsd-mp4", keys <- ["project/h264bsd-mp4"]),
        Row(name = "plmpeg-stream", keys <- ["project/plmpeg-stream"]),
        Row(name = "wasm3", keys <- ["project/wasm3"]),
        Row(name = "doomgeneric", keys <- ["project/doomgeneric"]),
        Row(name = "quakegeneric", keys <- ["project/quakegeneric"])]
}

[CommandLineArgs]
struct CensusArgs {
    @clarg_doc = "read only the rows whose name contains this text"
    filter : string = ""
    @clarg_doc = "suite workers at once (a program's worker runs alone)"
    jobs : int = 4
    @clarg_doc = "pairs and contexts shown per castKind and form in a row's tables (0: all)"
    limit : int = 12
    @clarg_doc = "also write the raw counts of every row and the total as JSON to this file"
    json : string = ""
    @clarg_doc = "print the tables of this C file, dumped as a suite test is, and exit"
    c : string = ""
    @clarg_doc = "print the tables from the counts the workers already wrote, converting nothing"
    reuse : bool
    @clarg_doc = "worker: count the input with this key into metrics/work/conversion_census/<key>/"
    one : string = ""
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

def private counts_path(key : string) : string => "{WORK}/{key}/counts.tsv"

def private failures_path(key : string) : string => "{WORK}/{key}/failures.tsv"

// every `.cir.json` file under `folder`, sorted
def private cir_files(folder : string) : array<string> {
    var found, folders : array<string>
    dir(folder) $(name) {
        let path = path_join(folder, name)
        if (name != "." && name != ".." && stat(path).is_dir) {
            folders |> push(path)
        } elif (name |> ends_with(".cir.json") && name != "program.cir.json") {
            found |> push(path)
        }
    }
    for (sub in folders) {
        found |> push_from(cir_files(sub))
    }
    sort(found)
    return <- found
}

// the program `key` converted under `folder` and every unit's C-IR counted into `lines`, each
// file removed once read; `failures` takes the conversion's error and each file that does not read
def private read_program(key, folder : string; var lines, failures : array<string>) {
    let conv <- convert_input(key, folder)
    if (!empty(conv.error)) {
        failures |> push("{key}\t{headline(conv.error)}")
    }
    for (path in cir_files(folder)) {
        var error : string
        var c : ConversionCensus
        census_cir_file(path, c, error)
        remove(path)
        if (empty(error)) {
            lines |> push_from(unit_lines(base_name(path), c))
        } else {
            failures |> push("{path}\t{error}")
        }
    }
}

// chunk `chunk` of the suite `suite`: every `suite_chunks`th id its `expected_pass.txt` lists,
// dumped alone into `lines` (a csmith seed generated under `folder` first); `failures` takes each
// id the dumper refuses
def private read_suite(suite : string; chunk : int; folder : string; var lines, failures : array<string>) {
    var inscope r <- read_ratchet("suites/{suite}/expected_pass.txt", "suites/{suite}/skip.txt")
    for (idx, id in count(), r.expected) {
        if (idx % suite_chunks(suite) != chunk) {
            continue
        }
        var error : string
        var c_path = suite == "c_testsuite" ? "{C_TESTSUITE_TESTS}/{id}.c" : "{GCC_TORTURE_TESTS}/{id}.c"
        if (suite == "csmith") {
            let prog = csmith_program(id, folder, CSMITH_TIMEOUT)
            error = prog.timed_out ? "csmith took longer than {int(CSMITH_TIMEOUT)} s" : prog.error
            c_path = prog.c_path
        }
        var c : ConversionCensus
        if (empty(error)) {
            census_c_file(c_path, c, error)
        }
        if (empty(error)) {
            lines |> push_from(unit_lines("{suite}/{id}", c))
        } else {
            failures |> push("{id}\t{headline(error)}")
        }
    }
}

def private run_worker(key : string) {
    var lines, failures : array<string>
    let folder = "{WORK}/{key}"
    if (key |> starts_with(SUITE_PREFIX)) {
        let parts <- split(slice(key, length(SUITE_PREFIX)), "@")
        read_suite(parts[0], to_int(parts[1]), "{folder}/gen", lines, failures)
    } else {
        read_program(key, folder, lines, failures)
    }
    rmdir_rec(folder)
    mkdir_rec(folder)
    fwrite(failures_path(key), join(failures, "\n") + "\n")
    fwrite(counts_path(key), join(lines, "\n") + "\n")
}

// the workers of `keys`, `jobs` at a time; a line per worker that left no counts file into `failed`
def private run_batch(keys : array<string>; jobs : int; var failed : array<string>) {
    run_workers(length(keys), jobs, WORKER_TIMEOUT, $(index) {
        let noenv : array<string>
        remove(counts_path(keys[index]))
        return unsafe(spawn_process(worker_argv("metrics/conversion_census.das", keys[index]), "", noenv))
    }) $(index, killed, rc, output) {
        if (killed || !fexist(counts_path(keys[index]))) {
            failed |> push("{keys[index]}\t" + (killed ? "killed past {int(WORKER_TIMEOUT)} s" : "worker exit {rc}: {headline(strip(output))}"))
        }
    }
}

// the counts the workers of `row` wrote, a unit met twice counted once, and their failure lines
// into `failures`
def private gather(row : Row; var failures : array<string>) : CensusRow {
    var out = CensusRow(name = row.name)
    var seen : table<string>
    for (key in row.keys) {
        out.c |> add_counts_file(seen, fexist(counts_path(key)) ? fread(counts_path(key)) : "")
        for (line in fexist(failures_path(key)) ? split(fread(failures_path(key)), "\n") : array<string>()) {
            if (!empty(line)) {
                failures |> push("{row.name}: {replace(line, "\t", ": ")}")
            }
        }
    }
    return <- out
}

// the keys of the suite rows of `rows` when `suites`, else of the program rows, in order
def private keys_of(rows : array<Row>; suites : bool) : array<string> {
    var out : array<string>
    for (r in rows) {
        if ((r.keys[0] |> starts_with(SUITE_PREFIX)) == suites) {
            out |> push_from(r.keys)
        }
    }
    return <- out
}

// the report of `rows` from the counts their workers wrote, `failed` the workers that left none:
// each row's tables, the total's and, past one row, the total's without csmith, whose generated
// programs hold most of the casts, then what was not read
def private print_report(rows : array<Row>; failed : array<string>; limit : int; json : string) {
    var failures : array<string>
    var read <- [for (r in rows); gather(r, failures)]
    var total = CensusRow(name = "total")
    var but_csmith = CensusRow(name = "total without csmith")
    for (r in read) {
        total.c |> add_census(r.c)
        if (r.name != CSMITH_ROW) {
            but_csmith.c |> add_census(r.c)
        }
    }
    read |> emplace(total)
    if (length(read) > 2) {
        read |> emplace(but_csmith)
    }
    for (r in read) {
        print(render_set(r, limit))
    }
    print("Not read:\n\n")
    for (line in failures) {
        print("- {line}\n")
    }
    for (line in failed) {
        print("- {replace(line, "\t", ": ")}\n")
    }
    if (!empty(json)) {
        fwrite(json, render_json(read))
    }
}

[export]
def main : int {
    var args = CensusArgs()
    let parsed = cli_prologue(args, "conversion_census")
    if (parsed >= 0) {
        return parsed
    }
    if (!empty(args.c)) {
        var row = CensusRow(name = args.c)
        var error : string
        census_c_file(args.c, row.c, error)
        if (!empty(error)) {
            to_log(LOG_ERROR, "{headline(error)}\n")
            return 1
        }
        print(render_set(row, args.limit))
        return 0
    }
    if (!empty(args.one)) {
        run_worker(args.one)
        return 0
    }
    let rows <- [for (r in all_rows()); r; where empty(args.filter) || find(r.name, args.filter) >= 0]
    var failed : array<string>
    if (!args.reuse) {
        run_batch(keys_of(rows, false), 1, failed)
        run_batch(keys_of(rows, true), args.jobs, failed)
    }
    print_report(rows, failed, args.limit, args.json)
    return empty(failed) ? 0 : 1
}
