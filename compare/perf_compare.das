options gen2

module perf_compare public

require math
require strings
require daslib/strings_boost
require daslib/fio
require daslib/json_boost
require ../converter/tiers.das
require ../converter/pipeline.das
require ../suites/suite_files.das
require ../perf/perf_compose.das
require ../perf/perf_lanes.das
require ../perf/perf_measure.das
require ../perf/perf_tables.das
require rust_translator
require suite_compare

//! The perf kernels through both translators: each kernel composed by the dasProfile method, the
//! native build its oracle, this repository's conversion and the Rust translation each timed under
//! the interpreter, the JIT, `exe` and `aot` in one run, and the geometric mean of each lane's
//! ratio to native over the kernels both sides timed (`compare/ARCHITECTURE.md`).

let PERF_WORK = "compare/work/perf"

//! seconds the Rust translator may take over one kernel
let PERF_TRANSLATE_TIMEOUT = 600.0

//! the limits of both sides' das lanes: a translation that loses the kernel's `volatile` lets the
//! optimizer hoist the kernel out of the budget loop, which then never ends
let COMPARE_LIMITS = LaneLimits(sample = 120.0, build = 300.0)

//! the das lanes, each measured for both sides; the capture lists `native` before them
let DAS_LANES <- ["interp", "jit", "exe", "aot"]

//! One kernel of the comparison: `key` names it in the capture, `name` is its file stem in `dir`.
struct PerfKernel {
    key : string
    name : string
    dir : string
}

//! The kernels of `perf/kernels/` keyed by name, then those of `perf/kernels/dasprofile/` keyed
//! `dasprofile/<name>`, the ones whose key holds a part of the comma-separated `filter`.
[arch(at="ARCHITECTURE_PERF.md#perf")]
def perf_kernels(filter : string) : array<PerfKernel> {
    var all <- [for (name in c_file_ids(KERNELS, "")); PerfKernel(key = name, name = name, dir = KERNELS)]
    all |> push_from([for (name in c_file_ids(METHOD_KERNELS, "")); PerfKernel(key = "dasprofile/{name}", name = name, dir = METHOD_KERNELS)])
    let parts <- [for (part in split(filter, ",")); part; where !empty(part)]
    return <- [for (k in all); k; where empty(parts) || find_index_if(parts, $(part) => k.key |> contains(part)) >= 0]
}

//! Why the capture `path` takes no re-run of `samples` samples under `stamps` and the clang version
//! line `clang`: no such capture or `perf` section, or one whose box, Rust commit, sample count,
//! clang or daslang version is not the re-run's; "" when it takes one.
[arch(at="ARCHITECTURE_PERF.md#perf")]
def rerun_refusal(path : string; stamps : Stamps; samples : int; clang : string) : string {
    var error : string
    var root = fexist(path) ? capture_root(path, error) : null
    let section = root?["perf"]
    if (section == null || !(section.value is _object) || !((section?["kernels"]).value is _object)) {
        return empty(error) ? "no perf section in {path} to re-measure kernels into" : error
    }
    let fields = ["box", "rust_commit", "samples", "clang", "daslang"]
    let had = [section?["box"] ?? "", section?["rust_commit"] ?? "", "{section?["samples"] ?? 0}", section?["versions"]?["clang"] ?? "", section?["versions"]?["daslang"] ?? ""]
    let now = [stamps.box, stamps.rust_commit, "{samples}", clang, stamps.daslang]
    let differ <- [for (field, a, b in fields, had, now); "{field} `{a}` against this run's `{b}`"; where a != b]
    return empty(differ) ? "" : "{path} holds {join(differ, ", ")}: a re-run joins only a capture of its own box, translator, toolchain and samples"
}

//! The capture `path` with the re-measured kernels of `entries` merged into its `perf` section:
//! each entry replacing its kernel's, every other kernel kept as read, `geomean` over them all, and
//! the re-run's date, keys, box, Rust commit and versions appended to `reruns`; "" or why not
//! (`rerun_refusal`).
[arch(at="ARCHITECTURE_PERF.md#perf")]
def merge_perf_rerun(path : string; stamps : Stamps; samples : int; clang : string; var entries : table<string; JsonValue?>) : string {
    let refusal = rerun_refusal(path, stamps, samples, clang)
    if (!empty(refusal)) {
        return refusal
    }
    var error : string
    var root = capture_root(path, error)
    var section = root?["perf"]
    var kernels = section?["kernels"]
    for (key, entry in keys(entries), values(entries)) {
        (kernels.value as _object)[key] = entry
    }
    (section.value as _object)["geomean"] = geomeans(kernels)
    var reruns = section?["reruns"]
    if (reruns == null || !(reruns.value is _array)) {
        var none : array<JsonValue?>
        reruns = JV(none)
    }
    var rerun_keys <- [for (key in keys(entries)); key]
    sort(rerun_keys)
    (reruns.value as _array) |> push(JV({"timestamp" => JV(stamps.date), "kernels" => JV(rerun_keys), "box" => JV(stamps.box), "rust_commit" => JV(stamps.rust_commit), "versions" => JV({"clang" => JV(clang), "daslang" => JV(stamps.daslang)})}))
    (section.value as _object)["reruns"] = reruns
    return write_capture_section(path, "perf", section)
}

