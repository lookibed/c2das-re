options gen2

module criteria_file public

require strings
require math
require daslib/strings_boost
require daslib/json_boost
require daslib/md_boost
require daslib/functional

//! The criteria capture `metrics/criteria_linux.json` as data (`metrics/ARCHITECTURE_CRITERIA.md`):
//! the criteria and their compliance formulas over the raw counts, the rows they are measured on,
//! the text a run writes, its reader and shape check, and the tables a run and the gate print.

//! The raw counts an input records, sorted; `metrics/ARCHITECTURE_CRITERIA.md` defines each.
let RAW_KEYS <- ["addr_deref_sites", "bool_roundtrip_sites", "c_char_literals", "c_code_lines", "c_comment_lines", "c_constant_uses", "c_includes", "c_renames_sites", "c_repeated_lines", "c_strings", "c_switches", "das_char_literals", "das_code_lines", "das_comment_lines", "das_comments_carried", "das_constant_names", "das_repeated_lines", "das_requires", "das_string_reinterprets", "discarded_temps", "flag_lines", "flag_switches", "fn_addr_deref", "fn_bool_roundtrip", "fn_c_renames", "fn_label_stubs", "fn_literal_arithmetic", "fn_lost_parens", "fn_matched", "fn_median_x100", "fn_qualified_calls", "fn_reinterpret_casts", "fn_stray_braces", "fn_temporaries", "fn_within", "fn_worst_x100", "goto_state_lines", "label_stubs_sites", "layout_check_lines", "literal_arithmetic_sites", "long_lines", "lost_parens_sites", "modules", "modules_late_bound", "modules_layout_check", "modules_long_lines", "qualified_calls_sites", "reinterpret_casts_sites", "self_assignments", "setjmp_loops", "setjmp_sites", "stray_braces_sites", "temporaries_sites"]

//! One input's raw counts by name, and the das-to-C line ratio of each matched function, x100.
struct CriteriaRaw {
    counts : table<string; int>
    ratios : array<int>
}

//! The criteria in the critic's order of findings.
let CRITERIA <- ["comments", "constant_names", "char_literals", "macro_blowup", "repeated_blocks", "switch_flags", "temporaries", "addr_deref", "reinterpret_casts", "late_binding", "qualified_calls", "require_lines", "setjmp", "layout_checks", "stray_braces", "label_stubs", "string_literals", "lost_parens", "literal_arithmetic", "bool_roundtrip", "c_renames", "long_lines"]

//! The rows of the capture: each Lua program in each layout, then each ratchet suite.
let ROWS <- ["lua/lua", "lua/lua@scc", "lua/lua@single", "lua/luac", "lua/luac@scc", "lua/luac@single", "c_testsuite", "csmith", "gcc_torture"]

//! The c-testsuite inputs the gate re-measures against the capture's `sample`: a switch with
//! character literals and comments, defines, a plain switch.
let SAMPLE_KEYS <- ["c_testsuite/00085", "c_testsuite/00181", "c_testsuite/00182", "c_testsuite/00215"]

//! The column of the mean over the rows.
let ALL = "all"

//! A compliance a criterion has no measure of: its denominator is zero.
let NOT_APPLICABLE = -1.0lf

//! The row an input key counts in: a Lua key is its own row, a suite key its suite's.
def row_of(key : string) : string => key |> starts_with("lua/") || find(key, "/") < 0 ? key : slice(key, 0, find(key, "/"))

def private raw(counts : table<string; int>; key : string) : double => double(counts?[key] ?? 0)

// the share `part / whole`, capped at the whole, as a percentage; not applicable on no whole
def private share(part, whole : double) : double => whole <= 0.0lf ? NOT_APPLICABLE : 100.0lf * min(part, whole) / whole

// the share of `whole` free of `bad`
def private clean_share(bad, whole : double) : double => whole <= 0.0lf ? NOT_APPLICABLE : 100.0lf * (1.0lf - min(bad, whole) / whole)

let private FUNCTION_SHARE <- {"temporaries" => "fn_temporaries", "addr_deref" => "fn_addr_deref", "reinterpret_casts" => "fn_reinterpret_casts", "qualified_calls" => "fn_qualified_calls", "stray_braces" => "fn_stray_braces", "label_stubs" => "fn_label_stubs", "lost_parens" => "fn_lost_parens", "literal_arithmetic" => "fn_literal_arithmetic", "bool_roundtrip" => "fn_bool_roundtrip", "c_renames" => "fn_c_renames"}

let private MODULE_SHARE <- {"late_binding" => "modules_late_bound", "layout_checks" => "modules_layout_check", "long_lines" => "modules_long_lines"}

