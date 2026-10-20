options gen2

module perf_cli public

require daslib/fio
require daslib/json_boost
require ../converter/sidecar.das
require perf_tables

//! The file side of the perf harness: whole-file text, the baseline capture a delta compares
//! against, and the tables a run prints and reports.

def fread_text(path : string) : string {
    var text = ""
    fopen(path, "rb") $(f) {
        if (f != null) {
            text = fread(f)
        }
    }
    return text
}

def write_text(path : string; text : string) {
    fopen(path, "wb") $(f) {
        if (f != null) {
            fwrite(f, text)
        }
    }
}

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
        write_text(report, text)
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