//! A cell as the perf capture writes it.
def cell_json(cell : Cell) : JsonValue? => JV((time = cell.time, spread = cell.spread, count = cell.count, result = cell.result, samples = JV(cell.samples)))

//! A cell that does not stand: `{error}`.
def error_json(error : string) : JsonValue? => JV({"error" => JV(error)})

//! The text of the first line of `errors` that starts with `<side>/<lane>: `, else of the first
//! that starts with `<side>/<step>: ` for a step that is no das lane (one every lane stands on, its
//! name kept), else "not measured".
def lane_error(errors : array<string>; side, lane : string) : string {
    let own = "{side}/{lane}: "
    for (e in errors) {
        if (e |> starts_with(own)) {
            return slice(e, length(own))
        }
    }
    let prefix = "{side}/"
    for (e in errors) {
        let step = text_before(slice(e, length(prefix)), ": ")
        if (e |> starts_with(prefix) && !has_value(DAS_LANES, step)) {
            return slice(e, length(prefix))
        }
    }
    return "not measured"
}

//! Each lane of `lanes`: its cell from `cells`, else the error `lane_error` finds under `side`.
[arch(at="ARCHITECTURE_PERF.md#perf")]
def lane_entries(cells : table<string; Cell>; errors : array<string>; side : string; lanes : array<string>) : table<string; JsonValue?> {
    var entries : table<string; JsonValue?>
    for (lane in lanes) {
        var entry : JsonValue?
        cells |> get(lane) $(c) {
            entry = cell_json(c)
        }
        entries[lane] = entry != null ? entry : error_json(lane_error(errors, side, lane))
    }
    return <- entries
}

//! Every das lane of `das_path` against `oracle`, its builds in `work`: the interpreter and the JIT
//! with `module_dirs` loaded, `exe` and `aot` through `measure_tiers`, each under `limits`; the
//! errors under `side`.
[arch(at="ARCHITECTURE_PERF.md#perf")]
def das_lane_entries(side, das_path, work : string; module_dirs : array<string>; samples, oracle : int; limits : LaneLimits) : table<string; JsonValue?> {
    var inscope cells : table<string; Cell>
    var errors : array<string>
    measure_lane(cells, errors, side, "interp", das_lane_command(das_path, "", module_dirs), samples, oracle, limits.sample)
    measure_tiers(cells, errors, side, das_path, work, module_dirs, samples, oracle, limits)
    return <- lane_entries(cells, errors, side, DAS_LANES)
}

//! Every das lane failed with `error`.
def failed_lanes(error : string) : table<string; JsonValue?> {
    return <- {for (lane in DAS_LANES); lane => error_json(error)}
}

//! The Rust side of a kernel: `refused` with the translator's error and no lanes, else `ran` with
//! the lanes of its entry run with no module folder, or `lanes_error` on every lane when it is set.
[arch(at="ARCHITECTURE_PERF.md#perf")]
def rust_entry(t : RustTranslation; work : string; samples, oracle : int; lanes_error : string) : JsonValue? {
    if (!t.ok || empty(t.entry)) {
        let error = !t.ok ? t.error : "the translation defines no main in {t.out_dir}"
        return JV({"status" => JV("refused"), "error" => JV(error)})
    }
    let no_modules : array<string>
    var lanes <- empty(lanes_error) ? das_lane_entries("rust", t.entry, work, no_modules, samples, oracle, COMPARE_LIMITS) : failed_lanes(lanes_error)
    return JV({"status" => JV("ran"), "lanes" => JV(lanes)})
}

// our side of a kernel: the lanes of its conversion into `<work>/ours`, or `no_oracle` on every lane
// when it is set
def private ours_lanes(c_path, work, no_oracle : string; samples, oracle : int) : table<string; JsonValue?> {
    if (!empty(no_oracle)) {
        return <- failed_lanes(no_oracle)
    }
    let ours_work = path_join(work, "ours")
    let res <- convert(c_path, ours_work, "linux")
    if (!res.ok) {
        return <- failed_lanes("convert: {first_line(res.error)}")
    }
    return <- das_lane_entries("ours", res.das_path, ours_work, CONVERTED_MODULES, samples, oracle, COMPARE_LIMITS)
}

