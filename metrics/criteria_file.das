options gen2

module criteria_file public

require strings
require math
require daslib/strings_boost
require daslib/json_boost
require daslib/fio
require daslib/md_boost
require daslib/functional

//! The criteria capture `metrics/criteria_linux.json` as data (`metrics/ARCHITECTURE_CRITERIA.md`):
//! the criteria and their compliance formulas over the raw counts, the densities per thousand
//! lines and their pooled total over the programs, the rows they are measured on, the text a run
//! writes, its reader and shape check, the capture read from its file, and the tables a run and
//! the gate print.

//! The raw counts an input records, sorted; `metrics/ARCHITECTURE_CRITERIA.md` defines each.
let RAW_KEYS <- ["addr_deref_sites", "addr_sites", "blowup_lines", "bool_roundtrip_sites", "c_char_literals", "c_code_lines", "c_comment_lines", "c_constant_uses", "c_files", "c_files_converted", "c_includes", "c_macro_calls", "c_renames_sites", "c_repeated_lines", "c_strings", "c_switches", "cast_sites", "das_char_literals", "das_code_lines", "das_comment_lines", "das_comments_carried", "das_constant_names", "das_macro_calls", "das_repeated_lines", "das_requires", "das_string_reinterprets", "deref_sites", "discarded_temps", "flag_lines", "flag_switches", "fn_addr_deref", "fn_bool_roundtrip", "fn_c_renames", "fn_label_stubs", "fn_lines_max", "fn_lines_median", "fn_lines_p90", "fn_literal_arithmetic", "fn_long", "fn_lost_parens", "fn_matched", "fn_median_x100", "fn_p90_x100", "fn_qualified_calls", "fn_reinterpret_casts", "fn_stray_braces", "fn_temporaries", "fn_total", "fn_within", "fn_worst_x100", "goto_state_lines", "label_stubs_sites", "layout_check_lines", "literal_arithmetic_sites", "literal_cast_lines", "long_lines", "lost_parens_sites", "macro_faulting", "macro_folded", "macro_sites", "modules", "modules_late_bound", "modules_layout_check", "modules_long_lines", "qualified_calls_sites", "reinterpret_casts_sites", "self_assignments", "setjmp_loops", "setjmp_sites", "stray_braces_sites", "temp_name_sites", "temporaries_sites"]

//! One input's raw counts by name, the das-to-C line ratio of each matched function, x100, and the
//! body code lines of each das function of the program's own.
struct CriteriaRaw {
    counts : table<string; int>
    ratios : array<int>
    lengths : array<int>
}

//! A das function of more code lines than this is a long function.
let LONG_FUNCTION = 100

//! The value at the `p` percent point of `sorted` (its median at 50, its maximum at 100), 0 when empty.
def percentile(sorted : array<int>; p : int) : int => empty(sorted) ? 0 : sorted[min(length(sorted) * p / 100, length(sorted) - 1)]

//! The distributions into `c`: of the matched functions' das-to-C ratios x100, `ratios` sorted, the
//! median, the 90th percentile and the worst; of the das functions' body code lines `lengths`, how
//! many, the median, the 90th percentile, the longest and the ones past `LONG_FUNCTION`.
def distribution_counts(ratios, lengths : array<int>; var c : table<string; int>) {
    c["fn_median_x100"] = percentile(ratios, 50)
    c["fn_p90_x100"] = percentile(ratios, 90)
    c["fn_worst_x100"] = percentile(ratios, 100)
    var inscope sorted := lengths
    sort(sorted)
    c["fn_total"] = length(sorted)
    c["fn_lines_median"] = percentile(sorted, 50)
    c["fn_lines_p90"] = percentile(sorted, 90)
    c["fn_lines_max"] = percentile(sorted, 100)
    c["fn_long"] = length([for (n in sorted); n; where n > LONG_FUNCTION])
}