//! One criterion's compliance percentage over a row's raw counts, `NOT_APPLICABLE` when its
//! denominator is zero.
[arch(at="ARCHITECTURE_CRITERIA.md#criteria")]
def compliance(criterion : string; c : table<string; int>) : double {
    if (key_exists(FUNCTION_SHARE, criterion)) {
        return clean_share(raw(c, FUNCTION_SHARE?[criterion] ?? ""), raw(c, "fn_matched"))
    } elif (key_exists(MODULE_SHARE, criterion)) {
        return clean_share(raw(c, MODULE_SHARE?[criterion] ?? ""), raw(c, "modules"))
    } elif (criterion == "comments") {
        return share(raw(c, "das_comments_carried"), raw(c, "c_comment_lines"))
    } elif (criterion == "constant_names") {
        return share(raw(c, "das_constant_names"), raw(c, "c_constant_uses"))
    } elif (criterion == "char_literals") {
        return share(raw(c, "das_char_literals"), raw(c, "c_char_literals"))
    } elif (criterion == "macro_blowup") {
        return share(raw(c, "fn_within"), raw(c, "fn_matched"))
    } elif (criterion == "repeated_blocks") {
        let das_lines = raw(c, "das_code_lines")
        let c_lines = raw(c, "c_code_lines")
        if (das_lines <= 0.0lf || c_lines <= 0.0lf) {
            return NOT_APPLICABLE
        }
        let c_unique = 1.0lf - raw(c, "c_repeated_lines") / c_lines
        let das_unique = 1.0lf - raw(c, "das_repeated_lines") / das_lines
        return c_unique <= 0.0lf ? 100.0lf : 100.0lf * min(das_unique / c_unique, 1.0lf)
    } elif (criterion == "switch_flags") {
        return clean_share(raw(c, "flag_switches"), max(raw(c, "c_switches"), raw(c, "flag_switches")))
    } elif (criterion == "require_lines") {
        return share(raw(c, "c_includes"), raw(c, "das_requires"))
    } elif (criterion == "setjmp") {
        return clean_share(raw(c, "setjmp_loops"), raw(c, "setjmp_sites"))
    } elif (criterion == "string_literals") {
        return clean_share(raw(c, "das_string_reinterprets"), max(raw(c, "c_strings"), raw(c, "das_string_reinterprets")))
    }
    return NOT_APPLICABLE
}

//! The unweighted mean of the applicable values, `NOT_APPLICABLE` when none is.
def mean_applicable(values : array<double>) : double {
    var sum = 0.0lf
    var n = 0
    for (v in values) {
        if (v >= 0.0lf) {
            sum += v
            n++
        }
    }
    return n == 0 ? NOT_APPLICABLE : sum / double(n)
}

//! One capture: the raw counts per row, and the raw counts of the sample inputs the gate
//! re-measures.
struct CriteriaCapture {
    rows : table<string; table<string; int>>
    sample : table<string; table<string; int>>
}

//! The compliance of every criterion per row, and the `all` column: each criterion's mean over the
//! rows where it applies.
[arch(at="ARCHITECTURE_CRITERIA.md#rows")]
def compliance_table(cap : CriteriaCapture) : table<string; table<string; double>> {
    var out : table<string; table<string; double>>
    for (row in ROWS) {
        cap.rows |> get(row) $(c) {
            out[row] <- {for (cr in CRITERIA); cr => compliance(cr, c)}
        }
    }
    var all <- {for (cr in CRITERIA); cr => mean_applicable([for (row in keys(out)); out?[row]?[cr] ?? NOT_APPLICABLE])}
    out[ALL] <- all
    return <- out
}

//! A column's total: the unweighted mean of its applicable criteria.
def column_total(column : table<string; double>) : double => mean_applicable([for (cr in CRITERIA); column?[cr] ?? NOT_APPLICABLE])

//! A percentage as the capture and the tables spell it: one decimal, `null` when not applicable.
def percent_text(v : double) : string => v < 0.0lf ? "null" : fmt(":.1f", v)

def private object_text(entries : array<tuple<key : string; text : string>>; one_line : bool) : string {
    if (empty(entries)) {
        return "\{\}"
    }
    if (one_line) {
        return "\{" + join([for (e in entries); "\"{e.key}\": {e.text}"], ", ") + "\}"
    }
    return "\{\n" + join([for (e in entries); "    \"{e.key}\": {e.text}"], ",\n") + "\n  \}"
}

def private raw_lines(rows : table<string; table<string; int>>; order : array<string>) : string {
    var entries : array<tuple<key : string; text : string>>
    for (k in order) {
        rows |> get(k) $(c) {
            entries |> push((key = k, text = object_text([for (r in RAW_KEYS); (key = r, text = "{c?[r] ?? 0}")], true)))
        }
    }
    return object_text(entries, false)
}

