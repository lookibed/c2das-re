options gen2

module readability_file public

require strings
require daslib/strings_boost
require daslib/json_boost
require daslib/md_boost
require daslib/functional
require ../suites/suite_files.das

//! The readability capture `metrics/readability_linux.json` as data: the metric and input
//! names, the text a run writes (keys sorted, two-space indent, one module per line), the shape
//! check `metrics/REVIEW.das` runs over the committed file, and the totals table a run prints.

//! the metrics, sorted, each a count of sites in one emitted module (metrics/ARCHITECTURE.md)
let METRICS <- ["c_function", "goto", "label", "literal_named", "pointer_arith", "pointer_index", "reinterpret", "unsafe_block", "unsafe_expr", "while_rangeable"]

//! the input groups, sorted; an input key is `<group>/<id>`
let INPUT_GROUPS <- ["c_testsuite", "csmith", "gcc_torture", "perf"]

//! One capture: the input count per group and the counts per input key.
struct Capture {
    inputs : table<string; int>
    modules : table<string; table<string; int>>
}

//! The group of an input key, the text before its first slash.
def group_of(key : string) : string => text_before(key, "/")

//! Every metric summed over `modules`, a metric no module has counted as zero.
def totals_of(modules : table<string; table<string; int>>) : table<string; int> {
    var totals <- {for (m in METRICS); m => 0}
    for (counts in values(modules)) {
        for (m in METRICS) {
            totals[m] += (counts?[m] ?? 0)
        }
    }
    return <- totals
}

// a JSON object of `entries` in their order: on one line, or one entry per line at the second
// level of the capture's two-space indent
def private object_text(entries : array<tuple<key : string; text : string>>; one_line : bool) : string {
    if (empty(entries)) {
        return "\{\}"
    }
    if (one_line) {
        return "\{" + join([for (e in entries); "\"{e.key}\": {e.text}"], ", ") + "\}"
    }
    return "\{\n" + join([for (e in entries); "    \"{e.key}\": {e.text}"], ",\n") + "\n  \}"
}

def private count_entries(counts : table<string; int>; names : array<string>) : array<tuple<key : string; text : string>> => <- [for (m in names); (key = m, text = "{counts?[m] ?? 0}")]

//! The capture as the committed file spells it: top-level keys sorted, two-space indent, the
//! totals summed from the modules, one line per module.
def capture_text(cap : Capture) : string {
    var modules : array<tuple<key : string; text : string>>
    for (k in sorted([for (key in keys(cap.modules)); key])) {
        cap.modules |> get(k) $(counts) {
            modules |> push((key = k, text = object_text(count_entries(counts, METRICS), true)))
        }
    }
    let inputs = object_text(count_entries(cap.inputs, INPUT_GROUPS), false)
    let totals = object_text(count_entries(totals_of(cap.modules), METRICS), false)
    return "\{\n  \"inputs\": {inputs},\n  \"modules\": {object_text(modules, false)},\n  \"totals\": {totals}\n\}\n"
}

def private int_fields(js : JsonValue?) : table<string; int> {
    var out : table<string; int>
    if (js != null && js is _object) {
        for (k, v in keys(js as _object), values(js as _object)) {
            out[k] = int(v ?? 0l)
        }
    }
    return <- out
}

//! The capture `text` holds; `error` names what is not JSON.
def read_capture(text : string; var error : string&) : Capture {
    var cap : Capture
    let js = read_json(text, error)
    if (js == null) {
        return <- cap
    }
    cap.inputs <- int_fields(js?["inputs"])
    let modules = js?["modules"]
    if (modules != null && modules is _object) {
        for (k, v in keys(modules as _object), values(modules as _object)) {
            cap.modules[k] <- int_fields(v)
        }
    }
    return <- cap
}

// a finding per key of `obj` outside `names`, per name missing, and per value that is not a
// non-negative integer
def private check_counts(path : string; obj : JsonValue?; names : array<string>; var findings : array<string>) {
    if (obj == null || !(obj is _object)) {
        findings |> push("{path} is not an object")
        return
    }
    for (k, v in keys(obj as _object), values(obj as _object)) {
        if (!(names |> has_value(k))) {
            findings |> push("{path} has the unknown key `{k}`")
        } elif (v == null || !(v is _longint) || (v as _longint) < 0l) {
            findings |> push("{path}.{k} is not a non-negative integer")
        }
    }
    for (name in names) {
        if (!key_exists(obj, name)) {
            findings |> push("{path} lacks `{name}`")
        }
    }
}