//! The criteria in the critic's order of findings.
let CRITERIA <- ["comments", "constant_names", "char_literals", "macro_blowup", "repeated_blocks", "switch_flags", "temporaries", "addr_deref", "reinterpret_casts", "late_binding", "qualified_calls", "require_lines", "setjmp", "layout_checks", "stray_braces", "label_stubs", "string_literals", "lost_parens", "literal_arithmetic", "bool_roundtrip", "c_renames", "long_lines"]

//! The prefix of a compare project's input key and row, `project/<name>`.
let PROJECT_PREFIX = "project/"

//! The prefix of a hand-written port's input key and row, `hand/<name>`: das a human wrote, the
//! base the densities are read beside.
let HAND_PREFIX = "hand/"

//! The hand-written ports: the row, the environment variable naming its folder of `.das` files, and
//! the folder when the variable is unset.
let HAND_PORTS <- [(row = "hand/plmpeg-stream", env = "C2DAS_HAND_PLMPEG", dir = "/root/plmpeg-stream/src")]

//! The rows of the capture: each Lua program in each layout and under each opt-in, each ratchet
//! suite, each compare project of `compare/projects.das`'s `project_table`, in its order, then each
//! hand-written port.
let ROWS <- ["lua/lua", "lua/lua@source-cut", "lua/lua@single", "lua/lua@inline", "lua/lua@goto", "lua/lua@checks-off", "lua/lua@past-end-inline", "lua/lua@fn-macros-expand", "lua/luac", "lua/luac@source-cut", "lua/luac@single", "lua/luac@inline", "lua/luac@goto", "lua/luac@checks-off", "lua/luac@past-end-inline", "lua/luac@fn-macros-expand", "c_testsuite", "csmith", "gcc_torture", "project/wasm3", "project/binjgb", "project/h264bsd-mp4", "project/plmpeg-stream", "project/doomgeneric", "project/quakegeneric", "hand/plmpeg-stream"]

//! The Lua program row the densities' `programs` column pools: the published program in the
//! default layout; `luac` shares its files and the other layouts and opt-ins its functions.
let LUA_PROGRAM_ROW = "lua/lua"

//! The suffixes of a Lua row in a layout other than the default (`source`): the same functions
//! under other module heads, so the density table leaves them to the capture.
let LAYOUT_ROW_SUFFIXES <- ["@source-cut", "@single"]

//! Whether `row` is a Lua program in a non-default layout.
def layout_row(row : string) : bool {
    for (suffix in LAYOUT_ROW_SUFFIXES) {
        if (row |> ends_with(suffix)) {
            return true
        }
    }
    return false
}

//! The suffixes of a row converted under an opt-in (`--inline-helpers`, `--switch-dispatch goto`,
//! `--checks off`, `--past-end inline`, `--fn-macros expand`): its readability price, which the `all` column leaves out, so the default's total moves only with
//! the default.
let OPT_IN_ROW_SUFFIXES <- ["@inline", "@goto", "@checks-off", "@past-end-inline", "@fn-macros-expand"]

//! Whether `row` is converted under an opt-in.
def opt_in_row(row : string) : bool {
    for (suffix in OPT_IN_ROW_SUFFIXES) {
        if (row |> ends_with(suffix)) {
            return true
        }
    }
    return false
}

//! The c-testsuite inputs the gate re-measures against the capture's `sample`: a switch with
//! character literals and comments, defines, a plain switch.
let SAMPLE_KEYS <- ["c_testsuite/00085", "c_testsuite/00181", "c_testsuite/00182", "c_testsuite/00215"]

//! The column of the mean over the rows.
let ALL = "all"

//! The density column pooled over the programs: `LUA_PROGRAM_ROW` and every compare project, each
//! weighing its code lines, so the column is the programs' sites per thousand lines of output.
let PROGRAMS = "programs"

//! Whether `row` pools into the `programs` column.
def in_programs(row : string) : bool => row == LUA_PROGRAM_ROW || row |> starts_with(PROJECT_PREFIX)

//! A compliance a criterion has no measure of: its denominator is zero.
let NOT_APPLICABLE = -1.0lf