//! One kernel compared: composed by the method into `compare/work/perf/<key>/`, its native lane
//! (the oracle), our conversion's lanes and the Rust translation's, translated by `bin`.
[arch(at="ARCHITECTURE_PERF.md#perf")]
def compare_kernel(k : PerfKernel; bin : string; samples : int) : JsonValue? {
    let work = path_join(PERF_WORK, k.key)
    rmdir_rec(work)
    let c_path = write_method_composed(k.dir, k.name, work)
    var inscope native_cells : table<string; Cell>
    var native_errors : array<string>
    var oracle = 0
    let have_oracle = measure_native(native_cells, native_errors, k.name, c_path, work, [METHOD_NATIVE_DEFINE], samples, oracle)
    let no_oracle = have_oracle ? "" : "no native result: {lane_error(native_errors, k.name, "native")}"
    let t <- translate_file(bin, c_path, path_join(work, "rust"), array<string>(), [METHOD_NATIVE_DEFINE], PERF_TRANSLATE_TIMEOUT)
    var entry <- {
        "native" => have_oracle ? cell_json(native_cells["native"]) : error_json(lane_error(native_errors, k.name, "native")),
        "ours" => JV(ours_lanes(c_path, work, no_oracle, samples, oracle)),
        "rust" => rust_entry(t, path_join(work, "rust_run"), samples, oracle, no_oracle)
    }
    return JV(entry)
}

//! The time of a cell, 0 when it does not stand.
def private time_in(cell : JsonValue?) : double => cell?["time"] ?? 0.0lf

//! The geometric mean of `lane`'s time over native for each side, over the kernels of `kernels`
//! where the native and both sides' `lane` cells stand; `count` how many, both means 0 for none.
[arch(at="ARCHITECTURE_PERF.md#perf")]
def lane_geomean(kernels : JsonValue?; lane : string; var ours, rust : double&; var count : int&) {
    var ours_log, rust_log = 0.0lf
    count = 0
    if (kernels != null && kernels.value is _object) {
        for (k in values(kernels.value as _object)) {
            let native = time_in(k?["native"])
            let o = time_in(k?["ours"]?[lane])
            let r = time_in(k?["rust"]?["lanes"]?[lane])
            if (native > 0.0lf && o > 0.0lf && r > 0.0lf) {
                ours_log += log(o / native)
                rust_log += log(r / native)
                count++
            }
        }
    }
    ours = count == 0 ? 0.0lf : exp(ours_log / double(count))
    rust = count == 0 ? 0.0lf : exp(rust_log / double(count))
}

//! The `geomean` of a capture's `kernels`: per das lane `{ours, rust, kernels}`.
[arch(at="ARCHITECTURE_PERF.md#perf")]
def geomeans(kernels : JsonValue?) : JsonValue? {
    var by_lane : table<string; JsonValue?>
    for (lane in DAS_LANES) {
        var ours, rust : double
        var count : int
        lane_geomean(kernels, lane, ours, rust, count)
        by_lane[lane] = JV((ours = ours, rust = rust, kernels = count))
    }
    return JV(by_lane)
}

//! The `perf` section: the run's stamps, the lanes, every kernel's entry and the geometric means.
[arch(at="ARCHITECTURE_PERF.md#perf")]
def perf_section(stamps : Stamps; samples : int; var kernels : table<string; JsonValue?>) : JsonValue? {
    var clang_version, daslang_version : string
    tool_versions(clang_version, daslang_version)
    let kernels_json = JV(kernels)
    var root <- {
        "cpu" => JV(stamps.cpu),
        "box" => JV(stamps.box),
        "platform" => JV("{get_platform_name()} {strip(captured(["uname", "-m"]))}"),
        "versions" => JV({"clang" => JV(clang_version), "daslang" => JV(daslang_version)}),
        "rust_commit" => JV(stamps.rust_commit),
        "rust_commit_error" => JV(stamps.rust_commit_error),
        "samples" => JV(samples),
        "timestamp" => JV(stamps.date),
        "lanes" => JV(METHOD_LANES),
        "kernels" => kernels_json,
        "geomean" => geomeans(kernels_json)
    }
    return JV(root)
}

//! The line a run logs per lane of the geometric means: ours, the Rust side's, and how many kernels.
def geomean_lines(section : JsonValue?) : array<string> => <- [for (lane in DAS_LANES); "{lane}: ours {section?["geomean"]?[lane]?["ours"] ?? 0.0lf:.3f}, rust {section?["geomean"]?[lane]?["rust"] ?? 0.0lf:.3f} times native over {section?["geomean"]?[lane]?["kernels"] ?? 0l} kernels"]

// a cell's time, or `error` when it does not stand
def private cell_word(cell : JsonValue?) : string {
    let t = time_in(cell)
    return t > 0.0lf ? "{t:.6f}s" : "error"
}

//! The line a run logs per kernel: the native time, then each das lane's for ours and the Rust side.
def kernel_line(key : string; entry : JsonValue?) : string {
    let ours = join([for (lane in DAS_LANES); "{lane} {cell_word(entry?["ours"]?[lane])}"], ", ")
    let rust = entry?["rust"]
    let status = rust?["status"] ?? ""
    let rust_text = status == "ran" ? join([for (lane in DAS_LANES); "{lane} {cell_word(rust?["lanes"]?[lane])}"], ", ") : "{status}: {rust?["error"] ?? ""}"
    return "{key}: native {cell_word(entry?["native"])}; ours {ours}; rust {rust_text}"
}
