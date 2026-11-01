options gen2
// the pipeline parses clang's JSON dump below its own frames: a deep expression tree overflows
// the default 16 KB context stack, and dastest gives its tests this much
options stack = 1048576

require strings
require daslib/strings_boost
require daslib/fio
require daslib/clargs
require daslib/json_boost
require ../converter/pipeline.das
require ../converter/tiers.das
require ../converter/sidecar.das
require ../suites/suite_files.das
require ../compare/rust_translator.das
require perf_compose
require perf_lanes
require perf_measure
require audit_constructs
require audit_tables

//! The interpreter audit on Lua (P7.0b), P7.0's method one construct at a time: each construct's
//! kernel (`perf/kernels/audit/`) composed by the dasProfile method, built natively (the oracle),
//! converted, and its module timed under the interpreter and the JIT as converted and as the
//! construct's rewrite spells it, the Rust translation's interpreter beside; each construct's
//! sites counted in Lua's hot modules; and the four Lua benchmarks timed whole in the scc and the
//! source layouts. Run from the repository root with both module folders loaded
//! (`perf/ARCHITECTURE_AUDIT.md`).

let AUDIT_WORK = "perf/work/audit"
let AUDIT_RESULTS = "perf/audit_linux.json"
//! the limits of a das lane here: the Rust translation drops a file-scope `volatile`, so a JIT
//! may hoist its kernel out of the budget loop, which then never ends (compare's `COMPARE_LIMITS`)
let AUDIT_SAMPLE_TIMEOUT = 120.0
let RUST_TRANSLATE_TIMEOUT = 600.0
//! the seconds one whole Lua benchmark run may take
let BENCH_TIMEOUT = 900.0

[CommandLineArgs]
struct Args {
    @clarg_doc = "run only the kernels whose name contains this text"
    filter : string = ""
    @clarg_doc = "samples per kernel lane, each its own process (default 5)"
    samples : int = 5
    @clarg_doc = "samples per whole Lua benchmark lane (default 3)"
    bench_samples : int = 3
    @clarg_doc = "leave the whole Lua benchmarks out"
    no_benches : bool
    @clarg_doc = "the folder lua/run.das converts Lua into (default lua/work)"
    lua_work : string = "lua/work"
    @clarg_name = "table"
    @clarg_doc = "render the tables from the stored capture instead of measuring"
    show_table : bool
    @clarg_doc = "the capture a run writes and --table reads (default perf/audit_linux.json)"
    out : string = ""
    @clarg_short = "?"
    @clarg_name = "show-help"
    @clarg_doc = "show this help and exit"
    show_help : bool
}

def private cell_json(cell : Cell) : JsonValue? => JV((time = cell.time, spread = cell.spread, count = cell.count, result = cell.result, samples = JV(cell.samples)))

def private error_json(error : string) : JsonValue? => JV({"error" => JV(error)})

// the cell of `lane` measured over `argv`, or its error
def private lane_json(name, lane : string; argv : array<string>; samples, oracle : int) : JsonValue? {
    var inscope cells : table<string; Cell>
    var errors : array<string>
    measure_lane(cells, errors, name, lane, argv, samples, oracle, AUDIT_SAMPLE_TIMEOUT)
    var entry : JsonValue?
    cells |> get(lane) $(c) {
        entry = cell_json(c)
    }
    return entry != null ? entry : error_json(empty(errors) ? "not measured" : errors[0])
}

// the interpreter and JIT cells of the converted module at `das_path`
def private tier_cells(name, das_path : string; samples, oracle : int) : table<string; JsonValue?> {
    return <- {for (lane, flag in ["interp", "jit"], ["", "-jit"]); lane => lane_json(name, lane, das_lane_command(das_path, flag, CONVERTED_MODULES), samples, oracle)}
}

//! The module at `das_path` rewritten by `c` into `<stem>_<spelling>.das` beside it; the new path,
//! or "" with `error` set.
def rewritten_module(das_path : string; c : Construct; var error : string&) : string {
    let text = invoke(c.rewrite, fread(das_path), error)
    if (empty(text)) {
        return ""
    }
    let path = "{slice(das_path, 0, length(das_path) - length(".das"))}_{replace(c.spelling, "-", "_")}.das"
    fwrite(path, text)
    return path
}

// the Rust translation of `c_path` under the interpreter: refused with the translator's error, or
// its interpreter cell
def private rust_json(c_path, work : string; samples, oracle : int) : JsonValue? {
    var reason : string
    if (!rust_available(reason)) {
        return JV({"status" => JV("absent"), "error" => JV(reason)})
    }
    let t <- translate_file(rust_binary(), c_path, path_join(work, "rust"), array<string>(), [METHOD_NATIVE_DEFINE], RUST_TRANSLATE_TIMEOUT)
    if (!t.ok || empty(t.entry)) {
        return JV({"status" => JV("refused"), "error" => JV(!t.ok ? t.error : "no main in {t.out_dir}")})
    }
    let no_modules : array<string>
    return JV({"status" => JV("ran"), "interp" => lane_json("rust", "interp", das_lane_command(t.entry, "", no_modules), samples, oracle)})
}