//! The row an input key counts in: a Lua, project or hand-port key is its own row, a suite key its
//! suite's.
def row_of(key : string) : string => key |> starts_with("lua/") || key |> starts_with(PROJECT_PREFIX) || key |> starts_with(HAND_PREFIX) || find(key, "/") < 0 ? key : slice(key, 0, find(key, "/"))

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

//! The densities, each a count of sites per thousand das code lines, in the order of the table: what
//! the das text spells first, then what the C source had and the output lost.
let DENSITIES <- ["casts", "literal_casts", "addr", "deref", "reinterpret", "string_casts", "temp_names", "stray_braces", "labels", "switch_machinery", "setjmp_loops", "qualified_calls", "c_renames", "bool_roundtrip", "lost_parens", "literal_arithmetic", "long_lines", "layout_checks", "lost_comments", "unnamed_constants", "macro_expansions", "lost_chars", "blowup_lines", "excess_repeats"]

//! The densities a C source is needed for: not applicable where a row has no C code lines, the
//! hand-written ports among them.
let C_SIDE_DENSITIES <- ["lost_comments", "unnamed_constants", "macro_expansions", "lost_chars", "blowup_lines", "excess_repeats"]

//! The total of the densities read off the das text alone, the one a hand-written port has too.
let DAS_SIDE = "das_side"

//! The total of every applicable density.
let TOTAL = "total"

let private DENSITY_SITES <- {"casts" => "cast_sites", "literal_casts" => "literal_cast_lines", "addr" => "addr_sites", "deref" => "deref_sites", "reinterpret" => "reinterpret_casts_sites", "string_casts" => "das_string_reinterprets", "temp_names" => "temp_name_sites", "stray_braces" => "stray_braces_sites", "labels" => "label_stubs_sites", "setjmp_loops" => "setjmp_loops", "qualified_calls" => "qualified_calls_sites", "c_renames" => "c_renames_sites", "bool_roundtrip" => "bool_roundtrip_sites", "lost_parens" => "lost_parens_sites", "literal_arithmetic" => "literal_arithmetic_sites", "long_lines" => "long_lines", "layout_checks" => "layout_check_lines", "blowup_lines" => "blowup_lines"}

// what the C source had that the output lost: the C count less the das count that kept it
def private lost(c : table<string; int>; had, kept : string) : double => max(raw(c, had) - raw(c, kept), 0.0lf)

//! The sites of one density in a row's raw counts.
def density_sites(criterion : string; c : table<string; int>) : double {
    if (key_exists(DENSITY_SITES, criterion)) {
        return raw(c, DENSITY_SITES?[criterion] ?? "")
    } elif (criterion == "switch_machinery") {
        return raw(c, "flag_switches") + raw(c, "flag_lines") + raw(c, "goto_state_lines")
    } elif (criterion == "lost_comments") {
        return lost(c, "c_comment_lines", "das_comments_carried")
    } elif (criterion == "unnamed_constants") {
        return lost(c, "c_constant_uses", "das_constant_names")
    } elif (criterion == "macro_expansions") {
        return lost(c, "c_macro_calls", "das_macro_calls")
    } elif (criterion == "lost_chars") {
        return lost(c, "c_char_literals", "das_char_literals")
    } elif (criterion == "excess_repeats") {
        let c_lines = raw(c, "c_code_lines")
        let own_share = c_lines <= 0.0lf ? 0.0lf : raw(c, "c_repeated_lines") / c_lines
        return max(raw(c, "das_repeated_lines") - own_share * raw(c, "das_code_lines"), 0.0lf)
    }
    return NOT_APPLICABLE
}

//! One density over a row's raw counts: its sites per thousand das code lines; `NOT_APPLICABLE` on
//! no das code, for a C-side density on no C code, and for a name no density has.
[arch(at="ARCHITECTURE_CRITERIA.md#density")]
def density(criterion : string; c : table<string; int>) : double {
    let lines = raw(c, "das_code_lines")
    if (lines <= 0.0lf || !has_value(DENSITIES, criterion) || (has_value(C_SIDE_DENSITIES, criterion) && raw(c, "c_code_lines") <= 0.0lf)) {
        return NOT_APPLICABLE
    }
    return 1000.0lf * density_sites(criterion, c) / lines
}

