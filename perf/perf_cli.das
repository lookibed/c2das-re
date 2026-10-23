options gen2

module perf_cli public

require strings
require daslib/fio
require daslib/json_boost
require ../converter/sidecar.das
require perf_tables

//! The file side of the perf harness: the baseline capture a delta compares against, the tables
//! a run prints and reports, the `--check` verdict, and the README sections a run rewrites.

//! The `--baseline` file when given, else `committed` at HEAD; null without error when HEAD has none.
def baseline_capture(path, committed : string; var name : string&; var error : string&) : JsonValue? {
    if (!empty(path)) {
        name = path
        return read_json_file(path, error)
    }
    name = "HEAD:{committed}"
    var text : string
    if (run_and_capture(["git", "show", name], text, 60.0) != 0) {
        return null
    }
    var js = read_json(text, error)
    if (js == null) {
        error = "{name}: {error}"
    }
    return js
}

//! The text a run prints: the report when `report` names a file, which it also writes, else
//! the results, the ratios when asked, and the delta when there is a baseline.
def show_tables(current, baseline : JsonValue?; baseline_name : string; ratios : bool; report : string) : string {
    if (!empty(report)) {
        let text = render_report(current, baseline, baseline_name)
        fwrite(report, text)
        return text
    }
    var text = render_results(current)
    if (ratios) {
        text += "\n" + render_ratios(current)
    }
    if (baseline != null) {
        text += "\n" + render_delta(current, baseline, baseline_name)
    }
    return text
}

//! `--check`: the cells of capture `js` past `tolerance` percent against `baseline`, each an error
//! line; true when none. No baseline is a failure: there is nothing the run reproduces
def check_drift(js, baseline : JsonValue?; baseline_name : string; tolerance : int) : bool {
    if (baseline == null) {
        to_log(LOG_ERROR, "--check: no baseline capture to compare with\n")
        return false
    }
    let drifted <- drifted_cells(js, baseline, int64(tolerance) * 100l)
    for (cell in drifted) {
        to_log(LOG_ERROR, "--check: {cell} against {baseline_name}, past {tolerance}% and twice the cell's spread\n")
    }
    return empty(drifted)
}

//! The markers around the README section of each method.
let README_BEGIN = "<!-- perf-table:begin -->"
let README_END = "<!-- perf-table:end -->"
let README_METHOD_BEGIN = "<!-- perf-method:begin -->"
let README_METHOD_END = "<!-- perf-method:end -->"

//! The README section of capture `js`: the results table of the default method, under the
//! dasProfile method the comparison with dasProfile's own capture at `dasprofile_path`; "" with
//! `error` set when that capture does not read.
def readme_section(js : JsonValue?; method, dasprofile_path : string; var error : string&) : string {
    if (method != "dasprofile") {
        return render_results(js)
    }
    let dp = read_json_file(dasprofile_path, error)
    return dp == null ? "" : render_method_comparison(js, dp)
}

//! The text between `begin` and `end` in file `path` replaced by `rendered`; false without the markers.
def update_readme(path, rendered, begin, end : string) : bool {
    let text = fread(path)
    let b = find(text, begin)
    let e = find(text, end)
    if (b < 0 || e < 0 || e < b) {
        return false
    }
    fwrite(path, slice(text, 0, b + length(begin)) + "\n" + rendered + slice(text, e))
    return true
}

//! `--readme`: the method's section of `readme` rewritten from capture `js`, the comparison reading
//! dasProfile's capture at `dasprofile_path`; "" when done, else the error.
def write_readme(readme, dasprofile_path : string; js : JsonValue?; method : string) : string {
    var error : string
    let section = readme_section(js, method, dasprofile_path, error)
    let by_dasprofile = method == "dasprofile"
    if (empty(section)) {
        return error
    }
    if (!update_readme(readme, section, by_dasprofile ? README_METHOD_BEGIN : README_BEGIN, by_dasprofile ? README_METHOD_END : README_END)) {
        return "{readme} has no {by_dasprofile ? "perf-method" : "perf-table"} markers"
    }
    return ""
}
