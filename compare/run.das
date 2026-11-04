options gen2
// `--perf` converts in this process: the pipeline parses clang's JSON dump below its own frames,
// and a deep expression tree overflows the default 16 KB context stack
options stack = 1048576

require strings
require daslib/strings_boost
require daslib/clargs
require daslib/fio
require daslib/json_boost
require ../converter/pipeline.das
require ../converter/sidecar.das
require ../suites/suite_runner.das
require rust_translator
require suite_compare
require perf_compare
require quality_compare
require lua_compare
require compare_render
require projects
require ../perf/boxes.das
require ../perf/perf_lanes.das
require ../perf/perf_cli.das
require ../lua/sources.das

//! The head-to-head with the Rust translator from the repository root: `--suites` runs it over
//! the three suites' inputs and writes the `suites` section of `compare/results_linux.json`,
//! `--perf` times the perf kernels through both translators and writes its `perf` section
//! (`compare/ARCHITECTURE.md`); `--quality` counts and sizes both sides' output over the inputs
//! both translated and writes its `quality` section; `--lua` runs the Rust translator over Lua and
//! writes the `lua` and `doom` sections, over the C files and the sidecar of the folder
//! `--lua-from` names when it is set; `--project` runs one real project of the Rust checkout and
//! writes its entry of the `projects` section; `--readme` and `--report` render the capture as
//! markdown.

//! the README `--readme` rewrites and the rulings `--report` opens with, from the repository root
let README = "README.md"
let RULINGS = "docs/rulings-pending.md"