//! The capture as the committed file spells it: `compliance` (per column, each criterion's
//! percentage), `raw` (per row, its raw counts), `sample` (per sample input key, its raw counts) and
//! `totals` (per column), keys in a fixed order, one row per line.
def criteria_text(cap : CriteriaCapture) : string {
    let table_ <- compliance_table(cap)
    var columns <- [for (row in ROWS); row; where key_exists(table_, row)]
    columns |> push(ALL)
    var compliance_entries, total_entries : array<tuple<key : string; text : string>>
    for (col in columns) {
        table_ |> get(col) $(column) {
            compliance_entries |> push((key = col, text = object_text([for (cr in CRITERIA); (key = cr, text = percent_text(column?[cr] ?? NOT_APPLICABLE))], true)))
            total_entries |> push((key = col, text = percent_text(column_total(column))))
        }
    }
    let sample_keys <- sorted([for (k in keys(cap.sample)); k])
    return "\{\n  \"compliance\": {object_text(compliance_entries, false)},\n  \"raw\": {raw_lines(cap.rows, ROWS)},\n  \"sample\": {raw_lines(cap.sample, sample_keys)},\n  \"totals\": {object_text(total_entries, false)}\n\}\n"
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

def private int_rows(js : JsonValue?) : table<string; table<string; int>> {
    var out : table<string; table<string; int>>
    if (js != null && js is _object) {
        for (k, v in keys(js as _object), values(js as _object)) {
            out[k] <- int_fields(v)
        }
    }
    return <- out
}

//! The capture `text` holds; `error` names what is not JSON.
def read_criteria(text : string; var error : string&) : CriteriaCapture {
    var cap : CriteriaCapture
    let js = read_json(text, error)
    if (js != null) {
        cap.rows <- int_rows(js?["raw"])
        cap.sample <- int_rows(js?["sample"])
    }
    return <- cap
}

// a finding per row of `obj` outside `allowed` (none when `allowed` is empty), per raw key missing
// or unknown, and per value that is not a non-negative integer
def private check_raw(path : string; obj : JsonValue?; allowed : array<string>; var findings : array<string>) {
    if (obj == null || !(obj is _object)) {
        findings |> push("{path} is not an object")
        return
    }
    for (row, counts in keys(obj as _object), values(obj as _object)) {
        if (!empty(allowed) && !has_value(allowed, row)) {
            findings |> push("{path} has the unknown row `{row}`")
        } elif (counts == null || !(counts is _object)) {
            findings |> push("{path}.{row} is not an object")
        } else {
            for (k, v in keys(counts as _object), values(counts as _object)) {
                if (!has_value(RAW_KEYS, k)) {
                    findings |> push("{path}.{row} has the unknown key `{k}`")
                } elif (v == null || !(v is _longint) || (v as _longint) < 0l) {
                    findings |> push("{path}.{row}.{k} is not a non-negative integer")
                }
            }
            for (k in RAW_KEYS) {
                if (!key_exists(counts, k)) {
                    findings |> push("{path}.{row} lacks `{k}`")
                }
            }
        }
    }
}

//! The findings of the capture's shape: the four top-level keys, every row a known one with every
//! raw count a non-negative integer, and the text the writer's own spelling of its raw counts,
//! which makes every percentage and total the formulas' value.
def check_criteria(text : string) : array<string> {
    var findings : array<string>
    var error : string
    let js = read_json(text, error)
    if (js == null || !(js is _object)) {
        findings |> push("not a JSON object: {error}")
        return <- findings
    }
    for (k in keys(js as _object)) {
        if (!has_value(["compliance", "raw", "sample", "totals"], k)) {
            findings |> push("the unknown top-level key `{k}`")
        }
    }
    check_raw("raw", js?["raw"], ROWS, findings)
    check_raw("sample", js?["sample"], array<string>(), findings)
    if (empty(findings)) {
        var read_error : string
        if (criteria_text(read_criteria(text, read_error)) != text) {
            findings |> push("the text is not the writer's spelling of its raw counts: a percentage or total is not its formula's value, or the keys or indent differ")
        }
    }
    return <- findings
}

def private cell(v : double) : string => v < 0.0lf ? "n/a" : fmt(":.1f", v)

def private criterion_cells(cr : string; columns : array<string>; table_ : table<string; table<string; double>>) : array<string> {
    var line <- [cr]
    line |> push_from([for (col in columns); cell(table_?[col]?[cr] ?? NOT_APPLICABLE)])
    return <- line
}

//! The criteria table: a row per criterion, a column per measured row and the `all` column, the
//! totals last.
def render_criteria(cap : CriteriaCapture) : string {
    let table_ <- compliance_table(cap)
    var columns <- [for (row in ROWS); row; where key_exists(table_, row)]
    columns |> push(ALL)
    var rows <- [for (cr in CRITERIA); criterion_cells(cr, columns, table_)]
    var total_line <- ["**total**"]
    total_line |> push_from([for (col in columns); "**{cell(column_total(table_?[col] ?? default<table<string; double>>))}**"])
    rows |> emplace(total_line)
    var header <- ["Criterion"]
    header |> push_from(columns)
    var align <- [ColAlign.left]
    align |> push_from([for (_col in columns); ColAlign.right])
    return render_md_table(header, align, rows)
}

def private signed(v : double) : string => v > 0.0lf ? "+{fmt(":.1f", v)}" : fmt(":.1f", v)

def private delta_cells(cr : string; b, a : double) : array<string> => <- [cr, cell(b), cell(a), b < 0.0lf || a < 0.0lf ? "n/a" : signed(a - b)]

//! The delta table over the `all` column: per criterion `base`'s percentage, this capture's and the
//! signed difference, the total last; a criterion not applicable on either side shows `n/a`.
def render_delta(base, now : CriteriaCapture) : string {
    let before <- compliance_table(base)
    let after <- compliance_table(now)
    var rows <- [for (cr in CRITERIA); delta_cells(cr, before?[ALL]?[cr] ?? NOT_APPLICABLE, after?[ALL]?[cr] ?? NOT_APPLICABLE)]
    let bt = column_total(before?[ALL] ?? default<table<string; double>>)
    let at = column_total(after?[ALL] ?? default<table<string; double>>)
    rows |> emplace(["**total**", "**{cell(bt)}**", "**{cell(at)}**", bt < 0.0lf || at < 0.0lf ? "n/a" : "**{signed(at - bt)}**"])
    return render_md_table(["Criterion", "main", "now", "delta"], [ColAlign.left, ColAlign.right, ColAlign.right, ColAlign.right], rows)
}

//! The raw counts of `rows` summed key by key, the median and worst ratios excepted: those are
//! `ratios`' (pooled per-function ratios, sorted) median and maximum.
def sum_raw(rows : array<table<string; int>>; ratios : array<int>) : table<string; int> {
    var out <- {for (k in RAW_KEYS); k => 0}
    for (r in rows) {
        for (k in RAW_KEYS) {
            out[k] += r?[k] ?? 0
        }
    }
    out["fn_median_x100"] = empty(ratios) ? 0 : ratios[length(ratios) / 2]
    out["fn_worst_x100"] = empty(ratios) ? 0 : ratios[length(ratios) - 1]
    return <- out
}

//! The worker file: `ok`, a `<raw key> <count>` line per raw key, and `ratios` with the
//! per-function ratios; or `error <first line>`.
def result_text(raw : CriteriaRaw; error : string) : string {
    if (!empty(error)) {
        return "error {replace(error, "\n", " ")}\n"
    }
    let counts = join([for (k in RAW_KEYS); "{k} {raw.counts?[k] ?? 0}"], "\n")
    let ratios = join([for (r in raw.ratios); "{r}"], " ")
    return "ok\n{counts}\nratios {ratios}\n"
}

//! A worker file read back; `error` holds its error, or `no result` when it has no status line.
def read_result_text(text : string; var error : string&) : CriteriaRaw {
    var raw : CriteriaRaw
    let lines <- split(text, "\n")
    if (empty(lines) || lines[0] != "ok") {
        error = !empty(lines) && lines[0] |> starts_with("error ") ? slice(lines[0], length("error ")) : "no result"
        return <- raw
    }
    for (ln in lines) {
        var inscope words <- split(ln, " ")
        if (length(words) == 2 && has_value(RAW_KEYS, words[0])) {
            raw.counts[words[0]] = to_int(words[1])
        } elif (words[0] == "ratios") {
            raw.ratios <- [for (w in words); to_int(w); where w != "ratios" && !empty(w)]
        }
    }
    return <- raw
}

//! The gate's verdict on the sample: a line per sample key that failed to measure (`failed` holds
//! its error), one per key whose fresh raw counts differ from the capture's, naming the keys that
//! differ, or the line that all match; nothing is red.
def sample_freshness(committed : CriteriaCapture; fresh : table<string; table<string; int>>; failed : table<string; string>) : array<string> {
    var lines : array<string>
    for (key in SAMPLE_KEYS) {
        if (key_exists(failed, key)) {
            lines |> push("failed: {key}: {failed?[key] ?? ""}")
            continue
        }
        var inscope differ <- [for (k in RAW_KEYS); k; where(fresh?[key]?[k] ?? -1) != (committed.sample?[key]?[k] ?? -1)]
        if (!empty(differ)) {
            lines |> push("stale: {key} measures differently now ({join(differ, ", ")}): re-record with scripts/run_criteria.sh")
        }
    }
    if (empty(lines)) {
        lines |> push("sample: the {length(SAMPLE_KEYS)} sample inputs measure as metrics/criteria_linux.json records them")
    }
    return <- lines
}