//! The sum of the applicable values, `NOT_APPLICABLE` when none is.
def sum_applicable(values : array<double>) : double {
    var sum = 0.0lf
    var n = 0
    for (v in values) {
        if (v >= 0.0lf) {
            sum += v
            n++
        }
    }
    return n == 0 ? NOT_APPLICABLE : sum
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

//! One capture: the raw counts per row, the raw counts of the sample inputs the gate re-measures,
//! and, for a capture read as a delta's base, the raw keys its text predates.
struct CriteriaCapture {
    rows : table<string; table<string; int>>
    sample : table<string; table<string; int>>
    lacks : array<string>
}

//! Whether the row `row` counts in the `all` column: an opt-in's row is its readability price, a
//! compare project's may cover only the files that convert alone and a hand-written port is no
//! output, so the `all` column keeps the default output of the Lua programs and the suites.
def in_all(row : string) : bool => !opt_in_row(row) && !(row |> starts_with(PROJECT_PREFIX)) && !(row |> starts_with(HAND_PREFIX))

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
    var all <- {for (cr in CRITERIA); cr => mean_applicable([for (row in keys(out)); out?[row]?[cr] ?? NOT_APPLICABLE; where in_all(row)])}
    out[ALL] <- all
    return <- out
}

//! A column's total: the unweighted mean of its applicable criteria.
def column_total(column : table<string; double>) : double => mean_applicable([for (cr in CRITERIA); column?[cr] ?? NOT_APPLICABLE])

// a density column with its two totals: every applicable density summed, and the das-side ones
def private density_column(c : table<string; int>) : table<string; double> {
    var column <- {for (cr in DENSITIES); cr => density(cr, c)}
    column[TOTAL] = sum_applicable([for (cr in DENSITIES); column?[cr] ?? NOT_APPLICABLE])
    column[DAS_SIDE] = sum_applicable([for (cr in DENSITIES); column?[cr] ?? NOT_APPLICABLE; where !has_value(C_SIDE_DENSITIES, cr)])
    return <- column
}

//! The density of every criterion per row with the row's totals, and the `programs` column: the
//! program rows' raw counts pooled, so each weighs its lines of output.
[arch(at="ARCHITECTURE_CRITERIA.md#density")]
def density_table(cap : CriteriaCapture) : table<string; table<string; double>> {
    var out : table<string; table<string; double>>
    var programs : array<table<string; int>>
    for (row in ROWS) {
        cap.rows |> get(row) $(c) {
            out[row] <- density_column(c)
            if (in_programs(row)) {
                programs |> push_clone(c)
            }
        }
    }
    if (!empty(programs)) {
        out[PROGRAMS] <- density_column(sum_raw(programs, array<int>(), array<int>()))
    }
    return <- out
}

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
    let densities <- density_table(cap)
    var density_columns <- [for (row in ROWS); row; where key_exists(densities, row)]
    if (key_exists(densities, PROGRAMS)) {
        density_columns |> push(PROGRAMS)
    }
    var density_entries : array<tuple<key : string; text : string>>
    for (col in density_columns) {
        densities |> get(col) $(column) {
            var inscope cells <- [for (cr in DENSITIES); (key = cr, text = percent_text(column?[cr] ?? NOT_APPLICABLE))]
            cells |> push((key = TOTAL, text = percent_text(column?[TOTAL] ?? NOT_APPLICABLE)))
            cells |> push((key = DAS_SIDE, text = percent_text(column?[DAS_SIDE] ?? NOT_APPLICABLE)))
            density_entries |> push((key = col, text = object_text(cells, true)))
        }
    }
    let sample_keys <- sorted([for (k in keys(cap.sample)); k])
    return "\{\n  \"compliance\": {object_text(compliance_entries, false)},\n  \"density\": {object_text(density_entries, false)},\n  \"raw\": {raw_lines(cap.rows, ROWS)},\n  \"sample\": {raw_lines(cap.sample, sample_keys)},\n  \"totals\": {object_text(total_entries, false)}\n\}\n"
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