def private check_sums(js : JsonValue?; var findings : array<string>) {
    var cap : Capture
    var per_group <- {for (g in INPUT_GROUPS); g => 0}
    for (k, v in keys(js?["modules"] as _object), values(js?["modules"] as _object)) {
        cap.modules[k] <- int_fields(v)
        if (key_exists(per_group, group_of(k))) {
            per_group[group_of(k)]++
        } else {
            findings |> push("modules: `{k}` names no input group")
        }
    }
    let totals <- totals_of(cap.modules)
    for (m in METRICS) {
        let stated = int(js?["totals"]?[m] ?? 0l)
        if (stated != (totals?[m] ?? 0)) {
            findings |> push("totals.{m} is {stated}, the modules sum to {totals?[m] ?? 0}")
        }
    }
    for (g in INPUT_GROUPS) {
        let stated = int(js?["inputs"]?[g] ?? 0l)
        if (stated != (per_group?[g] ?? 0)) {
            findings |> push("inputs.{g} is {stated}, the modules hold {per_group?[g] ?? 0}")
        }
    }
}

//! The findings of the capture's shape: the three top-level keys, every input group and metric
//! present as a non-negative integer, the totals the sum over the modules, each input count the
//! number of its group's modules, and the text the writer's own spelling of it (keys sorted,
//! two-space indent, one module per line).
def check_capture(text : string) : array<string> {
    var findings : array<string>
    var error : string
    let js = read_json(text, error)
    if (js == null || !(js is _object)) {
        findings |> push("not a JSON object: {error}")
        return <- findings
    }
    for (k in keys(js as _object)) {
        if (k != "inputs" && k != "modules" && k != "totals") {
            findings |> push("the unknown top-level key `{k}`")
        }
    }
    check_counts("inputs", js?["inputs"], INPUT_GROUPS, findings)
    check_counts("totals", js?["totals"], METRICS, findings)
    let modules = js?["modules"]
    if (modules == null || !(modules is _object)) {
        findings |> push("modules is not an object")
        return <- findings
    }
    for (k, v in keys(modules as _object), values(modules as _object)) {
        check_counts("modules.{k}", v, METRICS, findings)
    }
    if (empty(findings)) {
        check_sums(js, findings)
    }
    if (empty(findings)) {
        var read_error : string
        if (capture_text(read_capture(text, read_error)) != text) {
            findings |> push("the text is not the writer's spelling of itself: keys sorted, two-space indent, one module per line")
        }
    }
    return <- findings
}

//! The findings of a capture whose input keys are not `expected`: a key no ratchet lists, and a
//! listed key the capture lacks.
def check_input_keys(text : string; expected : array<string>) : array<string> {
    var error : string
    let cap <- read_capture(text, error)
    var findings <- [for (k in sorted([for (key in keys(cap.modules)); key])); "`{k}` is in the capture, but no ratchet lists it"; where !(expected |> has_value(k))]
    for (k in expected) {
        if (!key_exists(cap.modules, k)) {
            findings |> push("`{k}` is listed, but the capture lacks it: re-record with scripts/run_readability.sh --update")
        }
    }
    return <- findings
}

//! The committed counts of the modules a run measured, summed: a `--filter` run compares like
//! with like, and a module the committed capture lacks counts from zero.
def committed_totals(committed : Capture; measured : array<string>) : table<string; int> {
    var same : table<string; table<string; int>>
    for (k in measured) {
        committed.modules |> get(k) $(counts) {
            same[k] := counts
        }
    }
    return <- totals_of(same)
}

//! Why an asked `--update` is not honoured, empty when it is or was not asked: a `--filter` run
//! and a run with a failed input never record.
def update_refusal(update, filtered, failed : bool) : string {
    if (!update) {
        return ""
    }
    return failed ? "a run with a failed input never records" : filtered ? "a --filter run never records" : ""
}

//! A run's exit code: 1 when an input failed, an asked `--update` was refused, or without
//! `--update` a total went up or a recorded input is no longer listed (`ratcheted`); 0 otherwise.
def run_exit_code(failed, refused, ratcheted, update : bool) : int => failed || refused || (ratcheted && !update) ? 1 : 0

//! The metrics whose total in `now` is above `committed`'s.
def raised_metrics(committed, now : table<string; int>) : array<string> => <- [for (m in METRICS); m; where(now?[m] ?? 0) > (committed?[m] ?? 0)]

//! The totals table: metric, the committed total, this run's and the signed difference.
def render_totals(committed, now : table<string; int>) : string {
    var rows : array<array<string>>
    rows |> reserve(length(METRICS))
    for (m in METRICS) {
        let committed_total = committed?[m] ?? 0
        let now_total = now?[m] ?? 0
        let delta = now_total - committed_total
        rows |> emplace([m, "{committed_total}", "{now_total}", delta > 0 ? "+{delta}" : "{delta}"])
    }
    return render_md_table(["Metric", "Committed", "Now", "Delta"], [ColAlign.left, ColAlign.right, ColAlign.right, ColAlign.right], rows)
}