[CommandLineArgs]
struct CompareArgs {
    @clarg_doc = "run the Rust translator over all three suites"
    suites : bool
    @clarg_doc = "run it over one suite: c_testsuite, gcc_torture or csmith"
    suite : string = ""
    @clarg_doc = "time the perf kernels through both translators under every lane"
    perf : bool
    @clarg_doc = "count and size both translators' output over the inputs both translated"
    quality : bool
    @clarg_doc = "translate Lua with the Rust translator and list the C library functions it lacks"
    lua : bool
    @clarg_doc = "--lua over the .c files of this folder (its lua.c holding main) with its lua.c2das, when present, as the sidecar, into <folder>/work, instead of Lua's release"
    lua_from : string = ""
    @clarg_doc = "run one real project of the Rust checkout's tests/manual through both translators: wasm3, binjgb, h264bsd-mp4, plmpeg-stream, doomgeneric or quakegeneric"
    project : string = ""
    @clarg_doc = "the GiB of address space each measured run of --project may map (default 6); 0 for no cap"
    @clarg_name = "as"
    address_space : int = 6
    @clarg_doc = "the folder --project writes its work into, one subfolder per project (default compare/work/projects)"
    work : string = ""
    @clarg_doc = "rewrite the comparison rendered from the capture between the compare markers of README.md"
    readme : bool
    @clarg_doc = "write the comparison rendered from the capture into this markdown file, the open rulings first"
    report : string = ""
    @clarg_doc = "samples per perf lane, each its own process (default 5); 0 with --project times no bench"
    samples : int = 5
    @clarg_doc = "run only the ids (perf: the kernels) that contain this text; a filtered run writes no capture"
    filter : string = ""
    @clarg_doc = "cases judged at once, one worker process each"
    jobs : int = 4
    @clarg_doc = "the capture a run writes (default compare/results_linux.json)"
    out : string = ""
    @clarg_doc = "the box the run measures on, bench, PC or fx (default: the box of the CPU model, none for another CPU)"
    box : string = ""
    @clarg_doc = "log the reason of every case that does not pass"
    verbose : bool
    @clarg_doc = "worker: judge this case, <suite>/<id>, writing compare/work/<suite>/<id>/verdict"
    one : string = ""
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

// the worker of `--one`: 0 once the verdict is written, 2 for an argument naming no case; an
// argument `quality/<key>` measures that key of the quality comparison
def run_worker(text : string) : int {
    if (text |> starts_with("quality/")) {
        measure_key(slice(text, length("quality/")), rust_binary(), QUALITY_WORK)
        return 0
    }
    var suite, id : string
    let specs <- compare_suites()
    let found = split_worker_id(text, suite, id) ? find_index_if(specs, $(s) => s.name == suite) : -1
    if (found < 0) {
        to_log(LOG_ERROR, "--one takes <suite>/<id> of c_testsuite, gcc_torture or csmith, not `{text}`\n")
        return 2
    }
    judge_case(specs[found], id, rust_binary())
    return 0
}

// one suite through the workers, its summary logged; its capture entry
def run_suite(spec : SuiteSpec; args : CompareArgs) : SuiteCapture {
    let started = ref_time_ticks()
    let ratchet <- read_ratchet(spec.expected_pass, spec.skip_ledger)
    var outcomes <- drive_suite(spec, suite_ids(spec, ratchet, args.filter), ratchet, args.jobs)
    for (o in outcomes) {
        if (args.verbose && o.status != "pass") {
            to_log(LOG_INFO, "{spec.name}/{o.id} ({o.tag}): {o.status}: {o.reason}\n")
        }
    }
    var c <- suite_capture(ratchet, outcomes, seconds_since(started), run_stamps(rust_binary(), args.box))
    let counts = join([for (s in STATUSES); "{s} {c.rust?[s] ?? 0}"], ", ")
    to_log(LOG_INFO, "{spec.name}: rust {counts} of {c.ids} (ours {c.ours_pass}, skipped {c.ours_skipped}; rust passes of ours {c.rust_pass_of_ours}, of skipped {c.rust_pass_of_skipped}, of unlisted {c.rust_pass_of_unlisted})\n")
    return <- c
}

// the perf comparison over the kernels `--filter` names, the geometric means logged; the capture's
// `perf` section written
def run_perf(args : CompareArgs) : int {
    if (samples_refused(args.samples, 1)) {
        return 1
    }
    var reason : string
    if (!rust_available(reason)) {
        to_log(LOG_ERROR, "{reason}\n")
        return 2
    }
    let bin = rust_binary()
    var entries : table<string; JsonValue?>
    for (k in perf_kernels(args.filter)) {
        var entry = compare_kernel(k, bin, args.samples)
        to_log(LOG_INFO, "{kernel_line(k.key, entry)}\n")
        entries[k.key] = entry
    }
    var section = perf_section(run_stamps(bin, args.box), args.samples, entries)
    for (line in geomean_lines(section)) {
        to_log(LOG_INFO, "{line}\n")
    }
    return record_run(empty(args.out) ? CAPTURE : args.out, args.filter) $(path) => write_capture_section(path, "perf", section)
}

// the quality comparison over the corpus the capture `out` and the ratchets name, `--filter`
// narrowing it, `--jobs` workers at a time; its `quality` section written
def run_quality(args : CompareArgs; out : string) : int {
    var reason : string
    if (!rust_available(reason)) {
        to_log(LOG_ERROR, "{reason}\n")
        return 2
    }
    var error : string
    let corpus <- quality_corpus_of(out, args.filter, error)
    if (!empty(error)) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    let missing = quality_missing(corpus, compare_suites())
    if (!empty(missing)) {
        to_log(LOG_ERROR, "{missing}\n")
        return 2
    }
    var entries <- drive_quality(corpus, args.jobs)
    var section = quality_section(run_stamps(rust_binary(), args.box), entries)
    for (g, totals in keys(section?["totals"] as _object), values(section?["totals"] as _object)) {
        to_log(LOG_INFO, "{g}: {totals?["counted"] ?? 0} of {totals?["keys"] ?? 0} keys counted; lines ours {totals?["ours"]?["lines"] ?? 0}, rust {totals?["rust"]?["lines"] ?? 0}, of them its runtime {totals?["rust"]?["runtime_lines"] ?? 0}\n")
    }
    return record_run(out, args.filter) $(path) => write_capture_section(path, "quality", section)
}

// the Lua comparison over Lua's release, or the C files of `from` when it is set: its `lua` and
// `doom` sections written
def run_lua(out, from, box : string) : int {
    let missing = empty(from) ? lua_missing(SOURCES, false) : lua_missing(from, true)
    if (!empty(missing)) {
        to_log(LOG_ERROR, "{missing}\n")
        return 2
    }
    let bin = rust_binary()
    var error : string
    let c_paths <- empty(from) ? program_sources("lua") : folder_sources(from)
    var section = lua_section(bin, c_paths, empty(from) ? SIDECAR : folder_sidecar(from), empty(from) ? LUA_WORK : folder_work(from), run_stamps(bin, box), error)
    if (section == null) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    to_log(LOG_INFO, "{lua_line(section)}\n")
    return record_run(out, "") $(path) {
        let written = write_capture_section(path, "lua", section)
        return empty(written) ? write_capture_section(path, "doom", doom_section()) : written
    }
}

// true, the refusal logged, when `samples` is below `least`
def private samples_refused(samples, least : int) : bool {
    if (samples >= least) {
        return false
    }
    to_log(LOG_ERROR, "--samples takes a count of at least {least}, not {samples}\n")
    return true
}

// the real project `--project` names through both translators, its result lines logged; its
// entry of the capture's `projects` section written
def run_project(args : CompareArgs; out : string) : int {
    // 0 samples: the run times no bench
    if (samples_refused(args.samples, 0)) {
        return 1
    }
    if (args.address_space < 0) {
        to_log(LOG_ERROR, "--as takes a count of GiB of at least 0, not {args.address_space}\n")
        return 1
    }
    var reason : string
    if (!rust_available(reason)) {
        to_log(LOG_ERROR, "{reason}\n")
        return 2
    }
    let checkout = rust_checkout()
    var p : Project
    if (!find_project(checkout, args.project, p)) {
        to_log(LOG_ERROR, "--project takes one of {join([for (row in project_table(checkout)); row.name], ", ")}, not `{args.project}`\n")
        return 1
    }
    if (!fexist(project_path(p, p.tu))) {
        to_log(LOG_ERROR, "no {project_path(p, p.tu)}: the Rust checkout {checkout} lacks the project\n")
        return 2
    }
    let expected_error = load_expected(p)
    if (!empty(expected_error)) {
        to_log(LOG_ERROR, "{expected_error}\n")
        return 2
    }
    let bin = rust_binary()
    var entry = project_entry(p, bin, path_join(empty(args.work) ? PROJECTS_WORK : args.work, p.name), args.samples, run_stamps(bin, args.box), int64(args.address_space) * 1073741824l)
    for (line in project_lines(p.name, entry)) {
        to_log(LOG_INFO, "{line}\n")
    }
    return record_run(out, args.filter) $(path) => write_project(path, p.name, entry)
}

// the open lines of `docs/rulings-pending.md`, under their heading; "" without the file or a line
def private rulings_pending : string {
    let lines <- [for (line in split(fexist(RULINGS) ? fread(RULINGS) : "", "\n")); line; where line |> starts_with("- ")]
    return empty(lines) ? "" : "## Rulings pending\n\n" + join(lines, "\n") + "\n\n"
}

// the comparison rendered from the capture `out`: into README.md between its compare markers under
// `--readme`, into the file `--report` names under its heading
def run_render(args : CompareArgs; out : string) : int {
    var error : string
    let results = read_json_file(out, error)
    if (results == null) {
        to_log(LOG_ERROR, "{error}\n")
        return 1
    }
    let body = compare_report(results)
    if (args.readme && !update_readme(README, body, COMPARE_BEGIN, COMPARE_END)) {
        to_log(LOG_ERROR, "{README} has no compare markers\n")
        return 1
    }
    if (!empty(args.report)) {
        fwrite(args.report, "# c2das-re against the Rust translator\n\n{rulings_pending()}## Head-to-head\n\n{body}")
    }
    return 0
}

[export]
def main : int {
    var args = CompareArgs()
    let parsed = cli_prologue(args, "compare")
    if (parsed >= 0) {
        return parsed
    }
    if (!empty(args.one)) {
        return run_worker(args.one)
    }
    let alone <- [for (mode in [("--perf", args.perf), ("--quality", args.quality), ("--lua", args.lua), ("--project", !empty(args.project)), ("--readme or --report", args.readme || !empty(args.report))]); mode._0; where mode._1]
    if (length(alone) > 1 || (length(alone) == 1 && (args.suites || !empty(args.suite)))) {
        to_log(LOG_ERROR, "{alone[0]} runs alone: run the suites and each of --perf, --quality, --lua, --project and the rendering in a run of its own\n")
        return 1
    }
    if (args.lua && !empty(args.filter)) {
        to_log(LOG_ERROR, "--lua takes no --filter: it translates the whole program\n")
        return 1
    }
    let refusal = box_refusal(args.box, cpu_name())
    if (!empty(refusal)) {
        to_log(LOG_ERROR, "{refusal}\n")
        return 1
    }
    let out = empty(args.out) ? CAPTURE : args.out
    if (args.readme || !empty(args.report)) {
        return run_render(args, out)
    }
    if (args.quality) {
        return run_quality(args, out)
    }
    if (args.lua) {
        return run_lua(out, args.lua_from, args.box)
    }
    if (!empty(args.project)) {
        return run_project(args, out)
    }
    if (args.perf) {
        return run_perf(args)
    }
    let all <- compare_suites()
    let specs <- [for (s in all); s; where args.suites || s.name == args.suite]
    if (empty(specs)) {
        to_log(LOG_ERROR, "name what to run: --suites, --suite c_testsuite, gcc_torture or csmith, --perf, --quality or --lua\n")
        return 1
    }
    let missing = missing_inputs(specs)
    if (!empty(missing)) {
        to_log(LOG_ERROR, "{missing}\n")
        return 2
    }
    var entries <- {for (spec in specs); spec.name => JV(run_suite(spec, args))}
    return record_run(empty(args.out) ? CAPTURE : args.out, args.filter, entries)
}