//! One kernel measured: the native oracle, the conversion under the interpreter and the JIT, each
//! construct of the kernel's rewrite under both, and the Rust translation's interpreter.
def measure_kernel(name : string; samples : int) : JsonValue? {
    let work = path_join(AUDIT_WORK, name)
    rmdir_rec(work)
    let c_path = write_method_composed(AUDIT_KERNELS, name, work)
    var inscope native_cells : table<string; Cell>
    var errors : array<string>
    var oracle = 0
    if (!measure_native(native_cells, errors, name, c_path, work, [METHOD_NATIVE_DEFINE], samples, oracle)) {
        return JV({"native" => error_json(errors[0])})
    }
    var entry : table<string; JsonValue?>
    entry["native"] = cell_json(native_cells["native"])
    let res <- convert(c_path, work, "linux")
    if (!res.ok) {
        entry["converted"] = error_json("convert: {first_line(res.error)}")
        return JV(entry)
    }
    entry["converted"] = JV(tier_cells(name, res.das_path, samples, oracle))
    for (c in constructs()) {
        if (c.kernel == name) {
            var error : string
            let alt = rewritten_module(res.das_path, c, error)
            entry[c.spelling] = empty(alt) ? error_json(error) : JV(tier_cells("{name}@{c.spelling}", alt, samples, oracle))
        }
    }
    entry["rust"] = rust_json(c_path, work, samples, oracle)
    return JV(entry)
}

// `samples` wall-clock runs of `argv`, each its own process, after one unmeasured run that warms
// the module cache; the median, or `error` when a run fails or prints other than `oracle` (unless
// empty, then the first run's output becomes it)
def private wall_cell(argv : array<string>; samples : int; var oracle : string&; var error : string&) : double {
    var times : array<double>
    for (s in range(samples + 1)) {
        var out : string
        let started = ref_time_ticks()
        let rc = run_and_capture(argv, out, BENCH_TIMEOUT)
        let seconds = double(get_time_nsec(started)) / 1000000000.0lf
        let output = program_output(out)
        if (rc != 0) {
            error = rc == popen_timed_out ? "timed out after {int(BENCH_TIMEOUT)} s" : "exited {rc}: {first_line(output)}"
            return 0.0lf
        }
        if (empty(oracle)) {
            oracle = output
        } elif (output != oracle) {
            error = "printed `{first_line(output)}` where the native build prints `{first_line(oracle)}`"
            return 0.0lf
        }
        if (s > 0) {
            times |> push(seconds)
        }
    }
    return median_of(times)
}

//! The four Lua benchmarks timed whole: the native build, the interpreter over the scc layout and
//! over the source layout, each in seconds or an error.
def measure_benches(lua_work : string; samples : int) : JsonValue? {
    let native = path_join(lua_work, "lua_native")
    var rows : table<string; JsonValue?>
    for (b in BENCHES) {
        let script = "ports/lua/bench/{b.name}.lua"
        var row : table<string; JsonValue?>
        row["arg"] = JV(b.arg)
        var oracle, error : string
        let t = wall_cell([native, script, b.arg], samples, oracle, error)
        row["native"] = empty(error) ? JV(t) : error_json(error)
        for (layout in ["scc", "source"]) {
            let entry = path_join(layout_dir(lua_work, "lua", layout), "lua.das")
            var inscope argv <- daslang_cmd(CONVERTED_MODULES)
            argv |> push_from([entry, "--", script, b.arg])
            var lane_error : string
            let lt = wall_cell(argv, samples, oracle, lane_error)
            row["interp-{layout}"] = empty(lane_error) ? JV(lt) : error_json(lane_error)
        }
        rows[b.name] = JV(row)
    }
    return JV(rows)
}

// the capture of a run: the machine, the versions, the kernels, the sites and the benchmarks
def private measure_all(args : Args) : JsonValue? {
    var kernels : table<string; JsonValue?>
    for (name in c_file_ids(AUDIT_KERNELS, args.filter)) {
        kernels[name] = measure_kernel(name, args.samples)
        to_log(LOG_INFO, "{name}: {write_json(kernels[name])}\n")
    }
    var clang_version, daslang_version, reason : string
    tool_versions(clang_version, daslang_version)
    let rust_commit = rust_available(reason) ? rust_version(rust_binary(), reason) : ""
    var root <- {
        "cpu" => JV(cpu_name()),
        "platform" => JV("{get_platform_name()} {strip(captured(["uname", "-m"]))}"),
        "timestamp" => JV(strip(captured(["date", "-u", "+%Y-%m-%d %H:%M UTC"]))),
        "samples" => JV(args.samples),
        "versions" => JV({"clang" => JV(clang_version), "daslang" => JV(daslang_version)}),
        "rust_commit" => JV(empty(rust_commit) ? reason : rust_commit),
        "kernels" => JV(kernels),
        "sites" => site_counts(layout_dir(args.lua_work, "lua", "scc"))
    }
    if (!args.no_benches) {
        root["benches"] = measure_benches(args.lua_work, args.bench_samples)
    }
    return JV(root)
}

[export]
def main : int {
    var args = Args()
    let parsed = cli_prologue(args, "audit_lua")
    if (parsed >= 0) {
        return parsed
    }
    let out = empty(args.out) ? AUDIT_RESULTS : args.out
    if (args.show_table) {
        var error : string
        let js = read_json_file(out, error)
        if (js == null) {
            to_log(LOG_ERROR, "{error}\n")
            return 1
        }
        print(audit_text(js))
        return 0
    }
    let js = measure_all(args)
    fwrite(out, write_json(js) + "\n")
    print(audit_text(js))
    return 0
}