//! The macro keys of the converter's fold verdicts (`ConvertResult.fold_counts`, a site counted once
//! per module) into `counts`: every outermost expansion, the folded ones, and the ones left expanded
//! because an argument the body does not evaluate unconditionally may fault (ruling 38 addendum 14).
[arch(at="ARCHITECTURE_CRITERIA.md#criteria")]
def fold_counts(verdicts : table<string; int>; var counts : table<string; int>) {
    var sites = 0
    for (n in values(verdicts)) {
        sites += n
    }
    counts["macro_sites"] = sites
    counts["macro_folded"] = verdicts?["folded"] ?? 0
    counts["macro_faulting"] = verdicts?["faulting"] ?? 0
}

//! The raw keys a capture recorded before they existed lacks: a base the delta reads them as 0,
//! and the density delta says so when the base lacks a density's key.
let LATER_RAW_KEYS <- ["c_files", "c_files_converted", "addr_sites", "blowup_lines", "c_macro_calls", "cast_sites", "das_macro_calls", "deref_sites", "fn_lines_max", "fn_lines_median", "fn_lines_p90", "fn_long", "fn_p90_x100", "fn_total", "literal_cast_lines", "temp_name_sites", "macro_faulting", "macro_folded", "macro_sites"]

//! The top-level keys a capture recorded before the `density` section existed may lack.
let LATER_SECTIONS <- ["density"]

// the key of `LATER_RAW_KEYS` the finding `f` reports lacking, "" for any other finding
def private lacked_key(f : string) : string {
    for (k in LATER_RAW_KEYS) {
        if (f |> ends_with(" lacks `{k}`")) {
            return k
        }
    }
    for (k in LATER_SECTIONS) {
        if (f == "the missing section `{k}`") {
            return k
        }
    }
    return ""
}

//! The capture `text` holds as the base of a delta, read from `path`: a capture recorded before a
//! key of `LATER_RAW_KEYS` or a section of `LATER_SECTIONS` existed reads with the key 0 and names it
//! in `lacks`; empty with `error` on any other finding.
def base_capture_of_text(text, path : string; var error : string&) : CriteriaCapture {
    var lacks, findings : array<string>
    for (f in check_criteria(text)) {
        let k = lacked_key(f)
        if (empty(k)) {
            findings |> push(f)
        } elif (!has_value(lacks, k)) {
            lacks |> push(k)
        }
    }
    if (!empty(findings)) {
        error = "{path}: {join(findings, "; ")}"
        return <- CriteriaCapture()
    }
    var cap <- read_criteria(text, error)
    cap.lacks <- lacks
    return <- cap
}

//! The capture in the file at `path`, empty with `error` when it is missing, not JSON or misshapen.
def capture_at(path : string; var error : string&) : CriteriaCapture {
    if (!fexist(path)) {
        error = "{path} is missing"
        return <- CriteriaCapture()
    }
    return <- capture_of_text(fread(path), path, error)
}

//! The capture `text` holds, read from `path`; empty with `error` when it is not JSON or misshapen.
def capture_of_text(text, path : string; var error : string&) : CriteriaCapture {
    let findings <- check_criteria(text)
    if (!empty(findings)) {
        error = "{path}: {join(findings, "; ")}"
        return <- CriteriaCapture()
    }
    return <- read_criteria(text, error)
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

//! The findings of the capture's shape: the five top-level keys, every row a known one with every
//! raw count a non-negative integer, and the text the writer's own spelling of its raw counts,
//! which makes every percentage, density and total the formulas' value.
def check_criteria(text : string) : array<string> {
    var findings : array<string>
    var error : string
    let js = read_json(text, error)
    if (js == null || !(js is _object)) {
        findings |> push("not a JSON object: {error}")
        return <- findings
    }
    for (k in keys(js as _object)) {
        if (!has_value(["compliance", "density", "raw", "sample", "totals"], k)) {
            findings |> push("the unknown top-level key `{k}`")
        }
    }
    for (k in LATER_SECTIONS) {
        if (!key_exists(js, k)) {
            findings |> push("the missing section `{k}`")
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
    return render_columns(table_, columns)
}

//! The criteria table of the capture's row `row` alone, its total last.
def render_row_criteria(cap : CriteriaCapture; row : string) : string => render_columns(compliance_table(cap), [row])

//! What the capture's row `row` measured: the whole program's C files, or the files that convert
//! alone out of all; "" for a row the capture lacks.
def coverage_text(cap : CriteriaCapture; row : string) : string {
    if (!key_exists(cap.rows, row)) {
        return ""
    }
    let all = cap.rows?[row]?["c_files"] ?? 0
    let converted = cap.rows?[row]?["c_files_converted"] ?? 0
    let files = all == 1 ? "C file" : "C files"
    return converted == all ? "the whole program, its {all} {files}" : "the {converted} of {all} {files} that convert alone, since the program does not convert whole; the other files are in no count, so these criteria describe only the converted files"
}

// the criteria table over `columns` of `table_`, the totals last
def private render_columns(table_ : table<string; table<string; double>>; columns : array<string>) : string {
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

//! The columns of the density and length tables: every measured row but the Lua layouts and opt-ins,
//! then `programs`, then the hand-written ports.
def density_columns(table_ : table<string; table<string; double>>) : array<string> {
    var columns <- [for (row in ROWS); row; where key_exists(table_, row) && !opt_in_row(row) && !layout_row(row) && !(row |> starts_with(HAND_PREFIX))]
    if (key_exists(table_, PROGRAMS)) {
        columns |> push(PROGRAMS)
    }
    columns |> push_from([for (row in ROWS); row; where key_exists(table_, row) && row |> starts_with(HAND_PREFIX)])
    return <- columns
}

//! The density table: a row per density, a column per `density_columns`, the two totals last.
def render_density(cap : CriteriaCapture) : string {
    let table_ <- density_table(cap)
    let columns <- density_columns(table_)
    var rows <- [for (cr in DENSITIES); criterion_cells(cr, columns, table_)]
    rows |> reserve(length(rows) + 2)
    for (total in [[TOTAL, "**total**"], [DAS_SIDE, "**das-side**"]]) {
        var line <- [total[1]]
        line |> push_from([for (col in columns); "**{cell(table_?[col]?[total[0]] ?? NOT_APPLICABLE)}**"])
        rows |> emplace(line)
    }
    var header <- ["Per 1000 lines"]
    header |> push_from(columns)
    var align <- [ColAlign.left]
    align |> push_from([for (_col in columns); ColAlign.right])
    return render_md_table(header, align, rows)
}

def private ratio_cell(c : table<string; int>; key : string) : string => (c?["fn_matched"] ?? 0) == 0 ? "n/a" : "{fmt(":.2f", double(c?[key] ?? 0) / 100.0lf)}x"

//! The length table: per column of `density_columns` but `programs` (a pooled percentile needs the
//! functions, which the capture does not keep), the das functions, their body lines' median, 90th
//! percentile and longest, the ones past `LONG_FUNCTION` lines, the matched functions' das-to-C
//! ratio median, 90th percentile and worst, then the outermost function-like macro expansions, the
//! ones printed as a call of their def and, on a line of their own, the ones an argument that may
//! fault keeps expanded (`fold_counts`).
def render_lengths(cap : CriteriaCapture) : string {
    let columns <- [for (col in density_columns(density_table(cap))); col; where col != PROGRAMS]
    let lines <- [["functions", "fn_total"], ["median lines", "fn_lines_median"], ["p90 lines", "fn_lines_p90"], ["longest", "fn_lines_max"], ["over {LONG_FUNCTION} lines", "fn_long"]]
    let ratios <- [["das/C median", "fn_median_x100"], ["das/C p90", "fn_p90_x100"], ["das/C worst", "fn_worst_x100"]]
    let macros <- [["macro sites", "macro_sites"], ["macro sites folded", "macro_folded"], ["faulting arguments", "macro_faulting"]]
    var rows : array<array<string>>
    rows |> reserve(length(lines) + length(ratios) + length(macros))
    for (ln in lines) {
        var line <- [ln[0]]
        line |> push_from([for (col in columns); "{cap.rows?[col]?[ln[1]] ?? 0}"])
        rows |> emplace(line)
    }
    for (r in ratios) {
        var line <- [r[0]]
        line |> push_from([for (col in columns); ratio_cell(cap.rows?[col] ?? default<table<string; int>>, r[1])])
        rows |> emplace(line)
    }
    for (m in macros) {
        var line <- [m[0]]
        line |> push_from([for (col in columns); "{cap.rows?[col]?[m[1]] ?? 0}"])
        rows |> emplace(line)
    }
    var header <- ["Function lengths"]
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

//! The raw counts of `rows` summed key by key, the distributions excepted: those are taken over
//! `ratios` (the pooled per-function ratios, sorted) and `lengths` (the pooled function lengths).
def sum_raw(rows : array<table<string; int>>; ratios, lengths : array<int>) : table<string; int> {
    var out <- {for (k in RAW_KEYS); k => 0}
    for (r in rows) {
        for (k in RAW_KEYS) {
            out[k] += r?[k] ?? 0
        }
    }
    distribution_counts(ratios, lengths, out)
    return <- out
}

//! What a base may lack and still give a density delta: the coverage counts, which no density
//! reads, and the `density` section, which the raw counts rebuild.
let DENSITY_FREE_KEYS <- ["c_files", "c_files_converted", "density"]

//! The density delta table over the `programs` column: per density `base`'s value, this capture's
//! and the signed difference, the totals last; or the line saying the base predates a density's key.
def render_density_delta(base, now : CriteriaCapture) : string {
    let predates <- [for (k in base.lacks); k; where !has_value(DENSITY_FREE_KEYS, k)]
    if (!empty(predates)) {
        return "no density delta: the base capture predates the keys {join(predates, ", ")}\n"
    }
    let before <- density_table(base)
    let after <- density_table(now)
    var rows <- [for (cr in DENSITIES); delta_cells(cr, before?[PROGRAMS]?[cr] ?? NOT_APPLICABLE, after?[PROGRAMS]?[cr] ?? NOT_APPLICABLE)]
    rows |> reserve(length(rows) + 2)
    for (total in [[TOTAL, "**total**"], [DAS_SIDE, "**das-side**"]]) {
        let b = before?[PROGRAMS]?[total[0]] ?? NOT_APPLICABLE
        let a = after?[PROGRAMS]?[total[0]] ?? NOT_APPLICABLE
        rows |> emplace([total[1], "**{cell(b)}**", "**{cell(a)}**", b < 0.0lf || a < 0.0lf ? "n/a" : "**{signed(a - b)}**"])
    }
    return render_md_table(["Per 1000 lines", "main", "now", "delta"], [ColAlign.left, ColAlign.right, ColAlign.right, ColAlign.right], rows)
}

//! The worker file: `ok`, a `<raw key> <count>` line per raw key, `ratios` with the per-function
//! ratios and `lengths` with the function lengths; or `error <first line>`.
def result_text(raw : CriteriaRaw; error : string) : string {
    if (!empty(error)) {
        return "error {replace(error, "\n", " ")}\n"
    }
    let counts = join([for (k in RAW_KEYS); "{k} {raw.counts?[k] ?? 0}"], "\n")
    let ratios = join([for (r in raw.ratios); "{r}"], " ")
    let lengths = join([for (n in raw.lengths); "{n}"], " ")
    return "ok\n{counts}\nratios {ratios}\nlengths {lengths}\n"
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
        } elif (words[0] == "lengths") {
            raw.lengths <- [for (w in words); to_int(w); where w != "lengths" && !empty(w)]
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

